# Releasing ACSLE

Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml`, which:

1. Builds the `.deb`, `.rpm`, `.apk` and Arch packages, then installs each one in
   containers of every supported distro (`ci.yml`, `packaging/smoke-test.sh`).
2. Creates a GitHub Release with the packages, a source tarball
   (`acsle-X.Y.Z.tar.gz`) and `SHA256SUMS`.
3. Adds the `.deb` and `.rpm` to the signed apt and dnf repos on the `gh-pages`
   branch (`packaging/publish-repo.sh`). These are served at
   `https://<owner>.github.io/ACSLE/`.

Nothing in the workflows names the repo owner, so the same files work on a fork
for testing and on `STEELISI/ACSLE`.

## Cutting a release

```sh
git switch master && git pull
git tag -a v1.2.0 -m "ACSLE 1.2.0"
git push origin v1.2.0
```

- The version comes from the tag only: there is no file to bump. `acsle --version`
  reports it.
- A tag with a suffix (`v1.2.0-rc1`) becomes a **pre-release**. It gets a GitHub
  Release but is **not** added to the apt/dnf repo, so use one to test a release.
- If a step fails, fix it, delete the tag and Release, and push the tag again:
  `gh release delete v1.2.0 --cleanup-tag --yes && git tag -d v1.2.0`

## One-time setup (per repository)

A repo admin has to do this once. Until it is done, releases still work, but the
apt/dnf step is skipped with a warning.

### 1. Signing key

Use a dedicated key that signs only ACSLE packages. Don't use a personal key.
Use RSA 4096, because RHEL 8's rpm can't verify ed25519.

```sh
export GNUPGHOME=$(mktemp -d)       # keep it out of your own keyring
gpg --batch --pinentry-mode loopback --passphrase '' --quick-gen-key "ACSLE Packages <sunshine@isi.edu>" rsa4096 sign 5y
gpg --armor --export-secret-keys "ACSLE Packages" > acsle-signing-key.asc
gpg --armor --export "ACSLE Packages"             > acsle-public-key.asc
```

To protect the key with a passphrase, leave out `--batch --pinentry-mode loopback --passphrase ''`
so gpg asks for one, and add the
passphrase as the `ACSLE_GPG_PASSPHRASE` secret.

Store `acsle-signing-key.asc` somewhere safe outside GitHub, such as the lab's
password manager. If it is lost, every user has to import a new key.

### 2. Repository settings

- **Settings → Secrets and variables → Actions**: add `ACSLE_GPG_PRIVATE_KEY`
  with the full contents of `acsle-signing-key.asc` (and `ACSLE_GPG_PASSPHRASE`
  if the key has one). Then delete the local files and `$GNUPGHOME`.
- **Settings → Actions → General → Workflow permissions**: *Read and write permissions*.
- After the first stable release has created the `gh-pages` branch:
  **Settings → Pages → Build and deployment**: *Deploy from a branch*, `gh-pages`, `/ (root)`.

### 3. Check it

In a fresh container, follow the "From the package repo" steps in `INSTALL.md`.
Replace `steelisi` with the owner of the repo you are testing.

## Testing on a fork

Do the same setup on the fork with a **throwaway key**. The fork's repo is at
`https://<your-user>.github.io/ACSLE/`. When the code is merged into
`STEELISI/ACSLE`, generate the real key there. Users only ever import that key.

## Testing locally

```sh
cd ttylog_src
make packages VERSION=1.2.0          # needs nfpm 2.48+
docker run --rm -v "$PWD:/src" -w /src ubuntu:24.04 sh packaging/smoke-test.sh
```

`publish-repo.sh` also runs locally. It needs gpg, apt-utils, createrepo-c and
rpm, so run it in an Ubuntu container with a test key. Read the header of the
script for the arguments.

## Repo layout (gh-pages)

```
acsle.gpg, acsle.asc        public key (apt / rpm)
apt/pool/main/*.deb         every released .deb
apt/dists/stable/           InRelease, Release(.gpg), main/binary-*/Packages
rpm/*.rpm, rpm/repodata/    every released .rpm (signed), repomd.xml.asc
rpm/acsle.repo              dnf/zypper repo file
```

All versions stay in the repo, so `apt install acsle-ttylog=1.1.0` works. GitHub
Pages has a 1 GB limit, and each release adds about 70 KB.
