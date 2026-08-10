## Link in and test MySQL/Postgres pre-backup dump tasks (not started)

`tasks/mysql_dump.yml` and `tasks/postgres_dump.yml` exist but have
never been verified end-to-end:

* Both are only included from `tasks/debian.yml` (`when:
  mysql_dump_script is defined` / `postgres_dump_script is defined`).
  Since `tasks/main.yml` runs `debian.yml` for any `os_family ==
  'Debian'` host (which includes Ubuntu), they do run on Debian and
  Ubuntu - but `tasks/redhat.yml` never includes them, so
  `mysql_dump_script`/`postgres_dump_script` are silently no-ops on
  EL 8/9, despite EL being a claimed supported platform. Either wire
  them into `redhat.yml` too or document the dump scripts as
  Debian/Ubuntu-only.
* Zero molecule coverage - no scenario sets `mysql_dump_script`,
  `postgres_dump_script`, `backuppc_client_mysql_dump`, or
  `backuppc_client_postgres_dump`, so neither task file has ever
  actually converged.
* `tasks/mysql_dump.yml`'s first two tasks (`Debug
  backuppc_client_mysql_dump`, `Debug2`) reference
  `backuppc_client_mysql_dump` unconditionally - if
  `mysql_dump_script` is defined but `backuppc_client_mysql_dump`
  isn't (they're independent variables), this fails on an undefined
  var before ever reaching the real work. `postgres_dump.yml` has the
  same pattern. Fix while wiring this in, not just testing around it.
* Leftover `Debug`/`Debug2` tasks in both files should probably be
  removed once the flow is confirmed working, not shipped as
  permanent output.

### Correction (2026-08-09, same day) — match pattern and quoting were wrong

Manually deploying the first version to `netbox` and testing against
the real `backuppc` server surfaced two bugs in the wrapper itself
(caught before this ever shipped broadly):

* The `case` pattern matched `"rsync --server --sender "*`, but
  `config.pl`'s `$Conf{RsyncClientPath} = '/usr/bin/sudo /usr/bin/rsync'`
  means BackupPC actually sends `$SSH_ORIGINAL_COMMAND` starting with
  `/usr/bin/sudo /usr/bin/rsync --server --sender `, not a bare
  `rsync ...`. The wrapper was rejecting every legitimate request.
* `exec sudo /usr/bin/rsync ${SSH_ORIGINAL_COMMAND#rsync }` word-splits
  on spaces but doesn't correctly re-parse quoted/escaped argument
  segments (e.g. exclude patterns with embedded shell quoting).
  Switched to `eval "exec $SSH_ORIGINAL_COMMAND"`, which reconstructs
  the command the same way the original hardcoded forced-command
  relied on shell parsing to do.

Fixed in `files/usr/local/bin/rsyncbackup-wrapper.sh` and the matching
README code block. Security guarantee is unchanged - it still only
ever permits `/usr/bin/sudo /usr/bin/rsync --server --sender ...`,
just matching what's actually sent instead of an idealized version of
it. **Still needs**: re-running the `BackupPC_serverMesg ... doFull`
verification against `netbox` with this corrected version and
confirming a clean `XferLOG.0.z` before considering this closed.

## rsyncbackup-wrapper.sh migration (2026-08-09)

Root-caused a real production failure: full backups of a client host
(referred to below as `netbox`) failing with `protocol version
mismatch -- is your shell clean?` / `rsync error: protocol
incompatibility`.
Cause: `authorized_keys`' `command=` forced a *frozen* rsync
invocation (flags/excludes baked in at key-provisioning time); SSH's
`command=` discards whatever the client actually sends, so the
client's real rsync version/flags never reached the real rsync
process. This wasn't a one-off — it's a structural problem that will
recur on any client whenever its rsync version drifts from whatever
the forced command was written for.

Fix, applied role-wide rather than patched on netbox alone:

* `files/usr/local/bin/rsyncbackup-wrapper.sh` (new) — validates
  `$SSH_ORIGINAL_COMMAND` starts with `rsync --server --sender ` and
  re-execs it via `sudo`, instead of substituting a frozen copy.
* `defaults/main.yml` — `backuppc_client_rsync_excludes` removed;
  `backuppc_client_wrapper_path` added (default
  `/usr/local/bin/rsyncbackup-wrapper.sh`).
* `tasks/ssh_keys.yml` — deploys the wrapper (root:root, `0755`);
  `key_options` default now forces `command=` to the wrapper path
  instead of a Jinja-built rsync command with an inlined exclude loop;
  added verify tasks (wrapper mode/ownership, `sudo -l -U` shows the
  expected `NOPASSWD: /usr/bin/rsync` rule).
* `tasks/sudoers_d.yml` — added `Defaults:<user> !use_pty` alongside
  the existing `NOPASSWD:/usr/bin/rsync` rule (pty allocation under
  sudo can corrupt rsync's binary protocol stream), and `validate:
  visudo -cf %s` on the write.
* `meta/argument_specs.yml`, `README.md`, `CLAUDE.md` updated to
  match; **BREAKING CHANGE** for any consumer setting
  `backuppc_client_rsync_excludes` or a per-entry `rsync_excludes` —
  move those excludes to the BackupPC server's `config.pl`
  (`RsyncArgs`/`RsyncArgsExtra`) instead. On this site that's already
  done as a shared fragment (`config.pl`'s global `RsyncArgsExtra`) —
  no per-host server config changes were needed for netbox itself.

**Not yet done / needs the consumer side**: this hasn't been run
against a real host yet (no live SSH access to `netbox` or the
`backuppc` server from this environment). Before relying on this,
re-apply the role to `netbox` and confirm with
`sudo -u backuppc /usr/share/backuppc/bin/BackupPC_serverMesg backup
netbox netbox backuppc
doFull`, then check `XferLOG.0.z` for real transfer activity and no
protocol-mismatch errors. Also flagged: no inventory of every client's
`rsync --version` vs. the server's `rsync_bpc --version` exists yet,
so other clients running rsync >= 3.4.0 with old-style forced commands
could hit the same failure — this role fix prevents it going forward,
but a fleet-wide audit of which hosts still need reprovisioning is a
separate follow-up.

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
  an opt-in variable. Note: `tasks/main.yml`'s commented block and
  `tasks/debian.yml`'s two commented blocks (`ansible_distribution_release`,
  `ansible_lsb.major_release`, `ansible_distribution`, `ansible_fqdn`,
  `ansible_default_ipv4`) still use the deprecated top-level fact form —
  update to `ansible_facts['...']` if any of these get wired in, to
  match the rest of the role (see below).

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
  `redhat.yml`. `tasks/ubuntu.yml`/`tasks/debian.yml` still contain
  other version-gated branches for OS releases outside the current
  supported-platform statement (Ubuntu `< 20` is now the "unsupported"
  debug branch, after the `16–20` ssh-dss block was removed — see
  below). Worth a follow-up pass to decide whether that's worth
  pruning to match the meta.yml/README/molecule matrix now that only
  jammy is a supported Ubuntu release.
* ~~`ssh-dss` key-type support~~ — removed entirely. DSA is
  long-deprecated in OpenSSH (disabled by default since 7.0) and not
  needed on any currently-supported platform:
  * `tasks/ubuntu.yml`'s `16–20` block ("accept ssh-dss key types")
    deleted outright — it was the block's only task, so the whole
    `when:`/`block:` went with it. The "unsupported release" debug's
    `when:` moved from `< 16` to `< 20` so there's no silent gap for
    16.04/18.04 now that nothing else handles that range.
  * `files/etc/ssh/sshd_config.d/PubkeyAcceptedKeyTypes.conf` (deployed
    to Ubuntu jammy+ by the `>= 20` block) had `,ssh-dss` dropped from
    its `PubkeyAcceptedKeyTypes +ssh-rsa,ssh-dss` line — `ssh-rsa` was
    left alone since only `ssh-dss` was asked for.
  * `tasks/debian.yml`'s commented-out "Remove ssh-dss key types" task
    (dead code, previously flagged above for a keep/wire-in/delete
    decision) was deleted along with its "leave this task" comment,
    since it existed solely to manage the now-gone directive.
* ~~A real-world run against Ubuntu 26.04 "resolute" failed with
  `sshd -T` rejecting `PubkeyAcceptedKeyTypes +ssh-rsa,ssh-dss` outright
  ("Bad key types") rather than a soft deprecation~~ — the static
  ssh-dss removal above only fixed the shipped default; it didn't stop
  a future group_vars/host_vars override from reintroducing an
  unsupported type and hitting the same class of failure, deep inside
  `sshd -T` validation during the actual config-deploy task. Fixed
  properly:
  * `files/etc/ssh/sshd_config.d/PubkeyAcceptedKeyTypes.conf` converted
    to a template (`templates/etc/ssh/sshd_config.d/PubkeyAcceptedKeyTypes.conf.j2`),
    driven by a new default, `backuppc_client_ssh_pubkey_accepted_types:
    "+ssh-rsa"` — now overridable per host/group like any other role
    variable.
  * `tasks/ubuntu.yml`'s `>= 20` block switched from `copy:` to
    `template:` for this file.
  * `tasks/preflight.yml` gained two new tasks (Ubuntu 20.04+ only):
    run `ssh -Q PubkeyAcceptedKeyTypes` on the target host, then assert
    every type named in `backuppc_client_ssh_pubkey_accepted_types` is
    in that list. A host_vars/group_vars override requesting an
    unsupported type now fails fast in preflight with a message naming
    the exact offending type(s), instead of failing deep inside
    `sshd -T` with a bare "Bad key types" error. Verified locally
    (Ansible not available in this session's sandbox at 2.20, so tested
    the Jinja/assert logic standalone with 2.17 against both a
    real `ssh -Q` result and a synthetic one lacking `ssh-dss` — both
    behaved as expected) but not yet run through the real role/molecule
    on an actual 2.20 control node - please verify against `netbox`
    (or another live host) before trusting this in production.
* ~~A real run failed with `'backuppc_client' is undefined` in
  `tasks/ssh_keys.yml`~~ — fixed at the root: `backuppc_client` is now
  a **required** variable (breaking change), matching how
  `deprecated_backuppc_username` already worked. Discussed first since
  the existing code was inconsistent - `tasks/main.yml`'s "Create
  backuppc user" and `tasks/sudoers_d.yml`'s rsync-sudoers task both
  guarded on `backuppc_client is defined`, implying it was meant to be
  optional, but `tasks/ssh_keys.yml`'s two live tasks
  (`authorized_keys`/`deprecated_keys` management) never had that
  guard - which is what actually broke. Decided to make it required
  everywhere rather than add the missing guard to `ssh_keys.yml`:
  * `tasks/preflight.yml`: new "assert backuppc_client is defined"
    check (list, even an empty one - same pattern as
    `deprecated_backuppc_username`).
  * Removed the now-dead `when: backuppc_client is defined` guards in
    `tasks/main.yml`'s "Create backuppc user" and
    `tasks/sudoers_d.yml`'s rsync-sudoers task, and the equivalent
    `when:` on preflight's own "entries are well-formed" check.
  * `tasks/sudoers_d.yml`'s MySQL/Postgres-dump sudoers tasks had the
    same latent bug (guarded only on `mysql_dump_script is
    defined`/`postgres_dump_script is defined`, not on
    `backuppc_client`) - now moot, since `backuppc_client` is always
    defined by the time any task runs.
  * `meta/argument_specs.yml` and `README.md` updated:
    `backuppc_client` moved from "no default, conditional" to
    "required (pass `[]` if this host has no backup users)".
  * **Not yet re-verified against the real host that hit the original
    error** - please run against `netbox` (or another live host) to
    confirm the preflight assertion fires
    correctly if `backuppc_client` is genuinely missing from its
    inventory, and that existing hosts that *do* define it still
    converge cleanly.
* ~~`backuppc_client[].key_options`/`authorized_keys` were fragile and
  hard to maintain~~ — addressed after reviewing a consuming site's
  actual `group_vars/all/backuppc.yml`:
  * `defaults/main.yml` gained `backuppc_client_rsync_excludes`, and
    `tasks/ssh_keys.yml` now builds `key_options` from it (or a
    per-entry `rsync_excludes` override) when a `backuppc_client`
    entry doesn't set `key_options` explicitly. Consumers no longer
    need to hand-write and quote the full rsync `command=` string —
    that's exactly the kind of place a stray `'` used to break
    `sshd -T`/`authorized_key` validation with a cryptic error.
  * Preflight gained "assert no DSA (ssh-dss) authorized_keys",
    covering `backuppc_client`, `backuppc_client_mysql_dump`, and
    `backuppc_client_postgres_dump`. That site's host_vars file
    referenced `id_dsa.pub` via a broken nested-Jinja lookup
    (`private_data+'/group_vars/{{ bootstrap_domainname }}/...'` -
    the inner `{{ }}` doesn't evaluate inside an already-active
    expression); rather than just fixing the path syntax, the decision
    was to deprecate DSA outright, consistent with the
    `PubkeyAcceptedKeyTypes` change above. **Actual key rotation
    (generating an ed25519 keypair and placing it under
    `production/private_vars/group_vars/<domain>/backuppc-client/` on
    the consumer side) is explicitly not done here** — that's
    consumer-side secret material this role/session has no access to
    (`private_vars/` is git-ignored). The site's `backuppc.yml` was
    left pointing at `authorized_keys: []` with a comment marking
    where the new key goes; that host's actual backup auth will not
    work again until the real key is generated and added.
  * Fixed a related, previously-undetected shape bug found while
    reviewing this: `deprecated_backuppc_username` is a list of dicts
    with a `username` key (matching the site's real data and
    `tasks/main.yml`'s usage), but `tasks/sudoers_d.yml`'s "Delete old
    backuppc user from sudoers.d" task used the raw loop item directly
    (`{{ backuppc_client_item }}`) instead of `.username`, and
    `meta/argument_specs.yml` documented it as `elements: str`. Both
    fixed to match reality. Added a matching preflight "entries are
    well-formed" check, mirroring the one already in place for
    `backuppc_client`.
  * **Not yet run against a real host or through molecule** — the
    `key_options`-building Jinja was verified standalone (both the
    default-excludes path and a per-entry `rsync_excludes` override
    render correctly, matching the original hand-written string
    byte-for-byte on the default-excludes case), and the DSA-detection
    filter chain was verified standalone, but neither has been
    exercised through the actual role or `molecule converge`.
* `tasks/known_hosts.yml` delegates to a hardcoded production BackupPC
  server hostname rather than a variable. Pre-existing, left untouched
  (surgical-changes rule), but worth variablizing at some point.
* `tasks/mysql_dump.yml`/`tasks/postgres_dump.yml` have "Debug"/"Debug2"
  tasks that unconditionally print variables on every run. Pre-existing
  noise, not touched.
* ~~Top-level fact injection (`ansible_distribution`, `ansible_os_family`,
  `ansible_lsb.major_release`, etc.) in `tasks/main.yml`, `tasks/debian.yml`,
  and `tasks/ubuntu.yml`~~ — fixed, switched to `ansible_facts['...']`
  after a live run surfaced the `INJECT_FACTS_AS_VARS` deprecation
  warning (removed in ansible-core 2.24). `ansible_ssh_host`/
  `ansible_ssh_port` in `tasks/known_hosts.yml` were left as-is — those
  are connection magic variables, not gathered facts, so this
  deprecation doesn't apply to them.

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
