#!/bin/sh
set -e

# Use OPENVPN_VERSION to select branch/tag; fallback to master
if [ -z "$OPENVPN_VERSION" ]; then
    BRANCH="master"
else
    BRANCH="v$OPENVPN_VERSION"
fi

# Install build dependencies (will be removed later to keep final image small)
apk add --no-cache \
    autoconf automake build-base gcc git libtool linux-headers make \
    pkgconfig file g++ wget openssl-dev lzo lzo-dev \
    linux-pam-dev libcap-ng libcap-ng-dev

# Clone OpenVPN source from official repo
git clone --branch "$BRANCH" https://github.com/OpenVPN/openvpn.git
cd openvpn

# Generate build system files
autoreconf -i -v -f

# Build custom version string:
# - architecture from uname -m (works correctly under QEMU multi-arch)
# - OS from /etc/os-release
# - OS version/build from /etc/os-release
# - build date in UTC, formatted as "7 Aug 2026 14:56 UTC"
# - append repository URL
ARCH=$(uname -m)
OS=$(grep -E '^ID=' /etc/os-release)
OS_v=$(grep -E '^VERSION_ID=' /etc/os-release)
REPO="https://github.com/qwertykolea/openvpn-client"
DATE=$(date -u '+%d %b %Y %H:%M UTC')
VERSION_STRING="OpenVPN ${OPENVPN_VERSION} ${ARCH}-${OS}-linux-v${OS_v}-musl [SSL (OpenSSL)] [LZO] [EPOLL] [MH/PKTINFO] [AEAD] built on ${DATE} | ${REPO}"

# Configure: disable DCO and LZ4, enable small build, override version string
./configure --disable-dco --disable-lz4 --enable-small --with-version-string="$VERSION_STRING"

# Compile using all available CPU cores
make -j

# Install only executables and libraries (skip man pages/doc to avoid missing file errors)
make install-exec

# Clean up source to save space
cd ..
rm -rf openvpn

# Remove build-only dependencies to keep final image lean
apk del autoconf automake build-base gcc git libtool linux-headers make \
       pkgconfig file g++ wget openssl-dev lzo-dev \
       linux-pam-dev libcap-ng-dev

echo "bump" # simple marker to confirm script completed
