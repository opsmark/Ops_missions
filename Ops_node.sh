#!/usr/bin/env bash
set -eu

cat >&2 <<'EOF'
OPS_MISSIONS_RETIRED: this historical Termux bootstrap is disabled.
It performed broad package installation, destructive replacement, cloning of
an unavailable framework, and an infinite maintenance loop without current
host admission, version pinning, receipts, bounded authority, or rollback.
Use the maintained Machine Substrate / OPS-099 control owner instead.
EOF

exit 64
