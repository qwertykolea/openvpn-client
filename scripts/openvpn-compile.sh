#!/bin/sh
set -e

# Determine which branch/tag to clone: use OPENVPN_VERSION if set, else master
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

# Configure: disable DCO (not useful in container), LZ4 (optional), enable small build
./configure --disable-dco --disable-lz4 --enable-small

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
