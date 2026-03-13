# AGENTS.md

## Scope
Cloudflare Tunnel deployment manifests live here.

## cloudflared practices
- Do not use the latest image tag for production-style changes; pin a tested version.
- Keep the tunnel token in a sealed secret only.
- Run multiple replicas for availability, but do not treat replicas as an autoscaling pattern.
- Rotate tunnel tokens in a maintenance window and update replicas in batches.
- Keep ingress exposure outbound-only; do not add inbound service exposure for cloudflared itself.
- Use explicit resource requests and limits when tuning the deployment.
- Prefer immutable config and predictable rollout behavior over ad hoc manual restarts.
