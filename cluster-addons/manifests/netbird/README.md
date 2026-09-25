# NetBird

NetBird replaces the Tailscale operator for private access to the cluster:

- **Kubernetes API**: the `ClusterProxy` runs `netbird-kubeapi-proxy` peers. `kubectl` traffic is
  authenticated by NetBird identity and impersonated into Kubernetes RBAC (no tokens to hand out).
- **Internal services** (ArgoCD, Grafana, Longhorn, ...): the `NetworkRouter` runs routing peers and
  every `NetworkResource` publishes a ClusterIP service as `<service>.<namespace>.hwkn.internal`.
  Friendly names such as `argocd.hwkn.internal` are CNAMEs added by hand.

The operator itself is installed by the `netbird-operator` Application
(`cluster-addons/apps/templates/netbird-operator`) and needs cert-manager for its webhook certificate.

## One-time setup in the NetBird dashboard

The operator creates networks, resources, DNS records, setup keys and the groups defined in
`templates/10-groups.yaml`. It does **not** create users, user groups or access policies
(NetBird is deny-by-default), so these steps are manual:

1. **API token**: `Team > Service Users > Add service user` (role *Admin*), then create an access token.
   Store it as a SealedSecret in the `netbird` Application (it creates the `netbird` namespace; the operator pod waits for the secret):

   ```sh
   kubectl -n netbird create secret generic netbird-mgmt-api-key \
     --from-literal=NB_API_KEY='<token>' --dry-run=client -o yaml \
     | kubeseal --format yaml > cluster-addons/manifests/netbird/templates/05-netbird-mgmt-api-key.sealed.yaml
   ```

2. **User groups**: `Team > Groups`. Create and assign to users (groups are propagated to their peers):
   - `hwkn-team`: everyone who may reach internal services
   - `k8s-admins`: cluster-admin on the Kubernetes API
   - `k8s-readers`: read-only on the Kubernetes API

   The names must match `templates/21-cluster-rbac.yaml` exactly.

3. **DNS zone**: `DNS > Zones > Add Zone`
   - Domain: `hwkn.internal` (must match `spec.dnsZoneRef.name` in `templates/30-network-router.yaml`)
   - Distribution groups: `hwkn-team`
   - The operator adds one A record per `NetworkResource`, always named `<service>.<namespace>.hwkn.internal`.
   - Once those exist, add the friendly names as CNAME records (`Add Record`, type CNAME):

     | Name                     | Target                                                   |
     |--------------------------|----------------------------------------------------------|
     | `argocd.hwkn.internal`   | `argocd-server.argocd.hwkn.internal`                     |
     | `grafana.hwkn.internal`  | `kube-prometheus-stack-grafana.monitoring.hwkn.internal` |
     | `longhorn.hwkn.internal` | `longhorn-frontend.longhorn-system.hwkn.internal`        |

     The CNAMEs keep working when a service's ClusterIP changes, because the operator updates the
     A record they point to.

4. **Access policies**: `Access Control > Policies`. The destination groups `k8s-api-proxy` and
   `k8s-services` are created by the operator once it runs.

   | Name           | Source                     | Destination     | Protocol / ports |
   |----------------|----------------------------|-----------------|------------------|
   | k8s-api        | `k8s-admins`, `k8s-readers` | `k8s-api-proxy` | TCP 443          |
   | k8s-services   | `hwkn-team`           | `k8s-services`  | TCP 80           |

   Add ports to the `k8s-services` policy when exposing a service on another port.

## Client usage

Requires the NetBird client (`netbird` CLI) connected to the account.

```sh
netbird kubernetes list
netbird kubernetes write-kubeconfig hwkn-prod   # adds context "hwkn-prod" to ~/.kube/config
kubectl --context hwkn-prod get nodes
```

Internal services resolve on connected peers, e.g. `http://argocd.hwkn.internal`.

## Exposing another service

1. Add a `NetworkResource` to `templates/40-network-resources.yaml`, in the namespace of the
   (ClusterIP) service and referencing the router:

   ```yaml
   apiVersion: netbird.io/v1alpha1
   kind: NetworkResource
   metadata:
     name: metabase
     namespace: metabase
   spec:
     networkRouterRef:
       name: hwkn-prod
       namespace: netbird
     serviceRef:
       name: metabase
     groups:
       - name: k8s-services
   ```

2. After ArgoCD syncs, add a CNAME in the `hwkn.internal` zone:
   `metabase.hwkn.internal -> metabase.metabase.hwkn.internal`.
3. If the service listens on a port other than 80 (Metabase uses 3000), add that port to the
   `k8s-services` access policy.

## Removing the Tailscale operator

The old `tailscale-operator` Application had no resources finalizer, so pruning it from the
app-of-apps leaves its resources behind. Clean up once:

```sh
kubectl delete application -n argocd tailscale-operator --ignore-not-found
kubectl delete namespace tailscale
kubectl get crd -o name | grep tailscale.com | xargs -r kubectl delete
```

Afterwards revoke the OAuth client and remove the `hwkn-prod-tailscale-operator` device in the
Tailscale admin console.
