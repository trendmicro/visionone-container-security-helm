# Import custom rules through OCI registry

## Configuration

TrendMicro helm chart can be configured to automatically download and install rules files from OCI artifacts.

This functionality is off by default.

To enable automatic installation of rules files from OCI repositories, add the following sections into overrides:

```yaml
visionOne:
...
  runtimeSecurity:
    enabled: true
    customRules:
      enabled: true
      ociRepository:
        enabled: true
        ruleFiles:
          - shell_in_container.yaml
          - falco_rules.yaml
        artifactUrls:
          - ghcr.io/your_rules_repo/falco-rules:latest
          - public.ecr.aws/your_rules_repo/falco-rules:latest
        basicAuthTokenSecretName: customrules-falcoctl-registry-auth-basic-missing-repo

```
**NOTE: these fields are subject to change**

Section `visionOne.runtimeSecurity.customRules.ociRepository.artifactUrls` is a list of OCI repository URLs to pull artifacts from.
For URL format, see [falcoctl push](https://github.com/falcosecurity/falcoctl?tab=readme-ov-file#falcoctl-registry-push).

Section `visionOne.runtimeSecurity.customRules.ociRepository.ruleFiles` is a list of filenames, to be continuously monitored as OCI artifacts.
Each file is expected to be a valid falco rule file. There is no restrictions on how files are distributed between artifacts. A single artifact may contain all listed files or multiple artifacts may contain some of them. falco ignores files not listed by `.ociRepository.ruleFiles`.

Consult [falcoctl registry](https://github.com/falcosecurity/falcoctl?tab=readme-ov-file#falcoctl-registry) for details how to push artifacts into OCI repo using falcoctl.

Section `visionOne.runtimeSecurity.customRules.ociRepository.basicAuthTokenSecretName` is a string naming a kubernetes secret inside `trendmicro-system` namespace. The secret is expected to include `falcoctl` key, its value is interpreted as basic auth credentials for private OCI repos. The format is the same as falcoctl env variable `FALCOCTL_REGISTRY_AUTH_BASIC`, described here [falcoctl environment variables](https://github.com/falcosecurity/falcoctl?tab=readme-ov-file#falcoctl-environment-variables).

Use of this secret:
- with `.artifactUrls` only listing public repos, this field may be empty string or just skipped
- with `.artifactUrls` listing some/all private repos, this field is required, the secret is required in the namespace `trendmicro-system`

NOTE: it's a deployment error if `.basicAuthTokenSecretName` is the secret specified but if that secret does not exist in namespace `trendmicro-system`.

NOTE: with `.basicAuthTokenSecretName` secret present but contains no key `falcoctl`, the scout pod will fail to start.

NOTE: with `.basicAuthTokenSecretName` secret present and contains key `falcoctl` but its value represents wrong credentials, falcoctl will not be able to install artifacts from private repos and falco will run with rules defined at deployment.

Optionally, section `.Values.scout.falco.ociRepository.logLevel` can be set to `info` to lower CPU impact. In this case `.output_fields.enabled_rules` will be empty.

## OCI repo

OCI artifact consists of one or more rulesfiles, packaged, pushed into OCI repo, tagged with versions.
See [artifact push](https://github.com/falcosecurity/falcoctl?tab=readme-ov-file#falcoctl-registry-push) for details.

## Artifact Versions

Falcoctl supports floating versions, i.e. every time version "0.1.0" is pushed, extra tags added "0" and "0.1". It allows `.ociRepository.artifactUrls` to specify major versions only, i.e. "float over" fully qualified tags/versions and pickup the most recent version without reconfiguration.
See [semver](https://semver.org/).

## Possible Issues

### Issue: help install/upgrade failed with `secret *** is expected`

Possible reason 1: secret `visionOne.runtimeSecurity.customRules.ociRepository.basicAuthTokenSecretName`
is missing from `trendmicro-system` namespace.

Solution: follow recommendations in Section `visionOne.runtimeSecurity.customRules.ociRepository.basicAuthTokenSecretName` on how to create the secret.

### Issue: scout pod status is `CreateContainerConfigError`

Additional info: cluster events include error `Error: couldn't find key falcoctl in Secret ...`

Possible reason: secret `visionOne.runtimeSecurity.customRules.ociRepository.basicAuthTokenSecretName`
contains no key `falcoctl`.

Solution: add key `falcoctl`, follow recommendations in Section `visionOne.runtimeSecurity.customRules.ociRepository.basicAuthTokenSecretName`

### Issue: OCI artifacts are not installed

Additional info: logs of container `falco-customrules` in `scout` pod show errors accessing OCI repo.

```sh
...
an error occurred while fetching descriptor from remote repository
...
```

or

```sh
...
Unable to pull config layer
...
```

Possible reason: secret `visionOne.runtimeSecurity.customRules.ociRepository.basicAuthTokenSecretName` is malformed or defines wrong password or defines wrong repo URL.

Solution: double check the format is the same as falcoctl env variable `FALCOCTL_REGISTRY_AUTH_BASIC`, described here [falcoctl environment variables](https://github.com/falcosecurity/falcoctl?tab=readme-ov-file#falcoctl-environment-variables).
Double check repo URL and password is valid.

## How It Works

With `runtimeSecurity.enabled` and `customRules.enabled`, additional pod `runtime-ruleloader` is spawned.

With `ociRepository.enabled` false, the pod `runtime-ruleloader` will use rules configured at deployment.

With `ociRepository.enabled` true, the pod `runtime-ruleloader` will do the following:
- run an instance of falcoctl, configured to watch/download/install OCI artifacts from `.ociRepository.artifactUrls` ( every 6 hours, hardcoded )

When new version of an artifact is available, falcoctl installs it into a directory shared with falco.
Falco detects changes in files listed by `.ociRepository.ruleFiles`, performs "hot restart". Changes on the rest of files are ignored.

"Hot restart" is performed in 3 steps:
- falco validates a syntax of all rules found in files listed by `.ociRepository.ruleFiles`
- when syntax valid, falco begings to monitor those rules ( assuming artifacts are accepted )
- when any rule syntax is invalid ( this includes all rules, not limited to most recent change ), falco ignores changes and continues with most recent good configuration ( assuming recently installed artifacts are ignored )

`artifacts accepted` and `artifacts ignored` events are emitted accordingly, see below.


