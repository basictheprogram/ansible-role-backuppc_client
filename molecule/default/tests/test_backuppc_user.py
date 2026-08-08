"""backuppc user / authorized_keys tests for the backuppc_client Molecule scenario."""
from __future__ import annotations

from typing import TYPE_CHECKING

from ._data import BACKUPPC_HOME, BACKUPPC_TEST_PUBKEY, BACKUPPC_USER

if TYPE_CHECKING:
    from testinfra.host import Host


def test_backuppc_user_exists(host: Host) -> None:
    user = host.user(BACKUPPC_USER)
    assert user.exists
    assert user.home == BACKUPPC_HOME
    assert user.shell == "/bin/bash"


def test_backuppc_user_password_locked(host: Host) -> None:
    shadow_entry = host.file("/etc/shadow")
    assert shadow_entry.contains(f"{BACKUPPC_USER}:!")


def test_backuppc_authorized_keys_installed(host: Host) -> None:
    authorized_keys = host.file(f"{BACKUPPC_HOME}/.ssh/authorized_keys")
    assert authorized_keys.exists
    assert authorized_keys.contains(BACKUPPC_TEST_PUBKEY)
