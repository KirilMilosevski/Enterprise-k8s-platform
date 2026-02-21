# Homelab Plane GitOps Cluster

This directory defines a full homelab Kubernetes environment for running **Plane (Ticket managment system)** with GitOps, TLS, ingress, Cloudflare tunnel access, and observability.

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
│       ├── application.yaml                      # Plane CE app (+ ingress source)
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
│   ├── plg.yaml                                  # kube-prometheus-stack app
│   ├── loki.yaml
│   ├── promtail.yaml
│   └── traefikservicemonitor.yaml
├── namespaces/plane.yaml                         # Explicit Plane namespace manifest
├── secrets/cloudflared-token.sealedsecret.yaml   # SealedSecret for tunnel token
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

## Before First Apply

### 1) Set Cloudflare API token secret for cert-manager

`ClusterIssuer` resources reference this secret:
- Name: `cloudflare-api-token-secret`
- Namespace: `cert-manager`
- Key: `api-token`

Create it manually before/after bootstrap:

```bash
kubectl create secret generic cloudflare-api-token-secret \
  -n cert-manager \
  --from-literal=api-token='<YOUR_CLOUDFLARE_API_TOKEN>'
```

### 2) Ensure sealed Cloudflared token is valid

`secrets/cloudflared-token.sealedsecret.yaml` must contain a token encrypted against your cluster Sealed Secrets controller key.

If you need to rotate it:

```bash
kubectl create secret generic cloudflared-token \
  -n cloudflare \
  --from-literal=TUNNEL_TOKEN='<YOUR_TUNNEL_TOKEN>' \
  --dry-run=client -o yaml \
| kubeseal \
  --controller-namespace kube-system \
  --controller-name sealed-secrets \
  --format yaml \
> secrets/cloudflared-token.sealedsecret.yaml
```

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

### Align Plane URLs with TLS

`apps/children/plane/application.yaml` currently sets:
- `cors_allowed_origins: "http://plane.kiril.shop"`
- `web_url: "http://plane.kiril.shop"`

For HTTPS deployments, set both to `https://...`.

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

1. Verify Cloudflare API secret exists in `cert-manager` namespace
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

- Grafana admin password is set to `admin` in `monitoring/plg.yaml`
- Plane URLs are HTTP in chart values while ingress uses TLS
- Plane wildcard cert uses staging issuer
- Secrets are partly GitOps-managed (SealedSecret) and partly manual (Cloudflare API token secret)

Harden before wider exposure.

## Destroy / Recreate

Destroy everything:

```bash
cd terraform
terraform destroy
```

This triggers k3d cluster deletion via Terraform `local-exec` destroy provisioner.


## Project Status

- CI/CD pipeline work is currently in progress.
- Additional observability to be added (Prometheus, Grafana, Loki, and Promtail).
