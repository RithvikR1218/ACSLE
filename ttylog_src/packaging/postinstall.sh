#!/bin/sh
# Point sshd's ForceCommand at the installed scripts (idempotent, so upgrades are fine).
# Opt out on testbeds where sshd must not change (the package version of
# install.sh --no-sshd): set ACSLE_NO_SSHD=1 or create /etc/acsle/no-sshd.
if [ "${ACSLE_NO_SSHD:-0}" = 1 ] || [ -e /etc/acsle/no-sshd ]; then
    echo "acsle: sshd config not changed (ACSLE_NO_SSHD); record sessions with 'acsle-record'"
    exit 0
fi
/usr/lib/acsle/install.sh --sshd-only
