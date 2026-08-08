"""Session-scoped pytest fixtures for the backuppc_client Molecule scenario."""
from __future__ import annotations

from typing import TYPE_CHECKING

import pytest

from ._data import CONFIG_DIR_BY_FAMILY, REDHAT_DISTROS

if TYPE_CHECKING:
    from testinfra.host import Host


@pytest.fixture(scope="module")
def config_dir(host: Host) -> str:
    dist: str = host.system_info.distribution.lower()
    family = "redhat" if dist in REDHAT_DISTROS else "debian"
    return CONFIG_DIR_BY_FAMILY[family]
