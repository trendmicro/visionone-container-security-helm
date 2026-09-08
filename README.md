# Vision One Container Security Helm Charts

This branch contains the packaged Helm chart repository for Vision One Container Security.

## Install

```sh
helm repo add trendmicro https://trendmicro.github.io/visionone-container-security-helm
helm repo update
helm search repo trendmicro --versions
helm install trendmicro trendmicro/trendmicro-container-security --version <version>
```

The Helm repository index is available at [https://trendmicro.github.io/visionone-container-security-helm/index.yaml](https://trendmicro.github.io/visionone-container-security-helm/index.yaml).
Published chart packages are stored in the [`packages/`](packages/) directory.
