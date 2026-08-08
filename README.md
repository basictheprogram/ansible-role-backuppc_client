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

* Debian: bookworm, trixie
* Ubuntu: jammy (22.04)
* EL (RHEL/Rocky/AlmaLinux): 8, 9

## Role Variables ##

### `defaults/main.yml`

| Variable               | Default                | Description                                                        |
|-------------------------|-------------------------|----------------------------------------------------------------------|
| `known_host_keys_dir`   | `{{ playbook_dir }}`   | Where fetched SSH host public keys are written.                    |
| `ssh_host_pub_keys`     | dsa/rsa/ecdsa/ed25519   | List of `/etc/ssh/*.pub` filenames to consider for known_hosts.    |

### `vars/` (OS-specific, loaded via `include_vars` + `first_found`, not user-overridable)

| File            | Matches                          | Overrides                              |
|------------------|-----------------------------------|------------------------------------------|
| `vars/Debian.yml`| `ansible_os_family == 'Debian'`  | `backuppc_client_packages` (adds `pigz`) |
| `vars/Ubuntu.yml`| `ansible_os_family == 'Debian'` and `ansible_distribution == 'Ubuntu'` | `backuppc_client_packages` (adds `pigz`) |
| `vars/jammy.yml` | `ansible_distribution_release == 'jammy'` | `backuppc_client_packages` (adds `pigz`) |
| `vars/RedHat.yml`| `ansible_os_family == 'RedHat'`  | `backuppc_client_packages` (no `pigz`)  |
| `vars/default.yml`| fallback when nothing else matches | `backuppc_client_packages`            |

### Consumer-supplied variables (no default; role behavior is conditional on these being set)

| Variable                        | Purpose                                                                 |
|-----------------------------------|----------------------------------------------------------------------------|
| `backuppc_client`                | List of dicts: `username`, `home`, `shell`, `comment`, `authorized_keys`, `key_options`, `deprecated_keys`. Drives user creation, `authorized_keys`, and sudoers.d rules. |
| `deprecated_backuppc_username`   | List of usernames to remove (required - see Preflight below; pass `[]` if there's nothing to remove). |
| `mysql_dump_script`              | Path to install the MySQL dump script; enables MySQL dump support when set. |
| `postgres_dump_script`           | Path to install the Postgres dump script; enables Postgres dump support when set. |
| `postgres_dump_file`             | Source file (under `files/`) for the Postgres dump script.             |
| `backuppc_ssh_key_scan`          | When defined, runs `tasks/known_hosts.yml` to `ssh-keyscan` the host into the BackupPC server's known_hosts. |
| `backuppc_client_mysql_dump`     | List of dicts (same shape as `backuppc_client`) for MySQL-dump-specific `authorized_keys`. |
| `backuppc_client_postgres_dump`  | List of dicts (same shape as `backuppc_client`) for Postgres-dump-specific `authorized_keys`. |

Example `backuppc_client` entry:

```yaml
backuppc_client:
  - username: ''
    home: ''
    shell: '/bin/bash'
    comment: 'BackupPC User'
    authorized_keys: ''
    key_options: 'command="sudo /usr/bin/rsync --server --sender -logDtpr --delete --numeric-ids --block-size=2048
        --exclude=''/proc/*''
        --exclude=''/sys/*''
        --exclude=''/mnt/*''
        --exclude=''/tmp/*''
        --exclude=''/var/tmp/*''
        --exclude=''/var/cache/apt/archives/*''
        --exclude=''/var/log/*/*''
        --exclude=''/var/log/*.*''
        --exclude=''*.iso''
        --exclude=''*.ova'' . /",
        no-port-forwarding,no-X11-forwarding,no-agent-forwarding'
```

## Task Flow ##

1. **Preflight** (`tasks/preflight.yml`) - checks, before touching the
   host:
   * `ansible-core >= 2.20`
   * `os_family` is `Debian` or `RedHat`
   * `deprecated_backuppc_username` is defined (list)
   * every `backuppc_client` entry has `username`, `home`, and `shell`
2. Gather OS-specific variables (`vars/`, via `first_found`)
3. Install packages and configure sudoers.d, per OS family
   (`tasks/debian.yml`, `tasks/ubuntu.yml`, `tasks/redhat.yml`,
   `tasks/sudoers_d.yml`)
4. Remove deprecated backuppc users
5. Create the backuppc user(s) from `backuppc_client`
6. Manage SSH `authorized_keys` (`tasks/ssh_keys.yml`)
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
            authorized_keys: "ssh-ed25519 AAAA..."
```

## License ##

[MIT](LICENSE)

## Author Information ##

[Real Time Enterprises Inc.](http://www.real-time.com),
[Bob Tanner](https://github.com/basictheprogram)
