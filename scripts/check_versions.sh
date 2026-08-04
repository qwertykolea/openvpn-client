#!/bin/bash
set -e

CURRENT_FILE="current_versions"
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

# 2) Проверяем, существует ли образ в Docker Hub (и загружаем его, чтобы избежать ошибок)
echo "🐳 Checking if alpine:$LATEST_ALPINE exists..."
if ! docker pull "alpine:$LATEST_ALPINE" > /dev/null 2>&1; then
  echo "⚠️  Image alpine:$LATEST_ALPINE not found, trying fallback to latest minor version..."
  # Пробуем взять без последней цифры (например, 3.24 вместо 3.24.1)
  FALLBACK_VERSION=$(echo "$LATEST_ALPINE" | cut -d. -f1,2)
  if docker pull "alpine:$FALLBACK_VERSION" > /dev/null 2>&1; then
    LATEST_ALPINE="$FALLBACK_VERSION"
    echo "  Using fallback: $LATEST_ALPINE"
  else
    echo "❌ No working Alpine image found"
    exit 1
  fi
fi

# 3) Получаем версии пакетов (используем более стабильный формат вывода)
echo "🐳 Fetching package versions for Alpine $LATEST_ALPINE..."

# Запускаем контейнер и выполняем apk list, затем парсим версии
OUTPUT=$(docker run --rm "alpine:$LATEST_ALPINE" sh -c "apk list -I openvpn iptables 2>/dev/null | sed -n 's/^openvpn-\([0-9.]*\)-.*/\1/p; s/^iptables-\([0-9.]*\)-.*/\1/p'")
# Ожидаем две строки: сначала openvpn, потом iptables
OPENVPN_VERSION=$(echo "$OUTPUT" | head -1)
IPTABLES_VERSION=$(echo "$OUTPUT" | tail -1)

if [ -z "$OPENVPN_VERSION" ] || [ -z "$IPTABLES_VERSION" ]; then
  echo "❌ Failed to get package versions"
  echo "  Output was:"
  echo "$OUTPUT"
  exit 1
fi

echo "  OpenVPN : $OPENVPN_VERSION"
echo "  iptables: $IPTABLES_VERSION"

# 4) Сравниваем с текущими
SHOULD_BUILD=false
if [ "$current_alpine_version" != "$LATEST_ALPINE" ] || \
   [ "$current_openvpn_version" != "$OPENVPN_VERSION" ] || \
   [ "$current_iptables_version" != "$IPTABLES_VERSION" ]; then
  SHOULD_BUILD=true
fi

# 5) Вывод переменных для GitHub Actions
echo "should_build=$SHOULD_BUILD" >> $GITHUB_OUTPUT
echo "alpine_version=$LATEST_ALPINE" >> $GITHUB_OUTPUT
echo "openvpn_version=$OPENVPN_VERSION" >> $GITHUB_OUTPUT
echo "iptables_version=$IPTABLES_VERSION" >> $GITHUB_OUTPUT

if [ "$SHOULD_BUILD" = true ]; then
  echo "✅ New versions detected – build will proceed."
else
  echo "⏭️ No changes – build skipped."
fi
