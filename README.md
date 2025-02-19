# k8s-hawakening

This repository contains all deployment manifests for the hawakening.com & hwkn.dev infrastructure.
The manifests in this repo are automatically synced to the cluster using ArgoCD.

Our ArgoCD dashboard can be found [here](#)

> We do not manage anything through the ArgoCD UI!

## Continues Deployment

TODO


## Folder Structure

```
bootstrap: everything related to bootstrapping a new cluster (app of apps, argocd, etc.)
cluster-addons: everything related to cluster wide addons (e.g. cert-manager, ingress, etc.)
workloads: all hawakening specific manifests (backend, frontend, databases, etc.)
```

## Cluster bootstrapping / Disaster Recovery
If you want to setup a new cluster with the same configuration, you can have a look at:
- [Bootstrap cluster](./bootstrap/README.md)
