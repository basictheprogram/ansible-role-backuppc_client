# Claude Code project notes — backuppc_client

Configures a BackupPC client: creates the backup user, manages SSH
authorized_keys for the rsync-over-ssh backup transport, sets up
sudoers.d rules for rsync/MySQL-dump/Postgres-dump, and optionally
installs MySQL/Postgres database dump scripts, across Debian, Ubuntu,
and RedHat-family hosts.

---

## Behavioral guidelines

These four rules govern how to work in this repo. They bias toward
caution over speed — for trivial one-liner changes, use judgment.

### 1. Think before writing tasks

**Don't assume. Surface tradeoffs. Ask when uncertain.**

Before adding or changing anything:

* State assumptions explicitly. If a variable could live in `defaults/`,
  `vars/`, or `host_vars`, say which and why before choosing.
* If multiple approaches exist (e.g. `ansible.builtin.command` vs a
  purpose-built module), present the tradeoff — don't pick silently.
* If the request is ambiguous (which task file? which template block?),
  name the ambiguity and ask. Don't guess and implement.
* If a simpler approach solves the problem, say so and push back.
* If something conflicts with `DESIGN.md`, flag it before proceeding.

### 2. Simplicity first

**Minimum tasks, variables, and template logic that solve the problem.**

* No new default variables beyond what the task being added requires.
* No Jinja2 abstraction for logic used in only one template.
* No `when:` conditions for scenarios that have no test coverage.
* No "future-proofing" of the public interface that wasn't asked for.
* If a template block is 30 lines and could be 10, rewrite it.

Ask: would a senior Ansible engineer call this overcomplicated? If yes,
simplify.

### 3. Surgical changes

**Touch only what the request requires. Clean up only your own mess.**

When editing existing tasks, templates, or defaults:

* Don't reformat adjacent YAML, fix unrelated comments, or clean up
  upstream code that wasn't broken by your change.
* Match the existing style — indentation, quoting, bullet character —
  even if you'd do it differently from scratch.
* If you notice unrelated dead code or stale variables, mention it;
  don't delete it without being asked.

When your change creates orphans:

* Remove `vars`, `when` conditions, or template blocks that YOUR change
  made unreachable.
* Don't remove pre-existing orphans unless explicitly asked.

Every changed line should trace directly to the request.

### 4. Goal-driven execution

**Define the success criteria before starting. Verify before declaring done.**

Transform requests into verifiable outcomes:

* "Add a preflight assertion" → `molecule converge` passes,
  `molecule verify` passes, `pre-commit run --all-files` is clean.
* "Fix an idempotency bug" → second `molecule converge` reports zero
  changed tasks.
* "Refactor a template" → rendered output is byte-for-byte identical
  to pre-refactor output on a converged instance.

For multi-step changes, state a brief plan before starting:

    1. Edit template → verify: rendered YAML is valid
    2. Add task       → verify: molecule converge green
    3. Add test       → verify: molecule verify green
    4. Lint           → verify: pre-commit run --all-files clean

Strong success criteria allow independent verification. Weak criteria
("make it work") require constant clarification.

---

## Role-specific notes

### Source of truth

`DESIGN.md` is the authoritative spec. Read it before any non-trivial
change. If code disagrees with `DESIGN.md`, `DESIGN.md` is right —
flag the discrepancy and ask before fixing the design to match the code.

### Design notes

No DESIGN.md found — add one.

### Secrets

Role-specific secret variable names:

No `_key`/`_token`/`_password`/`_secret` style variables found.
`backuppc_client[].authorized_keys` and `ssh_host_pub_keys` carry SSH
*public* keys, not secrets. `tasks/main.yml`'s "Create backuppc user"
task sets `password: "*"` (a locked/disabled password, not a real
credential) and already carries a `# noqa no-log-password` comment.

### Commit scopes

Role-specific subsystem scopes: `ssh_keys`, `known_hosts`, `sudoers_d`,
`sshd_config`, `mysql_dump`, `postgres_dump`, `debian`, `ubuntu`,
`redhat`

### Settled decisions

