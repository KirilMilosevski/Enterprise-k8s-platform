# AGENTS.md

## Scope
Prometheus Operator custom resources such as ServiceMonitors live here.

## Prometheus Operator practices
- Apply ServiceMonitor and PodMonitor resources only after the Prometheus CRDs exist.
- Keep selectors stable and specific; avoid accidental cluster-wide scraping.
- Set scrape intervals deliberately and do not overscrape low-value targets.
- Keep labels aligned with the owning Prometheus release.
- Prefer additive, app-specific monitors over one broad catch-all monitor.
