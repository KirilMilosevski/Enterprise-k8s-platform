# Platform for Plane (GitOps, Observability, CI/CD)

This directory defines a full homelab Kubernetes environment for running **Plane CE** with GitOps, TLS, ingress, Cloudflare tunnel access, and observability.

It combines:
- `Terraform` for Day-0 bootstrap (k3d cluster + Argo CD install + root app apply)
- `Argo CD` for Day-1/2 continuous reconciliation of platform and app manifests
- `Helm via Argo CD` for core platform components (Traefik, cert-manager, Sealed Secrets, monitoring stack, Plane)

## What This Deploys

The current manifests deploy the following components:

- Kubernetes cluster:
  - `k3d` cluster named `homelab` (default: 1 server, 2 agents)
  - Built-in k3s Traefik disabled (`--disable=traefik`)
- GitOps control plane:
  - Argo CD (`argo-cd` chart, default version `9.3.5`)
  - Root app-of-apps for platform/apps
  - Separate app-of-apps for monitoring
- Ingress and TLS:
  - Traefik (`traefik` + `traefik-crds`)
  - cert-manager with Cloudflare DNS-01 ClusterIssuers
  - Wildcard certs for `*.kiril.shop` / `kiril.shop`
- Application:
  - Plane CE (`plane-ce` chart version `1.4.1`)
  - Dedicated Plane ingress rules
- Edge connectivity:
  - Cloudflared deployment using a SealedSecret tunnel token
- Observability:
  - kube-prometheus-stack (Prometheus, Alertmanager, Grafana)
  - Loki (single binary, filesystem-backed)
  - Promtail (currently configured to collect Plane API + web pod logs)
  - Traefik `ServiceMonitor`

## Architecture Overview

Traffic path:

1. User hits `plane.kiril.shop` or `argocd.kiril.shop`
2. DNS is hosted in Cloudflare
3. Cloudflare tunnel forwards traffic to cluster edge
4. Traefik routes traffic to `plane-*` services or `argocd-server`
5. cert-manager serves TLS certs issued via Cloudflare DNS challenge

Control path:

1. Terraform provisions cluster + Argo CD + namespaces
2. Terraform applies:
   - `apps/root/app-of-apps.yaml`
   - `monitoring/app-of-apps/app-of-apps.yaml`
3. Argo CD reconciles everything else from this folder

## Repository Layout

```text
.
├── apps/
│   ├── root/app-of-apps.yaml                     # Root app for apps/bootstrap
│   └── children/plane/
│       ├── application.yaml                      # Plane CE app (chart + config override)
│       ├── cloudflare-config.yaml                # Cloudflared app
│       └── bootstrap/
│           ├── traefik/                          # Traefik + Traefik CRDs + ingress app
│           ├── cert-manager/                     # cert-manager chart + cert config app
│           └── sealedsecrets/                    # sealed-secrets chart + secrets app
├── cert-manager/
│   ├── clusterissuer.yaml                        # Cloudflare-backed ACME issuers
│   ├── wildcard-cert.yaml                        # Plane namespace wildcard cert
│   └── argocd-cert.yaml                          # Argo CD namespace wildcard cert
├── cloudflared/cloudflared.yaml                  # Cloudflare tunnel deployment
├── ingress/
│   ├── plane-ingress.yaml
│   └── argocdingress.yaml
├── monitoring/
│   ├── app-of-apps/app-of-apps.yaml
│   ├── plg.yaml                                  # kube-prometheus-stack app (chart + ServiceMonitor)
│   ├── loki.yaml
│   └── promtail.yaml
├── monitoring-resources/
│   └── traefik/traefikservicemonitor.yaml        # Traefik ServiceMonitor managed with Prometheus app
├── plane-overrides/
│   └── plane-app-vars.yaml                       # HTTPS override for Plane app vars
├── namespaces/plane.yaml                         # Explicit Plane namespace manifest
├── secrets/cloudflared-token.sealedsecret.yaml   # SealedSecret for tunnel token
├── scripts/generate-sealed-secrets.sh            # Regenerates SealedSecrets from local env vars
└── terraform/                                    # Day-0 bootstrap and lifecycle
```

