# AGENTS.md

## Scope
Encrypted secret manifests live here.

## Secret handling practices
- Commit only encrypted or sealed secret material.
- Never commit plaintext Secret manifests, env files, kubeconfigs, tokens, or private keys.
- Rotate any credential that is ever exposed in chat, terminal history, or Git history.
- Regenerate sealed secrets after controller key changes, or preserve the controller key across rebuilds.
- Keep secret scope minimal: one purpose, one namespace, one name.
- Do not mix app configuration with secret payloads when a standard Secret reference exists.
