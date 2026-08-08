# TODO — backuppc_client sync follow-ups

Flagged during the `ansible-sync-role` pass (2026-08-08) but not resolved
in this session. Nothing here was silently dropped — decide each item
explicitly before or after committing.

## Decide: wire in or remove

* `files/snapshot_pct.sh` and `files/snapshot_qm.sh` — empty placeholder
  files, not referenced by any task. Either flesh them out and wire them
  into a task (e.g. a Proxmox `pct`/`qm` snapshot feature) or delete them.
* `files/dump_mongodb.sh` — not referenced by any task; no
  `tasks/mongo_dump.yml` exists to parallel `mysql_dump.yml`/
  `postgres_dump.yml`. Either build that task file (wiring it into
  `tasks/debian.yml` the same way mysql/postgres dumps are wired in) or
  delete the script.
* Large commented-out blocks in `tasks/main.yml` (authorized_keys
  loop_var rework) and `tasks/ssh_keys.yml` (debug task, an alternate
  authorized_keys block, a commented deprecated-keys removal block) and
  `tasks/known_hosts.yml` (fetch/add ssh host key block) — left
  untouched per the "don't silently decide" rule on orphaned/dead code.
  Finish the rework, delete the dead code, or wire something in behind
  an opt-in variable.

## Needs follow-up work

* ~~No `meta/argument_specs.yml` exists.~~ Added, documenting
  `defaults/main.yml` (`known_host_keys_dir`, `ssh_host_pub_keys`) and
  every consumer-supplied variable from the README. Note:
  `deprecated_backuppc_username` and each `backuppc_client[].deprecated_keys`
  are now marked `required: true` — this reflects the real latent bug
  noted below (`subelements('deprecated_keys')` errors if the key is
  missing), so role-invocation validation will now fail fast instead of
  erroring mid-task. If that's too strict for existing inventory,
  loosen it to `required: false` with `default: []` and add a matching
  `default([])` in `tasks/ssh_keys.yml`/`tasks/main.yml` instead.
* ~~No `LICENSE` file exists.~~ Added (MIT, matching `meta/main.yml`'s
  `license: MIT` and the README's license link). The role previously
  claimed BSD with nothing to back it up; MIT was chosen since that's
  what got requested — flag if BSD was actually intended instead.
* ~~`tasks/redhat.yml`'s `major_release < 6` and `tasks/ubuntu.yml`'s
  `>= 16 and < 20` monolithic-sudoers branches~~ — removed.
  `sudoers.d`/`#includedir` support has shipped by default since sudo
  1.7.2p1-1 (Debian 6 "Squeeze", 2011; Ubuntu 10.04 "Lucid", 2010), so
  every OS version these branches targeted (RHEL/CentOS < 6, Ubuntu
  16.04/18.04) already had `sudoers.d` support — the monolithic path was
  dead weight, not a real legacy requirement.
  `tasks/monolithic_sudoers.yml` was deleted along with its includes in
  `debian.yml` (already-commented dead reference), `ubuntu.yml`, and
  `redhat.yml`. `tasks/ubuntu.yml`'s `16–20` block is kept — it still
  does the unrelated ssh-dss key-type acceptance for that OS range —
  and `tasks/ubuntu.yml`/`tasks/debian.yml` still contain other
  version-gated branches for OS releases outside the current
  supported-platform statement (Ubuntu `< 16` "unsupported" debug,
  Ubuntu 16–20 ssh-dss branch itself). Those weren't touched by this
  change and remain a separate follow-up: decide whether they're worth
  pruning to match the meta.yml/README/molecule matrix now that only
  jammy is a supported Ubuntu release.
* `tasks/known_hosts.yml` delegates to a hardcoded production hostname
  (`backuppc.castle.real-time.com`) rather than a variable. Pre-existing,
  left untouched (surgical-changes rule), but worth variablizing at some
  point.
* `tasks/mysql_dump.yml`/`tasks/postgres_dump.yml` have "Debug"/"Debug2"
  tasks that unconditionally print variables on every run. Pre-existing
  noise, not touched.

## Verify before committing

* This session had no Docker/network access to actually run
  `molecule test` or `pre-commit run --all-files` — please run both
  locally before pushing. In particular:
  * Confirm the new 5-platform molecule matrix (jammy, bookworm, trixie,
    rockylinux8, rockylinux9) actually builds and converges.
  * Confirm the new `tasks/preflight.yml` assertions pass against real
    inventory `backuppc_client`/`deprecated_backuppc_username` values,
    not just the molecule fixture.
  * The `ssh_keys.yml` "Remove ssh key(s) from backuppc user" task uses
    `backuppc_client | subelements('deprecated_keys')`, which errors if
    any `backuppc_client` entry is missing a `deprecated_keys` key. This
    was a latent bug (the old molecule fixture didn't have one, so that
    task likely always failed when the fixture was defined) — the
    fixture now includes `deprecated_keys: []`, but check whether real
    inventory `backuppc_client` entries also need it added, or whether
    the task should gain `default([])` instead of requiring the key.

## Ready to commit

Steps 1–13 are done: config files synced, legacy CI check clean,
`CLAUDE.md` generated, ansible-core 2.20 compliance pass done,
`meta/main.yml` refactored, `defaults/`/`vars/` split cleaned up,
preflight assertions added, README rewritten, molecule platform matrix +
testinfra verifier updated, `converge.yml`/`prepare.yml` made
self-contained and OS-aware, fixtures anonymized with a throwaway SSH
key, pytest-testinfra suite added, and `molecule/requirements.txt` +
role-root `requirements.yml` added.

Use the `ansible-commit` skill to generate the commit message for these
changes.
