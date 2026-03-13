# AGENTS.md

## Scope
Ingress resources and external routing rules live here.

## Ingress practices
- Keep hostnames explicit; do not add catch-all exposure unless it is a deliberate edge design.
- Always define TLS for public endpoints.
- Set ingressClassName explicitly.
- Keep controller-specific annotations minimal and justified.
- Be precise with path matching. Verify slash and no-slash behavior for subpath applications.
- Put more specific paths before broad root paths when readability matters.
- Avoid duplicate resource ownership across ArgoCD Applications.
- Keep app routing, auth routing, websocket routing, and asset paths consistent with the application's base path.
