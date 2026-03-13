# AGENTS.md

## Scope
cert-manager issuers and certificates live here.

## cert-manager practices
- Prefer DNS-01 for wildcard certificates.
- Keep issuer scope intentional; use ClusterIssuer only when multiple namespaces truly need it.
- Set explicit secret names and hostnames on Certificate resources.
- Prefer privateKey.rotationPolicy: Always for renewed certificates.
- Do not use serving certificate Secrets as a trust distribution mechanism for clients.
- Keep Cloudflare or other DNS credentials in sealed secrets only.
- Watch for renewal failure blast radius before changing shared issuers.
- Pin chart versions and controller behavior explicitly in Argo-managed installs.
