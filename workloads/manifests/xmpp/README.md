# Hawakening XMPP

This chart deploys the custom Hawakening ejabberd image as a single-replica
StatefulSet in the `hawakening` namespace.

## Architecture

- `xmpp.hawakening.com:5222` is exposed through a TCP LoadBalancer.
- `party.xmpp.hawakening.com` is the MUC service hosted by ejabberd.
- `/opt/ejabberd/database` is persisted on a Longhorn `ReadWriteOnce` volume.
  Mnesia stores friend rosters, subscriptions, offline messages, and persistent
  room data there.
- Image and configuration updates replace only the StatefulSet pod. The
  `data-hawakening-xmpp-0` claim is reattached to the replacement pod, while
  module/runtime files come from the new image. Do not rename the StatefulSet
  or its `data` volume claim template during an ordinary version update.
- The backend validates the authenticated player and issues a dedicated RS256
  XMPP token. ejabberd receives only the public verification key committed at
  `files/jwt-public.jwk`.
- The ejabberd HTTP API remains cluster-internal and is restricted by a
  NetworkPolicy.

## Merge prerequisites

1. Merge the generated release pull request in `hawakening-xmpp`. Its release
   workflow publishes `ghcr.io/hawakening/hawakening-xmpp:vX.Y.Z` and records
   the immutable digest in the workflow summary. Set the matching version tag
   in `values.yaml` for each rollout.
2. Add `XMPP_JWT_PRIVATE_KEY` to the existing `backend-secret` SealedSecret.
   Re-seal the complete Secret using the existing secret-management workflow;
   do not create a second SealedSecret with the same name. Its RSA private key
   must correspond to `files/jwt-public.jwk`.
3. Create the missing `xmpp-admin` SealedSecret while connected to the target
   cluster:

   ```sh
   kubectl --namespace hawakening create secret generic xmpp-admin \
     --from-literal=password='REPLACE_WITH_A_STRONG_PASSWORD' \
     --dry-run=client --output=yaml \
     | kubeseal --format=yaml \
     > workloads/manifests/xmpp/templates/10-admin-secret.sealed.yaml
   ```

   Commit only the sealed output. The password initializes
   `admin@xmpp.hawakening.com` when the Mnesia database is first created.
4. Confirm the backend image implements the XMPP Presence token contract and
   the unauthenticated `HEAD /player/:userId` lookup used in-cluster by this
   chart.
5. Configure a DNS-only record for `xmpp.hawakening.com` that resolves to the
   LoadBalancer. Standard XMPP on port 5222 requires raw TCP; use neither a
   Cloudflare HTTP tunnel nor the ordinary orange-cloud HTTP proxy. Cloudflare
   Spectrum is the exception if it is deliberately configured for this port.
6. Configure and test the certificate before enabling
   `starttls`/`starttls_required`. The current listener is plaintext and is not
   suitable for production credentials over an untrusted network.
7. Add `data-hawakening-xmpp-0` to the Longhorn backup policy and test a restore.

## Key rotation

Generate a dedicated RSA key pair and export the public half as a JWK containing
only `kty`, `n`, `e`, `use`, and `alg`. Keep the private PEM exclusively in the
backend SealedSecret. Replacing `files/jwt-public.jwk` changes the ConfigMap
checksum and rolls the StatefulSet so ejabberd loads the replacement key.

Coordinate rotation so the backend does not issue tokens signed by the new key
before ejabberd has rolled. Existing tokens signed by the old key stop working
after the switch because this deployment currently configures one verification
key.

## Verification

```sh
helm lint workloads/manifests/xmpp
helm template xmpp workloads/manifests/xmpp --namespace hawakening
kubectl --namespace hawakening rollout status statefulset/hawakening-xmpp
kubectl --namespace hawakening exec hawakening-xmpp-0 -- ejabberdctl status
kubectl --namespace hawakening exec hawakening-xmpp-0 -- ejabberdctl modules_installed
```

The installed module list must contain `mod_hawken_muc_config`.
