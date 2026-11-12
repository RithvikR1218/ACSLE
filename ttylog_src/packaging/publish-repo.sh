#!/bin/sh
# Adds freshly built packages to the signed apt and dnf repos that are served
# from GitHub Pages, and regenerates the repo metadata. Older versions stay in
# the repo, so users can pin or downgrade.
#
#   packaging/publish-repo.sh PAGES_DIR DIST_DIR BASE_URL
#
#   PAGES_DIR  checkout of the gh-pages branch (created if missing)
#   DIST_DIR   output of `make packages` (only the .deb and .rpm are used)
#   BASE_URL   where PAGES_DIR is served, e.g. https://steelisi.github.io/ACSLE
#
# The signing key must already be in the gpg keyring:
#   ACSLE_GPG_KEY_ID      key id or fingerprint (required)
#   ACSLE_GPG_PASSPHRASE  only if the key has a passphrase
#
# Needs: gpg, apt-ftparchive (apt-utils), createrepo_c, rpmsign (rpm).
# Layout written to PAGES_DIR:
#   acsle.gpg / acsle.asc               public key (binary for apt, armored for rpm)
#   apt/pool/main/*.deb                 apt/dists/stable/{InRelease,Release,Release.gpg}
#   rpm/*.rpm  rpm/repodata/            rpm/acsle.repo

set -eu

die() { echo "publish-repo: ERROR: $*" >&2; exit 1; }
log() { echo "publish-repo: $*"; }

[ $# -eq 3 ] || die "usage: $0 PAGES_DIR DIST_DIR BASE_URL"
PAGES=$1
DIST=$2
BASE_URL=${3%/}
KEY=${ACSLE_GPG_KEY_ID:?set ACSLE_GPG_KEY_ID to the signing key}

for tool in gpg apt-ftparchive createrepo_c rpmsign; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool not found"
done
ls "$DIST"/*.deb "$DIST"/*.rpm >/dev/null 2>&1 || die "no .deb/.rpm in $DIST; run make packages first"

mkdir -p "$PAGES"
PAGES=$(cd "$PAGES" && pwd)
DIST=$(cd "$DIST" && pwd)

# gpg in batch mode, with the passphrase from a file so it never shows in ps
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
GPG_ARGS="--batch --yes --pinentry-mode loopback"
if [ -n "${ACSLE_GPG_PASSPHRASE:-}" ]; then
    printf '%s' "$ACSLE_GPG_PASSPHRASE" > "$TMP/pass"
    GPG_ARGS="$GPG_ARGS --passphrase-file $TMP/pass"
fi
# shellcheck disable=SC2086  # GPG_ARGS is a word list on purpose
gpg_sign() { gpg $GPG_ARGS --local-user "$KEY" "$@"; }

# Public key
gpg --batch --yes --export "$KEY" > "$PAGES/acsle.gpg"
gpg --batch --yes --armor --export "$KEY" > "$PAGES/acsle.asc"
[ -s "$PAGES/acsle.gpg" ] || die "key $KEY not found in the gpg keyring"
touch "$PAGES/.nojekyll"   # serve every file as is

# ---- apt ----
APT=$PAGES/apt
mkdir -p "$APT/pool/main"
cp "$DIST"/*.deb "$APT/pool/main/"
cd "$APT"
# The package is arch "all", but apt clients only fetch their native arch
# index, so list it under each architecture people actually use.
ARCHES="amd64 arm64 armhf i386"
for arch in $ARCHES all; do
    dir=dists/stable/main/binary-$arch
    mkdir -p "$dir"
    apt-ftparchive packages pool > "$dir/Packages"
    gzip -9nkf "$dir/Packages"
done
apt-ftparchive \
    -o APT::FTPArchive::Release::Origin=ACSLE \
    -o APT::FTPArchive::Release::Label=ACSLE \
    -o APT::FTPArchive::Release::Suite=stable \
    -o APT::FTPArchive::Release::Codename=stable \
    -o APT::FTPArchive::Release::Components=main \
    -o "APT::FTPArchive::Release::Architectures=$ARCHES all" \
    release dists/stable > "$TMP/Release"
mv "$TMP/Release" dists/stable/Release
gpg_sign --clearsign -o dists/stable/InRelease dists/stable/Release
gpg_sign --armor --detach-sign -o dists/stable/Release.gpg dists/stable/Release
log "apt repo: $(ls pool/main | wc -l) package(s)"

# ---- rpm ----
RPM=$PAGES/rpm
mkdir -p "$RPM"
for f in "$DIST"/*.rpm; do
    cp "$f" "$TMP/"
    rpmsign --addsign \
        --define "__gpg $(command -v gpg)" \
        --define "_gpg_name $KEY" \
        --define "_gpg_sign_cmd_extra_args $GPG_ARGS" \
        "$TMP/$(basename "$f")" >/dev/null
    mv "$TMP/$(basename "$f")" "$RPM/"
done
createrepo_c --quiet --update "$RPM"
rm -f "$RPM/repodata/repomd.xml.asc"
gpg_sign --armor --detach-sign -o "$RPM/repodata/repomd.xml.asc" "$RPM/repodata/repomd.xml"
cat > "$RPM/acsle.repo" <<EOF
[acsle]
name=ACSLE
baseurl=$BASE_URL/rpm
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$BASE_URL/acsle.asc
EOF
log "rpm repo: $(ls "$RPM"/*.rpm | wc -l) package(s)"
log "done; serve $PAGES at $BASE_URL"
