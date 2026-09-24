# TODO

Flagged during the 2026-09-24 `ansible-sync-role` pass, not fixed in
that session. Not a general backlog — see `CLAUDE.md`'s "Settled
decisions" for everything that *was* decided/fixed this session (and
in prior sessions; earlier revisions of this file preserved a much
longer historical log that's now redundant with that section).

* **Three empty, unreferenced files under `files/`**:
  `snapshot_pct.sh`, `snapshot_qm.sh`, `dump_mongodb.sh`. Either flesh
  them out and wire them into a task (a Proxmox `pct`/`qm` snapshot
  feature for the first two; a `tasks/mongo_dump.yml` paralleling
  `mysql_dump.yml`/`postgres_dump.yml` for the third) or delete them.
* **`tasks/known_hosts.yml` (the `backuppc_ssh_key_scan` feature) has
  no molecule test coverage.** It delegates to an external BackupPC
  server (`backuppc_client_known_hosts_server`), which doesn't fit a
  single-container fixture cleanly — would need a multi-node molecule
  scenario or an equivalent workaround.
* **`mysql_dump.yml`/`postgres_dump.yml` have zero molecule coverage,
  on any platform.** `converge.yml` never sets `mysql_dump_script`,
  `postgres_dump_script`, `backuppc_client_mysql_dump`, or
  `backuppc_client_postgres_dump`, so neither task file has ever
  actually converged in CI — including on the RedHat path this
  session just wired in. Worth a fixture pass: set the vars, add
  `dump_mysql.sh`/a real `postgres_dump_file` fixture, and assert the
  sudoers.d rules + authorized_keys entries land correctly.
