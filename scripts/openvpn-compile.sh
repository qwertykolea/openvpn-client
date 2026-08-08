```sh
#!/bin/sh
set -eu

# ============================================================
# OpenVPN build script for Alpine Linux
#
# Target platforms:
#   linux/amd64
#   linux/arm64
#   linux/arm/v7
#   linux/arm/v6
#
# Required environment variable:
#   OPENVPN_VERSION
#
# Optional environment variables:
#   OPENVPN_SHA256
#   TARGETARCH
#   TARGETVARIANT
#
# Example:
#   OPENVPN_VERSION=2.6.14
#
# If OPENVPN_SHA256 is provided, the downloaded source archive
# will be verified before compilation.
# ============================================================

: "${OPENVPN_VERSION:?ERROR: OPENVPN_VERSION must be specified}"

OPENVPN_REPO="https://github.com/OpenVPN/openvpn"
OPENVPN_ARCHIVE="openvpn-${OPENVPN_VERSION}.tar.gz"
OPENVPN_URL="${OPENVPN_REPO}/archive/refs/tags/v${OPENVPN_VERSION}.tar.gz"

# ------------------------------------------------------------
# Detect target architecture
#
# Docker Buildx provides:
#   TARGETARCH=amd64
#   TARGETARCH=arm64
#   TARGETARCH=arm
#
#   TARGETVARIANT=v7
#   TARGETVARIANT=v6
#
# Fallback to uname -m when build arguments are unavailable.
# ------------------------------------------------------------

if [ -n "${TARGETARCH:-}" ]; then

    case "${TARGETARCH}" in
        amd64)
            ARCH="amd64"
            ;;
        arm64)
            ARCH="arm64"
            ;;
        arm)
            case "${TARGETVARIANT:-}" in
                v6)
                    ARCH="armv6"
                    ;;
                v7)
                    ARCH="armv7"
                    ;;
                "")
                    ARCH="arm"
                    ;;
                *)
                    ARCH="arm${TARGETVARIANT}"
                    ;;
            esac
            ;;
        *)
            ARCH="${TARGETARCH}${TARGETVARIANT:-}"
            ;;
    esac

else

    case "$(uname -m)" in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="armv7"
            ;;
        armv6l)
            ARCH="armv6"
            ;;
        arm*)
            ARCH="$(uname -m)"
            ;;
        *)
            ARCH="$(uname -m)"
            ;;
    esac

fi

echo "============================================================"
echo "OpenVPN build"
echo "============================================================"
echo "Version:       ${OPENVPN_VERSION}"
echo "Architecture:  ${ARCH}"
echo "Source:        ${OPENVPN_URL}"
echo "============================================================"


# ------------------------------------------------------------
# Install build dependencies
# ------------------------------------------------------------

echo "[1/7] Installing build dependencies..."

apk add --no-cache \
    autoconf \
    automake \
    build-base \
    ca-certificates \
    libtool \
    linux-headers \
    pkgconfig \
    openssl-dev \
    lzo-dev \
    libcap-ng-dev \
    tar


# ------------------------------------------------------------
# Download OpenVPN release
# ------------------------------------------------------------

echo "[2/7] Downloading OpenVPN ${OPENVPN_VERSION}..."

cd /tmp

rm -f "${OPENVPN_ARCHIVE}"

wget -q \
    -O "${OPENVPN_ARCHIVE}" \
    "${OPENVPN_URL}"


# ------------------------------------------------------------
# Verify source archive
#
# OPENVPN_SHA256 is optional.
#
# Example:
#   OPENVPN_SHA256=0123456789abcdef...
# ------------------------------------------------------------

if [ -n "${OPENVPN_SHA256:-}" ]; then

    echo "[3/7] Verifying SHA-256 checksum..."

    echo "${OPENVPN_SHA256}  ${OPENVPN_ARCHIVE}" | sha256sum -c -

else

    echo "[3/7] SHA-256 verification skipped."
    echo "      Set OPENVPN_SHA256 to enable source verification."

fi


# ------------------------------------------------------------
# Extract source
# ------------------------------------------------------------

echo "[4/7] Extracting source..."

rm -rf "openvpn-${OPENVPN_VERSION}"

tar -xzf "${OPENVPN_ARCHIVE}"

cd "openvpn-${OPENVPN_VERSION}"


# ------------------------------------------------------------
# Configure
#
# DCO:
#   Disabled because this container is intended primarily
#   for MikroTik/RouterOS where userspace OpenVPN is desired.
#
# PKCS#11:
#   Disabled because hardware PKCS#11 token support is not
#   required for this client container.
#
# LZ4:
#   Enabled for compatibility with OpenVPN configurations
#   that require LZ4 compression support.
#
# Small:
#   Enable OpenVPN's reduced-size build options.
# ------------------------------------------------------------

echo "[5/7] Configuring OpenVPN..."

./configure \
    --disable-dco \
    --disable-pkcs11 \
    --enable-lz4 \
    --enable-small


# ------------------------------------------------------------
# Build
# ------------------------------------------------------------

echo "[6/7] Compiling OpenVPN..."

make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"


# ------------------------------------------------------------
# Install only executable-related files
# ------------------------------------------------------------

echo "[7/7] Installing OpenVPN..."

make install-exec


# ------------------------------------------------------------
# Verify resulting binary
# ------------------------------------------------------------

echo "============================================================"
echo "Build verification"
echo "============================================================"

if [ ! -x "/usr/local/sbin/openvpn" ]; then
    echo "ERROR: OpenVPN binary was not installed."
    exit 1
fi

echo "Binary:"
ls -lh /usr/local/sbin/openvpn

echo
echo "OpenVPN version:"
/usr/local/sbin/openvpn --version

echo
echo "Linked libraries:"
ldd /usr/local/sbin/openvpn || true


# ------------------------------------------------------------
# Cleanup source
# ------------------------------------------------------------

cd /

rm -rf \
    "/tmp/${OPENVPN_ARCHIVE}" \
    "/tmp/openvpn-${OPENVPN_VERSION}"


# ------------------------------------------------------------
# Remove build-only dependencies
# ------------------------------------------------------------

echo
echo "Removing build dependencies..."

apk del \
    autoconf \
    automake \
    build-base \
    ca-certificates \
    libtool \
    linux-headers \
    pkgconfig \
    openssl-dev \
    lzo-dev \
    libcap-ng-dev \
    tar


# ------------------------------------------------------------
# Final runtime verification
# ------------------------------------------------------------

echo
echo "============================================================"
echo "Final OpenVPN binary"
echo "============================================================"

/usr/local/sbin/openvpn --version

echo
echo "Architecture:"
file /usr/local/sbin/openvpn 2>/dev/null || true

echo
echo "============================================================"
echo "OpenVPN build completed successfully"
echo "Version:       ${OPENVPN_VERSION}"
echo "Architecture:  ${ARCH}"
echo "============================================================"
```
