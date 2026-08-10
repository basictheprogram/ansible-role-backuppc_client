#!/bin/bash
# Deployed by ansible-role-backuppc_client (tasks/ssh_keys.yml).
#
# Forced command for the backup user's authorized_keys entry. Validates
# that the incoming SSH command is actually
# "/usr/bin/sudo /usr/bin/rsync --server --sender ..." and re-execs it,
# instead of substituting a frozen/hardcoded rsync command string.
#
# The old approach baked one specific rsync invocation (flags, excludes,
# block-size) into command= at key-provisioning time. Since command=
# discards whatever the client actually sent, that frozen string silently
# stopped matching what BackupPC/rsync_bpc was really requesting the
# moment either side's rsync version or flags changed - the client's
# negotiated protocol/options never reached the real rsync process. This
# wrapper re-execs the actual incoming command instead, so BackupPC's own
# config (config.pl's RsyncArgs/RsyncArgsExtra) controls rsync flags and
# excludes, not this host's SSH key restriction.
#
# The prefix includes "/usr/bin/sudo" because config.pl's
# $Conf{RsyncClientPath} is '/usr/bin/sudo /usr/bin/rsync' - that's what
# BackupPC actually sends as $SSH_ORIGINAL_COMMAND, not a bare "rsync ...".
# The security guarantee is the same either way: this only ever permits
# "/usr/bin/sudo /usr/bin/rsync --server --sender ...", nothing else.
#
# eval (not a bare exec of the unquoted variable) is required so
# quoted/escaped argument segments rsync sends (e.g. exclude patterns
# with embedded shell quoting) get re-parsed correctly instead of just
# word-split on spaces - the same shell parsing the old hardcoded
# forced-command approach relied on.
case "$SSH_ORIGINAL_COMMAND" in
  "/usr/bin/sudo /usr/bin/rsync --server --sender "*)
    eval "exec $SSH_ORIGINAL_COMMAND"
    ;;
  *)
    echo "Rejected command: $SSH_ORIGINAL_COMMAND" >&2
    exit 1
    ;;
esac
