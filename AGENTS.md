# AGENTS.md

This repository contains a GitOps-driven Kubernetes platform.

## Stack
- Kubernetes
- ArgoCD
- Helm
- Terraform
- GitHub Actions
- Prometheus
- Loki
- Grafana
- Plane

## CI/CD
GitHub Actions is responsible for:
- linting
- testing
- building Docker images
- scanning images
- pushing images to GitHub Container Registry (GHCR)

## Deployment
ArgoCD is responsible for deployments.
Agents must never deploy directly to Kubernetes.
Agents must only change Git-tracked manifests / Helm values and let ArgoCD sync them.

## Rules
- Never commit secrets
- Never hardcode credentials
- Always prefer Helm values over hardcoded manifest changes
- Keep image repository and tag configurable
- Follow existing repository structure
- Keep changes production-style and minimal
