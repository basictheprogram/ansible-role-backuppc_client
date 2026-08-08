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
`mysql_dump`, `postgres_dump`, `debian`, `ubuntu`, `redhat`

### Settled decisions

<!-- TODO: fill in settled decisions -->

### Open questions

If a task touches one of these, leave a `# TODO(open-q):` comment:

<!-- TODO: fill in open questions -->

### Implementation order

Work one section at a time. Each item = one focused session and one
commit. Stop and verify between items.

1. **ansible-core 2.20 compliance** (`tasks/`) — `include_vars`
   `first_found` already points at `vars/`, good. Loop vars already use
   the `backuppc_client_`/`known_hosts` prefix pattern. Settled: RedHat
   `major_release|int < 6` and Ubuntu `< 20` monolithic-sudoers branches
   were dead weight (`sudoers.d` support predates every OS version this
   role can plausibly target) — `tasks/monolithic_sudoers.yml` and its
   includes were removed; `tasks/ubuntu.yml`'s `< 16`/`< 20` version
   branches for unrelated concerns (ssh-dss key acceptance) are still
   open. Decide the fate of the large commented blocks in
   `tasks/main.yml` and `tasks/ssh_keys.yml` (authorized_keys loop_var
   rework, ssh known_hosts fetch/add) — wire in, leave dead and
   document, or wire in behind an opt-in var.
2. **Lint clean** (`.ansible-lint`) — no `meta/argument_specs.yml` yet;
   add one documenting `defaults/main.yml`. Check `files/` copy/template
   tasks for explicit `mode:`. `files/snapshot_pct.sh` and
   `files/snapshot_qm.sh` are empty and not referenced by any task —
   orphaned, flag in `TODO.md`.
3. **Refactor `meta/main.yml`** — drop `platforms:`, set
   `min_ansible_version: "2.20"`, add `namespace: realtime`, set
   `issue_tracker_url` from the GitLab remote
   (`gitlab.real-time.com/ansible-roles/backuppc_client/-/issues`), fold
   the OS/version support statement into `description:`, expand
   `galaxy_tags:` beyond `debian`/`linux`/`ubuntu` (e.g. `ssh`,
   `authorizedkeys`, `sudo`, `backuppc`, `redhat`).
4. **LICENSE copyright stack** — no `LICENSE` file exists in this role;
   skip unless one gets added.
5. **`defaults/` vs `vars/` split** — `defaults/Debian.yml` duplicates
   `vars/Debian.yml`'s `known_host_keys_dir`/`ssh_host_pub_keys` content
   and isn't OS-agnostic; move anything still needed into
   `defaults/main.yml` or drop it, then delete `defaults/Debian.yml`.
6. **Preflight assertions** — add `tasks/preflight.yml`: ansible version
   check, supported OS family check, and validation that each
   `backuppc_client[]` entry has `username`/`home`/`shell` set (the
   fields `tasks/main.yml`'s user-creation loop depends on).
7. **README update** — rewrite from the current boilerplate template
   text into real content: requirements (`Ansible core >= 2.20`),
   supported platforms, `defaults/main.yml`/`vars/` variable tables,
   task flow including preflight.
8. **`molecule/default/molecule.yml` platform matrix + testinfra
   verifier** — align platform list with the `meta/main.yml`
   description sentence from step 3; switch to the testinfra verifier.
9. **Rewrite `converge.yml`** — remove any site-specific content, add
   the standard cache-update `pre_tasks`.
10. **Self-contained fixtures** — anonymize `molecule/default/group_vars/`
    if present; generate a throwaway SSH keypair fixture for the
    authorized_keys path.
11. **pytest-testinfra suite** — replace the current Ansible-based
    `verify.yml` with `molecule/default/tests/` skeletons covering
    packages, sudoers.d files, and the backuppc user/authorized_keys.
12. **`molecule/requirements.txt`** — add the pinned test-tooling
    requirements file; update `INSTALL.rst` to match. No
    `community.general`/other-collection modules found in use yet, so no
    role-root `requirements.yml` needed unless step 9's fixture work
    introduces one (e.g. for git-based fixtures).

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
`mysql_dump`, `postgres_dump`, `debian`, `ubuntu`, `redhat`

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
