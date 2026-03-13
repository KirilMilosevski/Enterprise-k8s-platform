# AGENTS.md

## Scope
Terraform bootstrap and cluster lifecycle code lives here.

## Terraform practices
- Run terraform fmt and terraform validate before committing Terraform changes.
- Keep provider and module versions pinned.
- Give every variable a type and description.
- Give every output a description.
- Mark sensitive variables as sensitive, but remember Terraform state still contains the plaintext value.
- Never commit tfstate, tfstate backups, or plaintext tfvars.
- Prefer declarative resources over shell-heavy local-exec flows; use local-exec only when no provider-native option exists.
- Keep plans deterministic and minimize hidden side effects.

## State and operations
- For real production use, prefer a remote backend with locking and encrypted state.
- For this homelab repo, keep local state out of Git and document any required environment variables.
- Avoid storing long-lived credentials in Terraform variables when a sealed or external secret flow exists.
- Treat cluster bootstrap as idempotent; reruns should converge cleanly.
