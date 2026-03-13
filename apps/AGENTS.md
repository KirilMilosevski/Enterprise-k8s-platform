# AGENTS.md

## Scope
ArgoCD Applications and Helm-driven application definitions live here.

## ArgoCD
- Keep ArgoCD fully declarative; change Git and let ArgoCD reconcile.
- Prefer one clear owner per resource. Do not let multiple Applications manage the same object.
- Use sync waves only for real dependency ordering such as CRDs, controllers, then custom resources.
- Keep automated sync explicit and intentional; use prune and self-heal only where drift correction is desired.
- Prefer small, composable Applications over one large recursive app with mixed concerns.

## Helm
- Prefer pinned chart versions for production-style changes; avoid broad version ranges for new work.
- Keep values minimal, explicit, and reviewable.
- When values become large or need CI-driven tag bumps, move them to dedicated values files instead of large inline blocks.
- Keep image repository and tag configurable through values; never rely on mutable tags like latest.
- Prefer chart values over post-render patches or hardcoded manifest overrides unless the chart is provably insufficient.

## Kubernetes app practices
- Set explicit namespaces and avoid implicit defaults.
- Use readiness and liveness probes, resource requests, and storage classes where the chart supports them.
- Keep secrets outside app definitions; reference SealedSecrets or other secret sources instead of plaintext.
- Preserve clean rollback behavior by avoiding ad hoc imperative changes.
