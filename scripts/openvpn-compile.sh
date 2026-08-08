#!/bin/sh
set -e

# OPENVPN_VERSION приходит из CI (например, "v2.6.12")
# Убираем префикс 'v', чтобы получить "2.6.12" для имени файла
CLEAN_VERSION="${OPENVPN_VERSION#v}"

# Устанавливаем зависимости для сборки.
# ВНИМАНИЕ: git, autoconf и automake БОЛЬШЕ НЕ НУЖНЫ!
apk add --no-cache lzo libcap-ng openssl lz4-libs

apk add --no-cache --virtual .openvpn-builddeps \
  build-base libtool linux-headers pkgconfig \
  libcap-ng-dev lz4-dev linux-pam-dev openssl-dev lzo-dev curl

# Скачиваем и распаковываем официальный tarball
# CDN swupdate.openvpn.org хранит уже подготовленные релизы со скриптом configure
echo "Downloading OpenVPN ${CLEAN_VERSION} tarball..."
curl -fSL "https://github.com/OpenVPN/openvpn/releases/download/v${CLEAN_VERSION}/openvpn-${CLEAN_VERSION}.tar.gz" | tar xz


cd "openvpn-${CLEAN_VERSION}"

# autoreconf НЕ НУЖЕН! Сразу запускаем configure
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
ARCH=$(uname -m)
OS=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
OS_V=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
DATE=$(date -u '+%d %b %Y %H:%M UTC')
REPO="https://github.com/qwertykolea/openvpn-client"

sed -i "s@#define TARGET_ALIAS .*@#define TARGET_ALIAS \"${ARCH}-${OS}-linux-v${OS_V}-musl built on ${DATE} | ${REPO} |\"@" config.h
# -----------------------------

# Безопасный подсчет ядер для make (в Alpine нет nproc по умолчанию)
# Для QEMU arm/v6 лучше не ставить больше 2, иначе может быть OOM (Out of Memory)
JOBS=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 2)
if [ "$ARCH" = "armv6l" ] || [ "$ARCH" = "armv7l" ]; then
  JOBS=2 # Ограничиваем для ARM под QEMU
fi

make -j"$JOBS"

# Install only executables
make install-exec

# Clean up source to save space
cd ..
rm -rf "openvpn-${CLEAN_VERSION}"

# Remove build-only dependencies
apk del .openvpn-builddeps

echo "bump"
