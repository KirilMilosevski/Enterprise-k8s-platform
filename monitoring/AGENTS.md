# AGENTS.md

## Scope
Prometheus, Loki, Grafana, and monitoring app definitions live here.

## Monitoring practices
- Pin chart versions intentionally for production-style updates.
- Keep retention, persistence, and storage size explicit.
- Use requests and limits for stateful monitoring components.
- Disable collectors and scrape targets that are noisy or not valid for this cluster.
- Keep dashboard and alert configuration declarative and versioned.
- Do not hardcode admin credentials; use a sealed or external secret.
- Control log volume and metrics cardinality deliberately.
- Treat scrape configs and relabeling as production code; broad selectors create noise and cost.
- Prefer one monitoring responsibility per Application when ordering or CRD availability matters.
