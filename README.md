# backuppc_client #

Configures a BackupPC client host: creates the backup user, manages SSH
`authorized_keys` for the rsync-over-ssh backup transport, and configures
`sudoers.d` rules for rsync (and, optionally, MySQL/Postgres dump
scripts) so the BackupPC server can pull backups without a password.

## Requirements ##

* Ansible core >= 2.20
* `ansible.posix` and `ansible.utils` collections, declared in
  `requirements.yml`; install with
  `ansible-galaxy collection install -r requirements.yml`

## Supported Platforms ##

* Debian: trixie
* Ubuntu: 22.04+ — `tasks/ubuntu.yml` gates on
  `ansible_facts['lsb']['major_release'] >= 20`, a looser check than
  the supported-platform statement; jammy (22.04), noble (24.04), and
  resolute (26.04) are what's actually exercised in molecule
* EL (RHEL/Rocky/AlmaLinux): 9, 10

## Role Variables ##

### `defaults/main.yml`

| Variable               | Default                | Description                                                        |
|-------------------------|-------------------------|----------------------------------------------------------------------|
| `backuppc_client_ssh_pubkey_accepted_types` | `+ssh-rsa` | `sshd_config` `PubkeyAcceptedKeyTypes` value (Ubuntu 20.04+). Validated in preflight against `ssh -Q PubkeyAcceptedKeyTypes` on the target host. |
| `backuppc_client_wrapper_path` | `/usr/local/bin/rsyncbackup-wrapper.sh` | Where the forced-command wrapper script (`files/usr/local/bin/rsyncbackup-wrapper.sh`) is deployed, and what each `backuppc_client` entry's `authorized_keys` `command=` restriction points at. See "The rsyncbackup-wrapper.sh pattern" below. |
| `backuppc_client_known_hosts_remote_user` | `ansible` | Remote user `tasks/known_hosts.yml` connects to `backuppc_client_known_hosts_server` as. |
| `backuppc_client_known_hosts_owner` | `backuppc` | Owner set on the BackupPC server's `known_hosts` file. |
| `backuppc_client_known_hosts_group` | `backuppc` | Group set on the BackupPC server's `known_hosts` file. |

### `vars/` (OS-specific, loaded via `include_vars` + `first_found`, not user-overridable)

| File            | Matches                          | Overrides                              |
|------------------|-----------------------------------|------------------------------------------|
| `vars/Debian.yml`| `ansible_os_family == 'Debian'`  | `backuppc_client_packages` (adds `pigz`) |
| `vars/Ubuntu.yml`| `ansible_os_family == 'Debian'` and `ansible_distribution == 'Ubuntu'` | `backuppc_client_packages` (adds `pigz`) |
| `vars/RedHat.yml`| `ansible_os_family == 'RedHat'`  | `backuppc_client_packages` (no `pigz`)  |
| `vars/default.yml`| fallback when nothing else matches | `backuppc_client_packages`            |

### Required variables (no default; validated in Preflight below)

| Variable                        | Purpose                                                                 |
|-----------------------------------|----------------------------------------------------------------------------|
| `backuppc_client`                | List of dicts: `username`, `home`, `shell`, `comment`, `authorized_keys`, `key_options`, `deprecated_keys`. Drives user creation, `authorized_keys`, and sudoers.d rules. Required (pass `[]` if this host has no backup users). |
| `deprecated_backuppc_username`   | List of dicts: `username`. Old backup users to remove. Required; pass `[]` if there's nothing to remove. |

### Consumer-supplied variables (no default; role behavior is conditional on these being set)

| Variable                        | Purpose                                                                 |
|-----------------------------------|----------------------------------------------------------------------------|
| `mysql_dump_script`              | Path to install the MySQL dump script; enables MySQL dump support when set. |
| `postgres_dump_script`           | Path to install the Postgres dump script; enables Postgres dump support when set. |
| `postgres_dump_file`             | Source file (under `files/`) for the Postgres dump script. Required whenever `postgres_dump_script` is set (validated in preflight) — "Copy Postgres dump script" uses it unconditionally. |
| `backuppc_ssh_key_scan`          | When defined, runs `tasks/known_hosts.yml` to `ssh-keyscan` the host into the BackupPC server's known_hosts. Requires `backuppc_client_known_hosts_server` to also be set (validated in preflight). |
| `backuppc_client_known_hosts_server` | BackupPC server hostname `tasks/known_hosts.yml` delegates to. Required whenever `backuppc_ssh_key_scan` is set. |
| `backuppc_client_mysql_dump`     | List of dicts: `username`, `authorized_keys`, `key_options` (all required). Grants MySQL-dump-specific `authorized_keys` — not the same shape as `backuppc_client` (no `home`/`shell`/`deprecated_keys`). |
| `backuppc_client_postgres_dump`  | Same shape as `backuppc_client_mysql_dump`, for Postgres-dump-specific `authorized_keys`. |

Example `backuppc_client` entry — the common case needs no `key_options`
at all; the role forces `command=` to `backuppc_client_wrapper_path`
automatically:

```yaml
deprecated_backuppc_username: []
backuppc_client:
  - username: rsyncbackup
    home: /var/lib/rsyncbackup
    shell: /bin/bash
    comment: 'BackupPC User'
    authorized_keys:
      - "ssh-ed25519 AAAA... rsyncbackup@backuppc-server"
    deprecated_keys: []
```

Only set `key_options` directly if a host needs something other than
the standard rsync-pull restriction (e.g. a completely different
forced command).

DSA (`ssh-dss`) keys in `authorized_keys` are rejected in preflight —
this role's own `sshd_config` already excludes `ssh-dss` from
`PubkeyAcceptedKeyTypes` on Ubuntu 20.04+, so a DSA key here would
silently fail to authenticate. Use ed25519 or RSA.

