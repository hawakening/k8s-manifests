# Internal ingress

Internal web UIs are served by Traefik (`traefik` Application, `cluster-addons/apps/values/traefik.values.yaml`)
on `https://<name>.int.hwkn.dev`. Traefik only has a ClusterIP service; it is reachable over
NetBird only (see [cluster-addons/manifests/netbird](../netbird/README.md) for the NetworkResource,
DNS zone and access policy).

- `10-cluster-issuer.yaml`: Let's Encrypt `ClusterIssuer` using DNS-01 on the Cloudflare `hwkn.dev` zone.
- `20-wildcard-certificate.yaml`: `*.int.hwkn.dev`, used as Traefik's default certificate.
- `30-argocd-ingress.yaml`: ArgoCD is installed by hand, so its Ingress lives here. Grafana and
  Longhorn get theirs from their Helm values.

| URL                             | Service                                    |
|---------------------------------|--------------------------------------------|
| https://argocd.int.hwkn.dev     | `argocd/argocd-server`                     |
| https://grafana.int.hwkn.dev    | `monitoring/kube-prometheus-stack-grafana` |
| https://longhorn.int.hwkn.dev   | `longhorn-system/longhorn-frontend`        |

## One-time setup: Cloudflare API token

Create a token in Cloudflare (`My Profile > API Tokens > Create Token`, template *Edit zone DNS*)
with `Zone / DNS / Edit` and `Zone / Zone / Read`, restricted to the `hwkn.dev` zone.
Store it as a SealedSecret in the `cert-manager` namespace (a `ClusterIssuer` reads its secrets from there):

```sh
kubectl -n cert-manager create secret generic cloudflare-api-token \
  --from-literal=api-token='<token>' --dry-run=client -o yaml \
  | kubeseal --format yaml > cluster-addons/manifests/ingress/templates/05-cloudflare-api-token.sealed.yaml
```

## Exposing another service

Add an Ingress in the namespace of the service. No `tls` block is needed; HTTP is redirected to
HTTPS and the wildcard certificate is served for every host.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: metabase
  namespace: metabase
spec:
  ingressClassName: internal
  rules:
    - host: metabase.int.hwkn.dev
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: metabase
                port:
                  number: 3000
```

Only single-level names (`<name>.int.hwkn.dev`) are covered by the wildcard certificate and CNAME.