## Prerequisites

Install locally:

- `docker` (or compatible engine required by k3d)
- `k3d`
- `kubectl`
- `terraform`
- `helm` (Terraform Helm provider installs charts, but Helm CLI is useful for debugging)
- `argocd` CLI (optional, but useful)
- `kubeseal` (required when rotating sealed secrets)

External prerequisites:

- A Cloudflare-managed domain (currently configured for `kiril.shop`)
- Cloudflare API token with DNS edit permissions
- Cloudflare Tunnel token (for `cloudflared`)

## Secrets Setup

The repo is wired so repo-managed credentials are expected to be backed by `SealedSecret` manifests instead of plaintext values or one-off manual `kubectl create secret` commands.

Expected sealed inputs:

- `cloudflare-api-token-secret` in namespace `cert-manager`
- `cloudflared-token` in namespace `cloudflare`
- `grafana-admin-credentials` in namespace `monitoring`

### 1) Bootstrap the cluster first

The Sealed Secrets controller certificate only exists after the cluster is up. Bootstrap the cluster and let Argo CD install the `sealed-secrets` app first:

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 2) Generate all SealedSecret manifests from local env vars

```bash
export CF_API_TOKEN='<YOUR_CLOUDFLARE_API_TOKEN>'
export TUNNEL_TOKEN='<YOUR_TUNNEL_TOKEN>'
export GRAFANA_ADMIN_PASSWORD='<A_STRONG_GRAFANA_PASSWORD>'
./scripts/generate-sealed-secrets.sh
```

Optional inputs:

- `GRAFANA_ADMIN_USER` defaults to `admin`
- `KUBECONFIG` defaults to `~/.kube/config-homelab`

The script writes:

- `secrets/cloudflare-api-token.sealedsecret.yaml`
- `secrets/cloudflared-token.sealedsecret.yaml`
- `secrets/grafana-admin-credentials.sealedsecret.yaml`

If you recreate the cluster and do not restore the previous Sealed Secrets controller key, regenerate every sealed secret manifest. Old ciphertext will not decrypt against a new controller key.

### 3) Optional but recommended config updates

Update hardcoded domain/repo values before initial deploy:

- Domain hosts:
  - `apps/children/plane/application.yaml`
  - `ingress/plane-ingress.yaml`
  - `ingress/argocdingress.yaml`
  - `cert-manager/wildcard-cert.yaml`
  - `cert-manager/argocd-cert.yaml`
- Git repo URL used by Argo applications:
  - Multiple files under `apps/` and `monitoring/app-of-apps/`

## Bootstrap and Deploy

From this directory:

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

After the first bootstrap, generate the sealed secret manifests and let Argo CD reconcile them:

```bash
./scripts/generate-sealed-secrets.sh
argocd app sync homelab-apps
argocd app sync monitoring
```

If `CF_API_TOKEN`, `TUNNEL_TOKEN`, and `GRAFANA_ADMIN_PASSWORD` are already exported in the shell that runs Terraform, Terraform now auto-runs [scripts/generate-sealed-secrets.sh](/home/pashalispar/PLANE/scripts/generate-sealed-secrets.sh) after the `sealed-secrets` controller becomes available and applies the regenerated manifests directly to the cluster.

This is only the runtime/bootstrap step. Argo CD still uses GitHub as its source of truth, so you must commit and push the regenerated files after bootstrap or Argo can later reconcile back to older ciphertext from the remote repo.

What happens during apply:

1. Creates k3d cluster and writes kubeconfig (default `~/.kube/config`)
2. Creates namespaces (`argocd`, `plane`, `monitoring`, `cert-manager`, `cloudflare`)
3. Installs Argo CD via Helm
4. Applies both root Argo CD Applications (apps + monitoring)
5. Argo CD reconciles all child applications/manifests

