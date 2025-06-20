#!/bin/bash

# Default values for script execution
# These variables can be changed based on customer environment settings
RELEASE_SERVICE=${RELEASE_SERVICE:-"Helm"}
CONTAINER_SECURITY_NAME=${CONTAINER_SECURITY_NAME:-"trendmicro-container-security"}
SOURCE_NAMESPACE=${SOURCE_NAMESPACE:-"trendmicro-system"}
ARGOCD_NAMESPACE="argocd"

if ! command -v kubectl &> /dev/null; then
    echo "No kubectl command found, exiting..."
    exit 1
fi

check_namespace_exists() {
  local namespace="$1"

  if kubectl get namespace "$namespace" &>/dev/null; then
    return 0
  else
    return 1
  fi
}

has_post_delete_finalizers() {
  local app_name="$1"

  local finalizers=$(kubectl get application "${app_name}" -n $ARGOCD_NAMESPACE -o jsonpath='{.metadata.finalizers}' 2>/dev/null)

  if [[ "$finalizers" == *"post-delete-finalizer"* ]]; then
    return 0
  else
    return 1
  fi
}

cleanup_image_pull_secrets() {
  local success=true

  local label_selector="app.kubernetes.io/managed-by=$RELEASE_SERVICE,app.kubernetes.io/name=$CONTAINER_SECURITY_NAME"

  local namespaces
  namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')

  for namespace in $namespaces; do
    if [ "$namespace" = $SOURCE_NAMESPACE ]; then
      continue
    fi

    local secrets
    secrets=$(kubectl get secrets -n "$namespace" -l "$label_selector" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

    if [ -n "$secrets" ]; then
      for secret in $secrets; do
        kubectl delete secret -n "$namespace" "$secret"

        if [ $? -ne 0 ]; then
          echo "[Secret] Failed to delete: $secret in namespace: $namespace"
          success=false
        else
          echo "[Secret] Successfully deleted: $secret in namespace: $namespace"
        fi
      done
    else
      echo "[Secret] No secrets found in namespace $namespace, nothing to delete"
    fi
  done

  if [ "$success" = true ]; then
    return 0
  else
    return 1
  fi
}

cleanup_post_delete_resources() {
  local success=true
  local label_selector="app.kubernetes.io/part-of=trendmicro-container-security"

  if ! check_namespace_exists "$SOURCE_NAMESPACE"; then
    echo "Source namespace $SOURCE_NAMESPACE does not exist, nothing to delete"
    return 0
  fi

  local sa_list=$(kubectl get serviceaccounts -n "$SOURCE_NAMESPACE" -l "$label_selector" -o jsonpath="{.items[*].metadata.name}" 2>/dev/null)

  if [ -n "$sa_list" ]; then
    for sa in $sa_list; do
      kubectl delete serviceaccount -n "$SOURCE_NAMESPACE" "$sa"
      if [ $? -ne 0 ]; then
        echo "[ServiceAccount] Failed to delete Service Account: $sa"
        success=false
      else
        echo "[ServiceAccount] Successfully deleted: $sa"
      fi
    done
  else
    echo "[ServiceAccount] No service accounts found in namespace $SOURCE_NAMESPACE, nothing to delete"
  fi

  local crb_list=$(kubectl get clusterrolebinding -l "$label_selector" -o jsonpath="{.items[*].metadata.name}" 2>/dev/null)

  if [ -n "$crb_list" ]; then
    for crb in $crb_list; do
      kubectl delete clusterrolebinding "$crb"
      if [ $? -ne 0 ]; then
        echo "[ClusterRoleBinding] Failed to delete: $crb"
        success=false
      else
        echo "[ClusterRoleBinding] Successfully deleted: $crb"
      fi
    done
  else
    echo "[ClusterRoleBinding] No cluster role bindings found, nothing to delete"
  fi

  local cr_list=$(kubectl get clusterrole -l "$label_selector" -o jsonpath="{.items[*].metadata.name}" 2>/dev/null)

  if [ -n "$cr_list" ]; then
    for cr in $cr_list; do
      kubectl delete clusterrole "$cr"
      if [ $? -ne 0 ]; then
        echo "[ClusterRole] Failed to delete: $cr"
        success=false
      else
        echo "[ClusterRole] Successfully deleted: $cr"
      fi
    done
  else
    echo "[ClusterRole] No cluster roles found, nothing to delete"
  fi

  if [ "$success" = true ]; then
    return 0
  else
    return 1
  fi
}

delete_crds() {
  local GROUP_NAMES=(
    "cloudone.trendmicro.com"
    "visionone.trendmicro.com"
    "container-security.trendmicro.com"
  )

  for GROUP in "${GROUP_NAMES[@]}"; do
    echo "[CRD] Looking for CRDs in group: $GROUP"

    local GROUP_CRDS=$(kubectl get crd -o jsonpath="{.items[?(@.spec.group=='$GROUP')].metadata.name}" 2>/dev/null)

    if [ -z "$GROUP_CRDS" ]; then
      echo "[CRD] No CRDs found for group: $GROUP"
      continue
    fi

    read -ra CRD_ARRAY <<< "$GROUP_CRDS"

    for CRD_NAME in "${CRD_ARRAY[@]}"; do
      # Remove finalizers from all CRs of this CRD before deleting the CRD itself
      local KIND=$(kubectl get crd "$CRD_NAME" -o jsonpath="{.spec.names.kind}" 2>/dev/null)
      if [ -n "$KIND" ]; then
        local RESOURCES=$(kubectl get "$CRD_NAME" --all-namespaces -o jsonpath="{range .items[*]}{.metadata.namespace}{','}{.metadata.name}{'\n'}{end}" 2>/dev/null)
        while IFS= read -r line; do
          ns=$(echo "$line" | cut -d',' -f1)
          name=$(echo "$line" | cut -d',' -f2)
          if [ -n "$name" ]; then
            if [ -n "$ns" ]; then
              kubectl patch "$CRD_NAME" "$name" -n "$ns" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null
            else
              kubectl patch "$CRD_NAME" "$name" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null
            fi
          fi
        done <<< "$RESOURCES"
      fi

      kubectl delete crd "$CRD_NAME"
      if [ $? -eq 0 ]; then
        echo "[CRD] Successfully deleted $CRD_NAME"
      else
        echo "[CRD] Failed to delete $CRD_NAME"
        return 1
      fi
    done
  done

  return 0
}

cleanup_jobs() {
  local success=true

  if ! check_namespace_exists "$SOURCE_NAMESPACE"; then
    echo "Source namespace $SOURCE_NAMESPACE does not exist, skipping cleanup"
    return 0
  fi

  local jobs=$(kubectl get jobs -n "$SOURCE_NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

  if [ -n "$jobs" ]; then
    for job in $jobs; do
      kubectl delete job -n "$SOURCE_NAMESPACE" "$job"

      if [ $? -ne 0 ]; then
        echo "[Job] Failed to delete job: $job"
        success=false
      else
        echo "[Job] Successfully deleted job: $job"
      fi
    done
  else
    echo "[Job] No jobs found in namespace $SOURCE_NAMESPACE, nothing to delete"
  fi

  if [ "$success" = true ]; then
    return 0
  else
    return 1
  fi
}

# start
if check_namespace_exists "$ARGOCD_NAMESPACE"; then
  echo "ArgoCD namespace found. Checking if applications are stuck in deleting state..."

  app_names=($(kubectl get applications -n $ARGOCD_NAMESPACE -o jsonpath='{.items[*].metadata.name}'))

  if [ ${#app_names[@]} -eq 0 ]; then
    echo "No ArgoCD applications found."
  else
    for app_name in "${app_names[@]}"; do
      if has_post_delete_finalizers "$app_name"; then

        finalizers=$(kubectl get application "$app_name" -n $ARGOCD_NAMESPACE -o jsonpath='{.metadata.finalizers}')

        deletion_timestamp=$(kubectl get application "$app_name" -n $ARGOCD_NAMESPACE -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null)

        if [ -n "$deletion_timestamp" ]; then
          echo -e "\nThe application is stuck in deletion state (has deletionTimestamp)."
          echo "Do you want to remove post-delete finalizers for application '$app_name' to allow successful deletion? (y/n)"
          read proceed

          if [[ "$proceed" =~ ^[Yy]$ ]]; then
            kubectl patch application "$app_name" -n $ARGOCD_NAMESPACE -p '{"metadata":{"finalizers":null}}' --type=merge

            if [ $? -eq 0 ]; then
              echo "Successfully removed finalizers from $app_name"
            else
              echo "Failed to remove finalizers from $app_name"
            fi
          fi
        fi
      fi
    done

  fi
else
  echo "ArgoCD namespace not found. Cannot proceed with ArgoCD application cleanup."
fi

echo -e "\nStarting Trend Micro Container Security cleanup process...\n"

echo "This script will attempt to delete the following Trend Micro leftover resources (if they exist):"
echo "  - Image pull secrets"
echo "  - Custom Resource Definitions (CRDs)"
echo "  - Service accounts, Cluster role bindings, and Cluster roles"
echo "  - Jobs in the $SOURCE_NAMESPACE namespace"
echo -e "\nProceed with cleanup? (y/n)"
read -r cleanup_confirm

if [[ ! "$cleanup_confirm" =~ ^[Yy]$ ]]; then
  echo -e "\nCleanup cancelled by user."
  exit 0
fi

echo -e "\nProceeding with cleanup...\n"

echo "Cleaning up image pull secrets..."
cleanup_image_pull_secrets
secret_cleanup_status=$?

echo -e "\nDeleting custom resource definitions..."
delete_crds
crd_cleanup_status=$?

echo -e "\nCleaning up service accounts, cluster role bindings, clusterroles...."
cleanup_post_delete_resources
post_delete_cleanup_status=$?

echo -e "\nCleaning up jobs..."
cleanup_jobs
cleanup_jobs_status=$?

if [ $secret_cleanup_status -eq 0 ] && [ $crd_cleanup_status -eq 0 ] && [ $post_delete_cleanup_status -eq 0 ] && [ $cleanup_jobs_status -eq 0 ]; then
  echo -e "\nArgoCD Cleanup completed successfully!"
else
  echo -e "\nArgoCD Cleanup completed with some errors. Please check the logs above."
  exit 1
fi

exit 0