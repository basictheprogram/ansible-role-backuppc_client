"""sudoers.d file tests for the backuppc_client Molecule scenario.

Existence/permission checks are parametrized over CONFIG_FILES. Content
assertions get their own single-purpose test function.
"""
from __future__ import annotations

from typing import TYPE_CHECKING

import pytest

from ._data import BACKUPPC_USER, CONFIG_FILES

if TYPE_CHECKING:
    from testinfra.host import Host


@pytest.mark.parametrize("filename", CONFIG_FILES)
def test_config_file_exists(host: Host, config_dir: str, filename: str) -> None:
    f = host.file(f"{config_dir}/{filename}")
    assert f.exists
    assert f.is_file


@pytest.mark.parametrize("filename", CONFIG_FILES)
def test_config_file_mode(host: Host, config_dir: str, filename: str) -> None:
    f = host.file(f"{config_dir}/{filename}")
    assert f.mode == 0o440


def test_rsync_sudoers_content(host: Host, config_dir: str) -> None:
    f = host.file(f"{config_dir}/rsyncbackup_rsync")
    assert f.contains(f"{BACKUPPC_USER} ALL=NOPASSWD:/usr/bin/rsync")
