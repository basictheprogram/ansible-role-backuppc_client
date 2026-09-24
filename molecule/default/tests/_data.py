"""Shared test constants for the backuppc_client Molecule scenario."""
from __future__ import annotations

# 1. OS-family detection.
REDHAT_DISTROS: frozenset[str] = frozenset({"redhat", "centos", "rocky", "almalinux", "fedora"})

# 2. Packages this role should install, per OS family (vars/Debian.yml, vars/RedHat.yml).
DEBIAN_PACKAGES: list[str] = ["openssh-server", "pigz", "rsync"]
REDHAT_PACKAGES: list[str] = ["openssh-server", "rsync"]

# 3. sudoers.d is a single fixed path across every supported OS family.
CONFIG_DIR_BY_FAMILY: dict[str, str] = {
    "debian": "/etc/sudoers.d",
    "redhat": "/etc/sudoers.d",
}

# 4. sudoers.d file the converge.yml fixture's "rsyncbackup" user should get.
CONFIG_FILES: list[str] = ["rsyncbackup_rsync"]

# 5. converge.yml fixture identity, reused by the user/authorized_keys tests.
BACKUPPC_USER: str = "rsyncbackup"
BACKUPPC_HOME: str = "/var/lib/rsyncbackup"
BACKUPPC_TEST_PUBKEY: str = (
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOUGIZtlsKNcAGaU4n/peqnAfXNsiV5NQJx3+WR4i4A/ molecule-test-key"
)

# 6. rsyncbackup-wrapper.sh (defaults/main.yml's backuppc_client_wrapper_path).
BACKUPPC_WRAPPER_PATH: str = "/usr/local/bin/rsyncbackup-wrapper.sh"