## The rsyncbackup-wrapper.sh pattern ##

`authorized_keys` used to force a *frozen, hand-written* rsync
command — the full invocation (flags, `--exclude` list, block-size)
baked into `command=` at the time the key was provisioned. SSH's
`command=` option means whatever the actual SSH client (BackupPC)
sends in `$SSH_ORIGINAL_COMMAND` is discarded entirely and that fixed
string runs instead. That's a stale-config trap: the moment either
side's rsync version, protocol, or flags changes, the frozen command
silently stops matching what BackupPC/`rsync_bpc` is actually asking
for — confirmed as the root cause of a real production failure
(`protocol version mismatch` / `rsync error: protocol incompatibility`)
when a client's rsync was upgraded past the version the forced command
was written for.

`files/usr/local/bin/rsyncbackup-wrapper.sh` fixes this by validating
the *shape* of the incoming command instead of substituting a copy of
it:

```bash
case "$SSH_ORIGINAL_COMMAND" in
  "/usr/bin/sudo /usr/bin/rsync --server --sender "*)
    case "$SSH_ORIGINAL_COMMAND" in
      *'`'* | *'$('* | *';'* | *'|'* | *'&'*)
        echo "Rejected command: contains shell metacharacters" >&2
        exit 1
        ;;
    esac
    eval "exec $SSH_ORIGINAL_COMMAND"
    ;;
  *)
    echo "Rejected command: $SSH_ORIGINAL_COMMAND" >&2
    exit 1
    ;;
esac
```

The match pattern includes `/usr/bin/sudo /usr/bin/rsync` because
`config.pl`'s `$Conf{RsyncClientPath}` is `/usr/bin/sudo /usr/bin/rsync`
— that's the literal string BackupPC sends as `$SSH_ORIGINAL_COMMAND`,
not a bare `rsync ...`. `eval "exec $SSH_ORIGINAL_COMMAND"` (not a bare
unquoted `exec`) is required so quoted/escaped argument segments rsync
sends get re-parsed correctly instead of just word-split on spaces —
the same shell parsing the old hardcoded forced-command relied on.

Because `eval` re-parses the *whole* string, a command that merely
starts with the allowed prefix could still smuggle a shell
metacharacter (`` ` ``, `$(`, `;`, `|`, `&`) later in the line and have
it executed during that re-parse — the prefix check alone doesn't
guarantee "rsync only". The inner `case` rejects any command
containing one of those characters before `eval` ever sees it.

This keeps the same security property (the key can only ever trigger
`/usr/bin/sudo /usr/bin/rsync --server --sender ...`, nothing else)
while staying correct regardless of which rsync version or flags
either side is currently using. It also means rsync flags/excludes are
no longer this role's concern at all — they belong in the BackupPC
server's `config.pl` (`RsyncArgs`/`RsyncArgsExtra`), applied once,
server-side, rather than duplicated into every client's SSH key
restriction.

`Defaults:<user> !use_pty` is required alongside the sudoers
`NOPASSWD:/usr/bin/rsync` rule (`tasks/sudoers_d.yml`) if the target's
global `/etc/sudoers` has `Defaults use_pty` set — pty allocation under
sudo can corrupt rsync's binary protocol stream.

## Task Flow ##

1. **Preflight** (`tasks/preflight.yml`) - checks, before touching the
   host:
   * `ansible-core >= 2.20`
   * `os_family` is `Debian` or `RedHat`
   * `deprecated_backuppc_username` is defined (list) and each entry
     has `username`
   * `backuppc_client` is defined (list) and each entry has `username`,
     `home`, and `shell`
   * no `backuppc_client`/`backuppc_client_mysql_dump`/
     `backuppc_client_postgres_dump` entry's `authorized_keys` contains
     a DSA (`ssh-dss`) key
   * `backuppc_client_known_hosts_server` is set whenever
     `backuppc_ssh_key_scan` is
   * `postgres_dump_file` is set whenever `postgres_dump_script` is
   * on Ubuntu 20.04+, `backuppc_client_ssh_pubkey_accepted_types` only
     requests key types this host's `ssh -Q PubkeyAcceptedKeyTypes`
     actually recognizes
2. Gather OS-specific variables (`vars/`, via `first_found`)
3. Install packages and configure sudoers.d, per OS family
   (`tasks/debian.yml`, `tasks/ubuntu.yml`, `tasks/redhat.yml`,
   `tasks/sudoers_d.yml`)
4. Remove deprecated backuppc users
5. Create the backuppc user(s) from `backuppc_client`
6. Manage SSH `authorized_keys` (`tasks/ssh_keys.yml`):
   * deploy `rsyncbackup-wrapper.sh` to `backuppc_client_wrapper_path`
   * set/remove `authorized_keys` entries
   * verify: wrapper script is root-owned and executable; `sudo -l`
     for each `backuppc_client` user shows the expected
     `NOPASSWD: /usr/bin/rsync` rule
7. `ssh-keyscan` the host into the BackupPC server's known_hosts, if
   `backuppc_ssh_key_scan` is defined (`tasks/known_hosts.yml`)

## Dependencies ##

None.

## Example Playbook ##

```yaml
- hosts: servers
  become: true
  roles:
    - role: realtime.backuppc_client
      vars:
        deprecated_backuppc_username: []
        backuppc_client:
          - username: backuppc
            home: /var/lib/backuppc
            shell: /bin/bash
            comment: 'BackupPC User'
            authorized_keys:
              - "ssh-ed25519 AAAA..."
            deprecated_keys: []
```

## License ##

[MIT](LICENSE)

## Author Information ##

[Bob Tanner](https://github.com/basictheprogram)
