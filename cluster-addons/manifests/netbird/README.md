# NetBird

NetBird replaces the Tailscale operator for private access to the cluster:

- **Kubernetes API**: the `ClusterProxy` runs `netbird-kubeapi-proxy` peers. `kubectl` traffic is
  authenticated by NetBird identity and impersonated into Kubernetes RBAC (no tokens to hand out).
- **Internal services** (ArgoCD, Grafana, Longhorn, ...): the `NetworkRouter` runs routing peers and
  a single `NetworkResource` publishes the internal Traefik ingress (TCP 80/443) as
  `traefik.traefik.int.hwkn.dev`. A wildcard CNAME `*.int.hwkn.dev` points at it, so every
  `Ingress` with `ingressClassName: internal` is reachable over HTTPS with a Let's Encrypt
  certificate (see [cluster-addons/manifests/ingress](../ingress/README.md)).

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
   - Domain: `int.hwkn.dev` (must match `spec.dnsZoneRef.name` in `templates/30-network-router.yaml`)
   - Distribution groups: `hwkn-team`
   - The operator adds one A record per `NetworkResource`, always named `<service>.<namespace>.int.hwkn.dev`.
   - Once `traefik.traefik.int.hwkn.dev` exists, add a wildcard CNAME record (`Add Record`, type CNAME):

     | Name             | Target                         |
     |------------------|--------------------------------|
     | `*.int.hwkn.dev` | `traefik.traefik.int.hwkn.dev` |

     The CNAME keeps working when the Traefik ClusterIP changes, because the operator updates the
     A record it points to.
   - The zone is authoritative for NetBird peers: `int.hwkn.dev` names are only resolved from here,
     the public `hwkn.dev` zone is not affected. Only the ACME challenge records
     (`_acme-challenge.int.hwkn.dev`) are created in Cloudflare.

4. **Access policies**: `Access Control > Policies`. The destination groups `k8s-api-proxy` and
   `k8s-services` are created by the operator once it runs.

   | Name           | Source                     | Destination     | Protocol / ports |
   |----------------|----------------------------|-----------------|------------------|
   | k8s-api        | `k8s-admins`, `k8s-readers` | `k8s-api-proxy` | TCP 443          |
   | k8s-services   | `hwkn-team`                | `k8s-services`  | TCP 80, 443      |

## Client usage

Requires the NetBird client (`netbird` CLI) connected to the account.

```sh
netbird kubernetes list
netbird kubernetes write-kubeconfig hwkn-prod   # adds context "hwkn-prod" to ~/.kube/config
kubectl --context hwkn-prod get nodes
```

Internal services resolve on connected peers, e.g. `https://argocd.int.hwkn.dev`.

## Exposing another service

Add an `Ingress` with `ingressClassName: internal` and a host under `int.hwkn.dev`; no NetBird,
DNS or certificate changes are needed. See [cluster-addons/manifests/ingress](../ingress/README.md).

## Migrating from `hwkn.internal`

Services used to be published one `NetworkResource` each in the `hwkn.internal` zone. Moving the
router to `int.hwkn.dev` makes the operator delete its records in the old zone. Afterwards:

1. Delete the `hwkn.internal` zone (and its hand-made CNAMEs) in the NetBird dashboard.
2. Add TCP 443 to the `k8s-services` policy.

## Removing the Tailscale operator

The old `tailscale-operator` Application had no resources finalizer, so pruning it from the
app-of-apps leaves its resources behind. Clean up once:

```sh
kubectl delete application -n argocd tailscale-operator --ignore-not-found
kubectl delete namespace tailscale
kubectl get crd -o name | grep tailscale.com | xargs -r kubectl delete
kubectl delete ingressclass tailscale
```

Afterwards revoke the OAuth client and remove the `hwkn-prod-tailscale-operator` device in the
Tailscale admin console.
