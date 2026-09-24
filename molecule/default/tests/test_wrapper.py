# Copyright (c) 2026 Real Time Enterprises, Inc.
"""rsyncbackup-wrapper.sh behavior tests for the backuppc_client scenario.

Regression coverage for the shell-metacharacter injection fix: eval
re-parses the whole $SSH_ORIGINAL_COMMAND, so a command that merely
starts with the allowed rsync --server --sender prefix could smuggle a
metacharacter later in the line and have it executed. Each malicious
case proves both the rejection message and that no code actually ran
(via a side-effect file that must never appear), rather than just
checking the exit code.
"""
from __future__ import annotations

import shlex
from typing import TYPE_CHECKING

from ._data import BACKUPPC_WRAPPER_PATH

if TYPE_CHECKING:
    from testinfra.host import Host

_SIDE_EFFECT_FILE = "/tmp/molecule-wrapper-pwned"  # noqa: S108 -- ephemeral single-tenant test container

_INJECTION_PAYLOADS: dict[str, str] = {
    "command_substitution": (
        f"/usr/bin/sudo /usr/bin/rsync --server --sender $(touch {_SIDE_EFFECT_FILE}) ."
    ),
    "backticks": f"/usr/bin/sudo /usr/bin/rsync --server --sender `touch {_SIDE_EFFECT_FILE}` .",
    "semicolon": f"/usr/bin/sudo /usr/bin/rsync --server --sender .; touch {_SIDE_EFFECT_FILE}",
    "pipe": f"/usr/bin/sudo /usr/bin/rsync --server --sender . | touch {_SIDE_EFFECT_FILE}",
    "background_ampersand": f"/usr/bin/sudo /usr/bin/rsync --server --sender . & touch {_SIDE_EFFECT_FILE}",
}


def _run_wrapper(host: Host, ssh_original_command: str):  # noqa: ANN202
    host.run(f"rm -f {_SIDE_EFFECT_FILE}")
    env_assignment = f"SSH_ORIGINAL_COMMAND={shlex.quote(ssh_original_command)}"
    return host.run(f"{env_assignment} {BACKUPPC_WRAPPER_PATH}")


def test_wrapper_exists_and_executable(host: Host) -> None:
    f = host.file(BACKUPPC_WRAPPER_PATH)
    assert f.exists
    assert f.is_file
    assert f.mode == 0o755
    assert f.user == "root"


def test_wrapper_rejects_wrong_prefix(host: Host) -> None:
    result = _run_wrapper(host, "/bin/rm -rf /")
    assert result.rc != 0
    assert "Rejected command" in result.stderr
    assert not host.file(_SIDE_EFFECT_FILE).exists


def test_wrapper_accepts_legitimate_command_shape(host: Host) -> None:
    result = _run_wrapper(
        host,
        "/usr/bin/sudo /usr/bin/rsync --server --sender -vlogDtprze.iLsfxC . /some/path",
    )
    # Actually completing the rsync protocol handshake needs a real paired
    # client, which this test doesn't simulate -- what matters here is that
    # the command was never rejected by either the prefix or the
    # metacharacter check, proving it reached eval.
    assert "Rejected command" not in result.stderr


def test_wrapper_rejects_injection_payloads(host: Host) -> None:
    for label, payload in _INJECTION_PAYLOADS.items():
        result = _run_wrapper(host, payload)
        assert result.rc != 0, f"{label}: wrapper did not reject the payload"
        assert "Rejected command" in result.stderr, f"{label}: missing rejection message"
        assert not host.file(_SIDE_EFFECT_FILE).exists, f"{label}: injected command actually ran"
