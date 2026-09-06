# Configure pod priority for the Container Security components

By default, all V1CS component pods run at Pod Priority 0 — the same as ordinary application workloads. Under node resource pressure, the kubelet preferentially evicts the lowest-priority pods first, so V1CS components can be evicted exactly when they're needed most.

To protect against this, the chart can optionally create one chart-owned `PriorityClass`, shared by all V1CS components so none is left unprotected relative to another:

| Class name | Priority Value | preemptionPolicy | globalDefault |
|---|---|---|---|
| `trendmicro-v1cs-security` | `10,000,000` | `PreemptLowerPriority` | `false` |

- `globalDefault: false` — only V1CS pods that explicitly reference the class get elevated priority; no other cluster workload is affected.
- `preemptionPolicy: PreemptLowerPriority` — if a V1CS pod can't find a free node, it may evict a running lower-priority pod to gain a slot. Note this doesn't change the memory-pressure eviction path: when a node runs low on memory, the kubelet evicts lowest-priority pods first, so raising V1CS priority makes lower-priority pods the ones evicted first. Weigh this trade-off before enabling on a shared cluster.
- `value` and `preemptionPolicy` are fixed by the chart and cannot be changed through `values.yaml` when `create: true`. If different settings are needed — for example a `preemptionPolicy` of `Never` so V1CS pods wait for a free slot instead of evicting another pod, or the cluster doesn't allow creating cluster-scoped resources (no permission on `priorityclasses.scheduling.k8s.io`) — set `priorityClassName.create: false`, create a custom `PriorityClass` with the required settings, and point `priorityClassName.default` (or the per-component keys) at it instead.

**RBAC prerequisite:** `PriorityClass` is cluster-scoped. Creating it requires `create`/`patch` permission on `priorityclasses.scheduling.k8s.io` — the installer identity must hold this when `priorityClassName.create` is `true`.

**How `create` relates to pod references:** `create` only controls whether the chart creates the PriorityClass resource. Pod references are controlled independently via `priorityClassName.default` and the per-component keys, regardless of `create` — whatever class they name must exist before installing.

## Examples

**Opt-in all V1CS components (recommended):**

```yaml
priorityClassName:
  create: true                            # creates the trendmicro-v1cs-security PriorityClass
  default: trendmicro-v1cs-security       # applies it to every V1CS component
```

**Opt-in core security path only (minimal, lower blast radius):**

```yaml
priorityClassName:
  create: true
  scout: trendmicro-v1cs-security
  admissionController: trendmicro-v1cs-security
```

**Bring a custom class** (e.g. RBAC-constrained environments without permission to create cluster-scoped objects):

```yaml
priorityClassName:
  create: false                                   # skip chart-owned PriorityClass creation
  default: my-existing-priority-class
```

**Default behaviour — full opt-out:** omit the `priorityClassName` block entirely. `create` defaults to `false` and no key is set, so no `PriorityClass` is created and no pod references one.

If `create: false` was previously set with per-component keys/`default` still pointing at the chart-owned class, clear those too (or omit the block) — otherwise pods will carry a `priorityClassName` the chart no longer creates and fail to schedule.

## Upgrade and lifecycle notes

- **On `helm upgrade`:** `priorityClassName` is immutable on a running pod. The first time a priority class is assigned to an existing install, affected pods are terminated and recreated — expected, not a defect.
- **Disabling `create` after enabling it deletes the object:** `helm upgrade`/`helm uninstall` prune resources the chart no longer renders, including `trendmicro-v1cs-security` — even if other pods/releases still reference it. Running pods are unaffected, but their *replacements* (on drain, upgrade, or crash) will fail to schedule with `no PriorityClass with name ... was found`.
- **Migrating to an independently managed class:** create the same name/value in a separate pipeline (GitOps, bootstrap chart, etc.), repoint `default`/per-component keys at it, confirm no pods reference the chart-owned name, then set `create: false`.
