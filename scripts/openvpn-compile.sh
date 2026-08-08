#!/bin/sh
set -e

# Use OPENVPN_VERSION
CLEAN_VERSION="${OPENVPN_VERSION#v}"

# Install build dependencies

apk add --no-cache lzo libcap-ng openssl lz4-libs

# Install build temp dependencies
apk add --no-cache --virtual .openvpn-builddeps \
  build-base libtool linux-headers pkgconfig \
  libcap-ng-dev lz4-dev linux-pam-dev openssl-dev lzo-dev curl

# Clone OpenVPN tarball(.tar.gz) from official repo
echo "Downloading OpenVPN ${CLEAN_VERSION} tarball..."
curl -fSL "https://github.com/OpenVPN/openvpn/releases/download/v${CLEAN_VERSION}/openvpn-${CLEAN_VERSION}.tar.gz" | tar xz

cd "openvpn-${CLEAN_VERSION}"

# Configure: disable DCO,etc, enable small build
./configure \
  --prefix=/usr \
  --sysconfdir=/etc \
  --disable-dco \
  --disable-pkcs11 \
  --enable-small \
  --disable-plugins \
  --disable-systemd \
  --disable-selinux \
  --disable-server \
  --disable-management \
  --disable-fragment \
  --disable-multihome \
  --disable-port-share \
  --disable-socks \
  --disable-http-proxy \
  --disable-pam

# ------------------------------------------------------------
# Build custom version string:
# - architecture from uname -m (works correctly under QEMU multi-arch)
# - OS from /etc/os-release
# - OS version/build from /etc/os-release
# - build date in UTC, formatted as "7 Aug 2026 14:56 UTC"
# - append repository URL
ARCH=$(uname -m)
OS=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
OS_V=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
DATE=$(date -u '+%d %b %Y %H:%M UTC')
REPO="https://github.com/qwertykolea/openvpn-client"

sed -i "s@#define TARGET_ALIAS .*@#define TARGET_ALIAS \"${ARCH}-${OS}-linux-v${OS_V}-musl built on ${DATE} | ${REPO} |\"@" config.h
# -----------------------------

# Compile using all available CPU cores
make -j

# Install only executables and libraries (skip man pages/doc to avoid missing file errors)
make install-exec

# Clean up source to save space
cd ..
rm -rf "openvpn-${CLEAN_VERSION}"

# Remove build-only dependencies
apk del .openvpn-builddeps

echo "bump" # simple marker to confirm script completed
