# How to upgrade from cloudone-container-security-helm

The upgrade process is different whether your cluster was manually registered or automatically registered.

Firewall rules changes are required, you can find the updated list of firewall exceptions required for Trend Vision One Container Security in the official [documentation](https://docs.trendmicro.com/en-us/documentation/article/trend-vision-one-firewall-exception-requirements-for)

## Manually registered clusters

Manual changes to the Helm values are required before upgrading if your installation is using the [cloudone-container-security-helm](https://github.com/trendmicro/cloudone-container-security-helm) Helm chart.

To obtain the new values:
- Navigate to the Trend Micro Vision One Container Security console using https://portal.xdr.trendmicro.com/index.html#/app/server-cloud/container-inventory.
- Click on your cluster under the Kubernetes section.
- The cluster description page will have a banner with a "How to upgrade" button. Click on it to get the new values and follow the upgrade instructions.

As an alternative, you can also get a bootstrap token for an existing cluster using the [public API](https://automation.trendmicro.com/xdr/api-beta/#tag/Kubernetes-Clusters). Please note that for now the API is only available in the beta version.

If you are using the `useExistingSecrets.containerSecurityAuth` option, you must now name the secret `trendmicro-container-security-bootstrap-token` with the key `bootstrap.token` set to the bootstrap token value. The bootstrap token expires after 24 hours, so you must have Container Security installed within that time frame.

### Upgrade instructions
Note that these instructions are the same as the ones shown in the console.

If you don’t have the values you used for your initial installation anymore, you can get them with the following command:
```bash
helm get values --namespace trendmicro-system trendmicro  -o yaml
```
Copy these values to an overrides file (e.g. overrides.yaml).

Replace the following values:
```yaml
cloudOne:
    apiKey: <your api key>
    endpoint: <endpoint>
```
with the values that will be displayed in V1 console once you click on the “How to upgrade” button. You can also get these values with the public API (see above).
The new values will look like this:
```yaml
visionOne:
  bootstrapToken: <new bootstrap token>
  endpoint: <new endpoint>
```

- `boostrapToken` replaces apiKey. The token displayed in the console expires after a day, so you need to run the upgrade within that time. If you don’t, you can click again on the “How to upgrade” button to get a new token. There is no need to update the token after that, it will be automatically renewed by Container Security components. The API key from earlier Helm chart versions will not work anymore.
- `endpoint` has been updated to a new URL

Run the following command to upgrade:
```bash
helm upgrade \
    trendmicro \
    --namespace trendmicro-system \
    --values overrides.yaml \
    https://github.com/trendmicro/visionone-container-security-helm/archive/main.tar.gz
```

## Automatically registered clusters

If you don’t have the values you used for your initial installation anymore, you can get them with the following command:
```bash
helm get values --namespace trendmicro-system trendmicro  -o yaml
```
Copy these values to an overrides file (e.g. overrides.yaml).

The `endpoint` value has changed, the following list shows the new value for each region:
- Americas:  https://api.xdr.trendmicro.com/external/v2/direct/vcs/external/vcs
- Europe:  https://api.eu.xdr.trendmicro.com/external/v2/direct/vcs/external/vcs
- Japan:  https://api.xdr.trendmicro.co.jp/external/v2/direct/vcs/external/vcs
- Australia: https://api.au.xdr.trendmicro.com/external/v2/direct/vcs/external/vcs
- India:  https://api.in.xdr.trendmicro.com/external/v2/direct/vcs/external/vcs
- Singapore:  https://api.sg.xdr.trendmicro.com/external/v2/direct/vcs/external/vcs
- Middle East and Africa: https://api.mea.xdr.trendmicro.com/external/v2/direct/vcs/external/vcs

Replace the following values:
```yaml
cloudOne:
    endpoint: <old endpoint>
```
with these values:
```yaml
visionOne:
  endpoint: <new endpoint from the list above>  # Replace with the appropriate endpoint based on your region
```

- `endpoint` has been updated to a new URL

Run the following command to upgrade:
```bash
helm upgrade \
    trendmicro \
    --namespace trendmicro-system \
    --values overrides.yaml \
    https://github.com/trendmicro/visionone-container-security-helm/archive/main.tar.gz
```

For support assistance, please contact Trend Micro Technical Support
