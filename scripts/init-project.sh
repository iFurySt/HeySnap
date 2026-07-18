#!/usr/bin/env bash

set -euo pipefail

cat >&2 <<'MSG'
scripts/init-project.sh has been retired.

HeySnap now keeps its own repository identity. Start from AGENTS.md and docs/
when updating project context, and use scripts/new-history.sh or
scripts/new-exec-plan.sh for repository maintenance records.
MSG

exit 1