## Validate Installation

Check app health:

```bash
kubectl get applications -n argocd
```

Check core pods:

```bash
kubectl get pods -A
```

Check cert status:

```bash
kubectl get certificate -A
kubectl get challenges.acme.cert-manager.io -A
```

Check ingress:

```bash
kubectl get ingress -A
kubectl -n kube-system get svc traefik
```

## Accessing Services

Configured public hosts:

- `https://plane.kiril.shop`
- `https://argocd.kiril.shop`

If DNS/tunnel is not ready, use port-forwarding:

Argo CD:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Grafana:

```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-stack-grafana 3000:80
```

Argo CD initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

## Day-2 Operations

Force refresh an app:

```bash
argocd app get plane --refresh
argocd app sync plane
```

Watch Argo reconciliation:

```bash
kubectl -n argocd get applications -w
```

Check Cloudflared logs:

```bash
kubectl -n cloudflare logs deploy/cloudflared -f
```

Check Promtail scheduling:

```bash
kubectl -n monitoring get pods -l app.kubernetes.io/name=promtail -o wide
kubectl get nodes --show-labels | grep promtail
```

If Promtail pods are pending due node selector, label nodes:

```bash
kubectl label node <NODE_NAME> promtail=enabled
```

## Common Customizations

### Switch Plane cert from staging to production

`cert-manager/wildcard-cert.yaml` currently uses `letsencrypt-cloudflare-staging`.
Change issuer to `letsencrypt-cloudflare-prod` after validation.

### Change storage class

Plane chart values currently use `local-path` for Postgres/Redis/MinIO in:
- `apps/children/plane/application.yaml`

### Pin Cloudflared image version

`cloudflared/cloudflared.yaml` uses `cloudflare/cloudflared:latest`.  
Pin to a specific version tag for predictable upgrades.

## Troubleshooting

### Argo app stuck in `OutOfSync` or `Degraded`

1. Inspect app:
   ```bash
   kubectl -n argocd describe application <APP_NAME>
   ```
2. Check controller logs:
   ```bash
   kubectl -n argocd logs deploy/argocd-application-controller -f
   ```

### Certificate not issued

1. Verify `cloudflare-api-token-secret` exists in `cert-manager` namespace or regenerate `secrets/cloudflare-api-token.sealedsecret.yaml`
2. Check DNS challenge events:
   ```bash
   kubectl get challenges.acme.cert-manager.io -A
   kubectl describe challenge -n <NAMESPACE> <CHALLENGE_NAME>
   ```
3. Confirm Cloudflare zone/token permissions

### Public endpoint unreachable

1. Verify tunnel health:
   ```bash
   kubectl -n cloudflare get pods
   kubectl -n cloudflare logs deploy/cloudflared --tail=200
   ```
2. Confirm Cloudflare tunnel routes point to cluster entrypoint
3. Validate Traefik service and ingress objects

## Security Notes

Current config contains intentionally simple defaults suitable for homelab bootstrap, not production:

- Grafana admin credentials are expected from `secrets/grafana-admin-credentials.sealedsecret.yaml`
- Plane wildcard cert uses staging issuer
- Sealed secrets must be regenerated whenever the Sealed Secrets controller key changes

Harden before wider exposure.

## Destroy / Recreate

Destroy everything:

```bash
cd terraform
terraform destroy
```

This triggers k3d cluster deletion via Terraform `local-exec` destroy provisioner.


## Notes for Contributors

- Keep all environment-specific values explicit and documented in this README.
- If you change chart versions or hostnames, update both manifests and this file.
- Validate Argo app sync status and certificate issuance before merging infra changes.

## Project Status

- CI/CD pipeline work is currently in progress.
- Observability has been added (Prometheus, Grafana, Loki, and Promtail).
- Alerting/alarm capabilities are also included through the monitoring stack.
