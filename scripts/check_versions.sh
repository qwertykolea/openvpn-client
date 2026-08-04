#!/bin/bash
set -e

CURRENT_FILE="current_versions"

# Читаем текущие версии из файла
if [ -f "$CURRENT_FILE" ]; then
  source "$CURRENT_FILE"
else
  echo "❌ current_versions not found"
  exit 1
fi

echo "🔍 Current versions:"
echo "  Alpine  : $current_alpine_version"
echo "  OpenVPN : $current_openvpn_version"
echo "  iptables: $current_iptables_version"

# 1) Получаем последнюю стабильную версию Alpine
echo "🌐 Fetching latest stable Alpine..."
LATEST_ALPINE=$(curl -s https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/latest-releases.yaml | grep 'version:' | head -1 | awk '{print $2}')
if [ -z "$LATEST_ALPINE" ]; then
  echo "❌ Failed to get Alpine version"
  exit 1
fi
echo "  Latest Alpine: $LATEST_ALPINE"

# 2) Получаем версии пакетов openvpn и iptables для этой Alpine (через временный контейнер)
echo "🐳 Fetching package versions for Alpine $LATEST_ALPINE..."
OPENVPN_VERSION=$(docker run --rm alpine:"$LATEST_ALPINE" apk info -v openvpn 2>/dev/null | grep 'openvpn-' | head -1 | sed 's/openvpn-//' | awk '{print $1}')
IPTABLES_VERSION=$(docker run --rm alpine:"$LATEST_ALPINE" apk info -v iptables 2>/dev/null | grep 'iptables-' | head -1 | sed 's/iptables-//' | awk '{print $1}')

if [ -z "$OPENVPN_VERSION" ] || [ -z "$IPTABLES_VERSION" ]; then
  echo "❌ Failed to get package versions"
  exit 1
fi
echo "  OpenVPN : $OPENVPN_VERSION"
echo "  iptables: $IPTABLES_VERSION"

# 3) Сравниваем с текущими
SHOULD_BUILD=false
if [ "$current_alpine_version" != "$LATEST_ALPINE" ] || \
   [ "$current_openvpn_version" != "$OPENVPN_VERSION" ] || \
   [ "$current_iptables_version" != "$IPTABLES_VERSION" ]; then
  SHOULD_BUILD=true
fi

# 4) Вывод переменных для GitHub Actions (через GITHUB_OUTPUT)
echo "should_build=$SHOULD_BUILD" >> $GITHUB_OUTPUT
echo "alpine_version=$LATEST_ALPINE" >> $GITHUB_OUTPUT
echo "openvpn_version=$OPENVPN_VERSION" >> $GITHUB_OUTPUT
echo "iptables_version=$IPTABLES_VERSION" >> $GITHUB_OUTPUT

if [ "$SHOULD_BUILD" = true ]; then
  echo "✅ New versions detected – build will proceed."
else
  echo "⏭️ No changes – build skipped."
fi
