#!/usr/bin/env bash
set -eu

cat >&2 <<'EOF'
OPS_MISSIONS_RETIRED: this historical device-recon script is disabled.
It collected clipboard, location, camera, microphone, network, process and
package data without a current bounded mission, minimization rule, consent
receipt, retention policy, or receiving owner.
Use a current scoped diagnostic owned by Machine Substrate instead.
EOF

exit 64
