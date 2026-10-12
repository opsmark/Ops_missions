#!/usr/bin/env bash
set -eu

cat >&2 <<'EOF'
OPS_MISSIONS_RETIRED: this historical remote-command poller is disabled.
It fetched and executed changing remote shell content without a signed task,
allowlist, replay protection, durable result receipt, or bounded rollback.
Use the maintained Machine Substrate / OPS-099 control owner instead.
EOF

exit 64
