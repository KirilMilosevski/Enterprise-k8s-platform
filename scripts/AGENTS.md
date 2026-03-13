# AGENTS.md

## Scope
Repository automation scripts live here.

## Shell scripting practices
- Use bash strict mode for new scripts: set -euo pipefail.
- Keep scripts idempotent when they are part of bootstrap or rotation workflows.
- Validate required commands and environment variables early with clear error messages.
- Never print secrets to stdout or write plaintext credentials to disk unless explicitly required and immediately cleaned up.
- Prefer small composable functions over long linear scripts.
- Keep usage and assumptions documented at the top of the script when the workflow is not obvious.
- Fail fast on partial secret generation rather than writing an inconsistent set of outputs.
