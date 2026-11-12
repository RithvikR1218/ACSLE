#!/bin/sh
# Installs the built package inside a distro container and checks that it works.
# Run as root inside the container, from ttylog_src/, after `make packages`:
#
#   docker run --rm -v "$PWD:/src" -w /src ubuntu:24.04 sh packaging/smoke-test.sh
#
# Checks: install with the opt-out (ACSLE_NO_SSHD=1, or /etc/acsle/no-sshd on
# Alpine) leaves sshd alone, a normal install sets
# ForceCommand, and removing the package takes it out again.

set -eu

DIST=${DIST:-dist}
PKG=acsle-ttylog

fail() { echo "FAIL: $*" >&2; exit 1; }
step() { echo "==> $*"; }

if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    pkg_install() { apt-get install -y -qq "./$(ls "$DIST"/*.deb)"; }
    pkg_remove()  { apt-get remove -y -qq "$PKG"; }
elif command -v dnf >/dev/null 2>&1; then
    pkg_install() { dnf install -y -q "$(ls "$DIST"/*.rpm)"; }
    pkg_remove()  { dnf remove -y -q --noautoremove "$PKG"; }
elif command -v zypper >/dev/null 2>&1; then
    pkg_install() { zypper -n -q install --allow-unsigned-rpm "$(ls "$DIST"/*.rpm)"; }
    pkg_remove()  { zypper -n -q remove "$PKG"; }
elif command -v apk >/dev/null 2>&1; then
    apk update -q
    pkg_install() { apk add -q --allow-untrusted "./$(ls "$DIST"/*.apk)"; }
    pkg_remove()  { apk del -q "$PKG"; }
elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm >/dev/null
    pkg_install() { pacman -U --noconfirm "$(ls "$DIST"/*.pkg.tar.zst)"; }
    pkg_remove()  { pacman -R --noconfirm "$PKG"; }
else
    fail "no supported package manager"
fi

has_force_command() {
    grep -rqs "ForceCommand /usr/lib/acsle/script.sh" /etc/ssh/sshd_config /etc/ssh/sshd_config.d
}

opt_out_install() {
    if command -v apk >/dev/null 2>&1; then
        # apk runs package scripts with an empty environment, so only the marker file works
        mkdir -p /etc/acsle && touch /etc/acsle/no-sshd
        pkg_install
        rm -f /etc/acsle/no-sshd
    else
        # Subshell: in POSIX sh, VAR=x before a function call stays set afterwards
        (export ACSLE_NO_SSHD=1; pkg_install)
    fi
}

step "install with the sshd opt-out"
opt_out_install
acsle --version
acsle --version | grep -q 'acsle [0-9]' || fail "acsle --version has no version number"
acsle sessions >/dev/null || fail "acsle sessions failed"
[ -f /etc/acsle/acsle.conf ] || fail "/etc/acsle/acsle.conf missing"
has_force_command && fail "ForceCommand was set despite the opt-out"
pkg_remove

step "install normally"
pkg_install
has_force_command || fail "ForceCommand not set after install"

step "remove"
pkg_remove
has_force_command && fail "ForceCommand still set after removal"
[ -e /usr/bin/acsle ] && fail "/usr/bin/acsle still there after removal"

echo "PASS"