* `tasks/redhat.yml` never included `mysql_dump.yml`/`postgres_dump.yml`
  (2026-09-24 finding) — unlike `debian.yml`, which does. This meant
  `mysql_dump_script`/`postgres_dump_script` silently did nothing on
  EL hosts despite EL being a claimed supported platform. Decided to
  wire them in now (matching `debian.yml`'s pattern exactly) rather
  than just document the gap. This is a behavior change for any
  existing EL consumer that already sets `mysql_dump_script`/
  `postgres_dump_script` expecting it to be a no-op — it will now
  actually run.
* `files/usr/local/bin/rsyncbackup-wrapper.sh` (2026-09-24): the
  prefix-match `case` only checked that `$SSH_ORIGINAL_COMMAND`
  *started with* the allowed rsync invocation, but `eval "exec
  $SSH_ORIGINAL_COMMAND"` re-parses the *whole* string — so a command
  matching the prefix could still smuggle a shell metacharacter
  (`` ` ``, `$(`, `;`, `|`, `&`) later in the line and have it
  executed during that re-parse. Anyone holding the SSH key could run
  arbitrary commands as `rsyncbackup`, not just rsync. Not a new
  privilege tier on its own (the key already implies broad root-level
  trust via `sudo rsync`), but it broke the "rsync only" guarantee the
  script's own comment describes. Fixed with an inner `case` that
  rejects any of those five characters before `eval` ever runs,
  keeping the pass-through design (rather than switching to `rrsync`,
  which would reintroduce the exact staleness problem this wrapper was
  built to avoid — see the header comment). Updated the matching code
  block in README.md to stay in sync, and added
  `molecule/default/tests/test_wrapper.py` — no test exercised the
  wrapper's actual behavior before this, so the fix had no regression
  coverage.
* DSA (`ssh-dss`) keys are deprecated role-wide, not just in
  `sshd_config`'s `PubkeyAcceptedKeyTypes` (Ubuntu 20.04+, see
  `backuppc_client_ssh_pubkey_accepted_types`). Preflight also rejects
  any `ssh-dss` key found in `backuppc_client`/
  `backuppc_client_mysql_dump`/`backuppc_client_postgres_dump`
  `authorized_keys`. Consumers must supply ed25519 or RSA keys.
  Regenerating/rotating actual key material for existing consumers is
  a follow-up the consumer side owns, not something this role does.
* `backuppc_client[].key_options` is optional: if unset, the role
  forces `command=` to `backuppc_client_wrapper_path`
  (`rsyncbackup-wrapper.sh`) rather than requiring every consumer to
  hand-write and quote a full rsync command string. Set `key_options`
  directly only when a host needs something other than the standard
  rsync restriction.
* `authorized_keys` no longer forces a frozen, hand-written rsync
  command (flags/excludes baked in at provisioning time) — it forces
  `rsyncbackup-wrapper.sh`, which validates `$SSH_ORIGINAL_COMMAND` is
  actually `rsync --server --sender ...` and re-execs it via `sudo`.
  Root cause: a real production failure (`protocol version mismatch`)
  traced to the old frozen command silently discarding whatever
  BackupPC/rsync actually negotiated, since `command=` always
  overrides the client's real invocation. `backuppc_client_rsync_excludes`
  and `backuppc_client[].rsync_excludes` were removed as a result —
  rsync excludes are no longer this role's concern; they belong in the
  BackupPC server's `config.pl` (`RsyncArgs`/`RsyncArgsExtra`), which
  the wrapper's re-exec now actually lets take effect. This is a
  BREAKING CHANGE for any consumer that set `backuppc_client_rsync_excludes`
  or a per-entry `rsync_excludes` — those excludes must be moved to the
  BackupPC server config instead (already consolidated as a shared
  `RsyncArgsExtra` fragment in the server-side `config.pl` on at least
  one consuming site).
* `deprecated_backuppc_username` is a list of dicts with a `username`
  key (matching `backuppc_client`'s shape), not a list of plain
  strings — `tasks/sudoers_d.yml`'s "Delete old backuppc user from
  sudoers.d" task and `meta/argument_specs.yml` both previously
  disagreed with this (treating it as `elements: str`); both were
  fixed to match `tasks/main.yml`'s actual (and consumers' actual)
  usage.

### Open questions

If a task touches one of these, leave a `# TODO(open-q):` comment:

* `files/snapshot_pct.sh`, `files/snapshot_qm.sh`, `files/dump_mongodb.sh`
  are all empty and unreferenced by any task. Wire one in, or remove
  them — neither decided yet.
* `tasks/known_hosts.yml` (the `backuppc_ssh_key_scan` feature) has no
  molecule test coverage — it delegates to an external BackupPC
  server, which doesn't fit a single-container fixture cleanly. Would
  need a multi-node molecule scenario or an equivalent workaround.

### Implementation order

Work one section at a time. Each item = one focused session and one
commit. Stop and verify between items.

All 13 steps of the `ansible-sync-role` skill are done as of
2026-09-24. This section previously claimed several were still
pending (no `meta/argument_specs.yml`, no `LICENSE`, README still
boilerplate, etc.) when they'd actually already been completed in an
earlier, undocumented session — a real gap between this file and the
repo's actual state. Rewritten below to describe what's actually true
today, not a stale backlog.

1. **ansible-core 2.20 compliance** — done. `ansible_facts['...']`
   used throughout; loop vars correctly `backuppc_client_`-prefixed.
   Fixed 2026-09-24: `redhat.yml`'s `common_library` debug task
   referenced an undefined variable (crashed every RedHat run) and
   used `ansible.builtin.yum` instead of `dnf`; several `tags:
   backuppc` typos (should be `backuppc_client`); `postgres_dump.yml`
   was missing the `is defined` guard `mysql_dump.yml`'s equivalent
   task already had. Removed ~140 lines of dead commented-out code
   (superseded alternates in `tasks/main.yml`/`tasks/ssh_keys.yml`,
   the "sshuttle" sudoers block) and 8 unconditional debug/cruft
   tasks, per your decisions. Parameterized `known_hosts.yml`'s
   hardcoded `backuppc.castle.real-time.com` hostname and
   `remote_user`/`owner`/`group` into real role variables. Wired
   `mysql_dump.yml`/`postgres_dump.yml` into `redhat.yml` (were only
   ever included from `debian.yml`) — see Settled decisions.
2. **Lint clean** — done, zero `ansible-lint` violations at the
   `production` profile. `meta/argument_specs.yml` exists and is kept
   current (updated 2026-09-24 for the new `known_hosts` variables and
   to give `backuppc_client_mysql_dump`/`_postgres_dump` their own
   correct nested schema instead of claiming "same shape as
   backuppc_client", which was never true). `files/snapshot_pct.sh`,
   `files/snapshot_qm.sh`, and `files/dump_mongodb.sh` remain
   orphaned (all three empty, unreferenced) — flagged in `TODO.md`.
3. **`meta/main.yml`** — done. No `platforms:` key, `min_ansible_version:
   "2.20"`, `namespace: realtime`, `issue_tracker_url` points at the
   GitHub mirror. Updated 2026-09-24: dropped Debian bookworm, Ubuntu
   20.04/focal, and EL 8 from the supported-platform description (all
   EOL); added EL 10. Settled platform list: Debian (trixie), Ubuntu
   (jammy, noble, resolute), EL (9, 10).
4. **LICENSE** — done. `LICENSE` exists (MIT, Real Time Enterprises,
   Inc.), matches `meta/main.yml`'s `license: MIT`.
5. **`defaults/`/`vars/` split** — done. `defaults/main.yml` has no
   OS-specific content. Removed 2026-09-24: `vars/jammy.yml` (a
   byte-identical duplicate of `vars/Ubuntu.yml` sitting at a more
   specific `first_found` tier for no reason) and the
   `known_host_keys_dir`/`ssh_host_pub_keys` defaults, which became
   orphaned once the dead-code cleanup in step 1 removed their only
   consumer.
6. **Preflight assertions** — done. `tasks/preflight.yml` covers
   ansible version, OS family, `deprecated_backuppc_username`/
   `backuppc_client` definedness and entry shape, no DSA keys, Ubuntu
   pubkey-type support. Added 2026-09-24:
   `backuppc_client_known_hosts_server` required whenever
   `backuppc_ssh_key_scan` is set; `postgres_dump_file` required
   whenever `postgres_dump_script` is set (its consuming task used it
   unconditionally with no such guarantee).
7. **README** — done, real content throughout (not boilerplate).
   Updated 2026-09-24 for the platform-list, defaults-table, and
   preflight-list changes above.
8. **`molecule.yml` platform matrix + verifier** — done. Testinfra
   verifier already in place. Updated 2026-09-24: dropped the
   bookworm and Rocky 8 instances, added Rocky 10, renamed all
   instances to the fleet's `<os>-<codename>` convention (were
   `backuppc-client-molecule-<codename>-instance`), lowercased
   `dependency.name`/`provisioner.name` (`Galaxy`/`Ansible` →
   `galaxy`/`ansible`).
9. **`converge.yml`** — done, self-contained, standard cache-update
   `pre_tasks` already present. Fixed 2026-09-24: the fixture set
   `key_options: ''` on its `backuppc_client` entry, which is NOT the
   same as omitting the key — Jinja's `default()` filter only
   substitutes on genuinely undefined values, not falsy ones. This
   meant the fixture had never actually exercised the documented
   "common case" (omit `key_options`, get the wrapper `command=`
   forced automatically); it silently tested a different, broken path
   the whole time. Removed the empty-string override and added
   `test_backuppc_authorized_keys_forces_wrapper_command` to actually
   verify the `command=` restriction is present.
10. **Self-contained fixtures** — done, nothing further needed. No
    `group_vars/`; `converge.yml`'s vars are inline; already uses a
    clearly-fake throwaway SSH key (`molecule-test-key`).
11. **pytest-testinfra suite** — done. Existing suite (`test_packages.py`,
    `test_config.py`, `test_backuppc_user.py`) already solid. Added
    2026-09-24: `test_wrapper.py` (regression coverage for the
    shell-injection fix — see Settled decisions), and the
    `command=`-restriction assertion in `test_backuppc_user.py` above.
    `tasks/known_hosts.yml` (the `backuppc_ssh_key_scan` feature)
    remains untested — it delegates to an external server, which is
    inherently hard to fixture in a single-container molecule
    scenario; flagged in `TODO.md` rather than building a multi-node
    fixture for it now.
12. **`molecule/requirements.txt` / role-root `requirements.yml`** —
    done. `requirements.yml` correctly declares `ansible.posix`
    (`authorized_key`) and `ansible.utils` (the `ipaddr` filter in
    `known_hosts.yml`) — verified against actual usage 2026-09-24,
    nothing missing and nothing stale.

### Consumer side notes

<!-- TODO: fill in consumer notes -->

---

## Conventions

* **Commits**: follow the commit message guide in this file exactly.
  Conventional Commits, imperative mood, bodies wrapped at 72,
  asterisk bullets.
* **Lint**: `.ansible-lint`, `.yamllint`, `.pre-commit-config.yaml`
  define the rules. Run `pre-commit run --all-files` before declaring
  work done.
* **Secrets**: never write a credential into a tracked file. Vault
  secrets are consumed on the consumer side; the role templates them
  into config files with restricted permissions. Use `no_log: true`
  on any task that touches them.
* **Modules**: prefer FQCNs (`ansible.builtin.template`, etc.).
  The `.ansible-lint` rules require it.
* **Idempotency**: every task should be safe to re-run.

## Testing locally

* `pre-commit run --all-files` — fast lint/format pass. Run before
  every commit.
* `molecule converge` then `molecule verify` — fast iteration during
  template / task work; skips the destroy/create cycle.
* `molecule test` — full role exercise per platform. Slow; run
  before declaring a change done.

## When in doubt

Read `DESIGN.md`, then ask. The schemas and decisions there are
load-bearing.

---

## Commit message guide

You are an expert DevOps engineer and professional git commit message
writer. When generating a commit message, follow these steps exactly.

### Step 1 — Retrieve changes

Run:

    git diff --cached

Analyze the full staged diff. This is the **single source of truth**
for what will be committed.

### Step 2 — Understand the change

Determine:

* The **primary purpose** of the change
* The **type of change** (feature, bug fix, refactor, etc.)
* The **most relevant scope** within the role
* Whether the change introduces a **breaking change** for role consumers
* Whether multiple changes should be summarized together

Pay special attention to:

* Changes to `defaults/main.yml` — these define the role's public interface
* Changes to handler names, task names, and tags — consumers may pin to them
* Changes to template variables that consumers override
* Changes to config or env file templates that affect service behavior
* Changes to `meta/main.yml` — galaxy metadata, min Ansible version, platforms

If multiple files are modified, identify the **dominant intent** rather
than listing every file.

### Step 3 — Select commit type

Use Conventional Commits:

* `feat` — new task, handler, variable, template, or capability
* `fix` — bug fix or idempotency correction
* `docs` — README, role metadata documentation, inline comments
* `style` — YAML formatting, whitespace, ansible-lint cleanup
* `refactor` — restructure tasks/templates without behavior change
* `perf` — performance improvement (e.g., reduced task runs, fewer handlers)
* `test` — molecule scenarios, lint config, CI tests
* `chore` — galaxy metadata, dependencies, tooling
* `ci` — GitHub Actions, GitLab CI, pre-commit hooks

### Step 4 — Determine scope

Infer a scope from the role layout or the subsystem being changed.

Common Ansible role scopes: `tasks`, `handlers`, `templates`,
`defaults`, `vars`, `meta`, `molecule`, `docker`.

Role-specific subsystem scopes: `ssh_keys`, `known_hosts`, `sudoers_d`,
`sshd_config`, `mysql_dump`, `postgres_dump`, `debian`, `ubuntu`,
`redhat`

Only include a scope when it adds clarity. Prefer a subsystem scope
for feature-driven changes (e.g., `feat(tls): ...`) and a role-layout
scope for structural changes (e.g., `refactor(tasks): ...`).

### Step 5 — Write the commit message

Format exactly as:

    <type>[optional scope]: <short summary (<=50 chars)>

    <body wrapped at 72 characters>

    [optional footer(s)]

**Subject line rules:**

* Use **imperative mood** ("Add", "Fix", "Update", "Remove")
* Maximum **50 characters**
* Describe the **result**, not the implementation
* Prefer role-specific or Ansible terminology over generic phrasing

**Body rules** (required):

Explain **why the change was made**, focusing on:

* What deployment scenario or upstream behavior motivated it
* What downstream role consumers need to know to upgrade safely
* Any Ansible version constraints involved

When helpful, summarize key changes using bullet points.

**Bullet rules:**

* Use `*` (asterisk) for all bullets — never `-` or `•`
* Nested bullets indented with two spaces
* No Markdown formatting of any kind

**Ansible role expectations:**

* Call out new, renamed, or removed default variables
* Note when handler names, tag names, or public task names change
* Mention idempotency improvements when relevant
* Reference supported platforms when adding OS-specific tasks
* Flag changes to `meta/main.yml` (min Ansible version, platforms)
* Note molecule scenario additions or removals

### Breaking changes

A change is breaking when it:

* Renames or removes a default variable
* Renames or removes a handler, tag, or public task name
* Changes a default value in a way that alters runtime behavior
* Drops support for an Ansible version or OS platform
* Restructures generated configuration in a way consumers' overrides
  cannot accommodate

If the diff introduces a breaking change:

* Add `!` after the type/scope in the subject
* Include a footer: `BREAKING CHANGE: <description>`

Examples:

    feat(tasks): add preflight variable assertion block
    fix(handlers): correct service restart trigger condition
    refactor(tasks): split install and configure into files
    chore(meta): bump minimum Ansible version to 2.20
    test(molecule): add scenario for Ubuntu 24.04

    feat(defaults)!: rename primary configuration variable

    BREAKING CHANGE: old_variable_name is now new_variable_name;
    update playbook vars before upgrading.

### Step 6 — Output rules

Return **only the commit message**. Do NOT include:

* explanations or analysis
* the diff
* markdown formatting
* code fences

The output must be a clean commit message ready for `git commit`.
It will be pasted directly into a git commit editor — optimize for
copy/paste fidelity over styling.
