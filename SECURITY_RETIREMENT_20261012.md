# Ops_missions security retirement — 2026-10-12

## Status

`RETIRED_ON_MAIN_SOURCE_ONLY`

This repository is historical. Its three executable files were replaced on the default `main` branch with fail-closed stubs in commit `680be75bf2ceb502d91e9ed9b839cb2836077770`. This is repository-source retirement only, not confirmation that older local copies are stopped. Git history preserves the original bytes and provenance.

## Why the old implementation is not an approved OPS control route

- `ops_remote.sh` repeatedly downloaded a changing shell script and executed it without a pinned digest, signature, operation allowlist, expiry, replay protection, durable request/result receipts or bounded rollback.
- `ops_command.sh` collected clipboard, location, camera, microphone, nearby Wi-Fi, processes, packages and system properties without a current scoped mission, data minimization, explicit collection receipt, retention boundary or receiving owner.
- `Ops_node.sh` installed broad tooling, deleted/recloned a framework, referenced an unavailable repository and entered an infinite maintenance loop without current host admission, version pinning or rollback.

The last historical commit was dated 2025-04-29. The referenced `opsmark/Ops_Remote_Commands` and `opsmark/Ops_Framework` repositories were not found during the 2026-10-12 authenticated GitHub reconciliation. Absence from GitHub does not prove that no device retains an old local copy.

## Replacement boundary

Do not revive this repository as a scheduler, command queue or general shell. Current control work belongs to the maintained Machine Substrate / OPS-099 owners and must require:

1. current host admission and collision checks;
2. authenticated, allowlisted operations;
3. signed or otherwise integrity-bound tasks with expiry and replay defense;
4. durable request/result receipts and receiving-owner readback;
5. reversible staging, explicit rollback and no credential/consent bypass;
6. separation of proposed, sent, received, executed and verified outcomes.

## Native follow-up

This source retirement prevents use of the historical script bodies when checking out the current `main` versions. Other branches, historical revisions and already-installed copies are separate. It does **not** stop an already-running local copy. Current device/process inspection remains a separate Machine Substrate action and was not claimed here.
