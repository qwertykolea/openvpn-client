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

# Функция получения версий пакетов для заданной Alpine
get_package_versions() {
  local alpine_ver=$1
  echo "🐳 Fetching package versions for Alpine $alpine_ver..."
  if ! docker pull "alpine:$alpine_ver" > /dev/null 2>&1; then
    echo "⚠️  Image alpine:$alpine_ver not found"
    return 1
  fi
  local output
  output=$(docker run --rm "alpine:$alpine_ver" sh -c "apk list openvpn iptables 2>/dev/null")
  if [ -z "$output" ]; then
    echo "⚠️  No packages found with 'apk list'"
    return 1
  fi
  local openvpn_ver=$(echo "$output" | grep '^openvpn-' | head -1 | sed -n 's/^openvpn-\([0-9.]*\)-.*/\1/p')
  local iptables_ver=$(echo "$output" | grep '^iptables-' | head -1 | sed -n 's/^iptables-\([0-9.]*\)-.*/\1/p')
  if [ -z "$openvpn_ver" ] || [ -z "$iptables_ver" ]; then
    echo "⚠️  Could not parse versions from output:"
    echo "$output"
    return 1
  fi
  echo "$openvpn_ver $iptables_ver"
  return 0
}

# Пытаемся получить версии для последней Alpine
if ! read -r OPENVPN_VERSION IPTABLES_VERSION <<< $(get_package_versions "$LATEST_ALPINE"); then
  echo "⚠️  Failed for $LATEST_ALPINE, trying fallback to major version (without patch)..."
  FALLBACK_MAJOR=$(echo "$LATEST_ALPINE" | cut -d. -f1,2)
  if [ "$FALLBACK_MAJOR" != "$LATEST_ALPINE" ]; then
    if read -r OPENVPN_VERSION IPTABLES_VERSION <<< $(get_package_versions "$FALLBACK_MAJOR"); then
      LATEST_ALPINE="$FALLBACK_MAJOR"
      echo "  ✅ Using fallback Alpine version: $LATEST_ALPINE"
    else
      echo "❌ Fallback also failed. No build will be triggered."
      # Выходим без ошибки, но помечаем, что сборка не нужна
      echo "should_build=false" >> $GITHUB_OUTPUT
      exit 0
    fi
  else
    echo "❌ No fallback version available. Skipping build."
    echo "should_build=false" >> $GITHUB_OUTPUT
    exit 0
  fi
fi

echo "  OpenVPN : $OPENVPN_VERSION"
echo "  iptables: $IPTABLES_VERSION"

# Сравниваем с текущими версиями
SHOULD_BUILD=false
if [ "$current_alpine_version" != "$LATEST_ALPINE" ] || \
   [ "$current_openvpn_version" != "$OPENVPN_VERSION" ] || \
   [ "$current_iptables_version" != "$IPTABLES_VERSION" ]; then
  SHOULD_BUILD=true
fi

# Записываем в GITHUB_OUTPUT – это единственные данные, которые попадут в переменные
echo "should_build=$SHOULD_BUILD" >> $GITHUB_OUTPUT
echo "alpine_version=$LATEST_ALPINE" >> $GITHUB_OUTPUT
echo "openvpn_version=$OPENVPN_VERSION" >> $GITHUB_OUTPUT
echo "iptables_version=$IPTABLES_VERSION" >> $GITHUB_OUTPUT

if [ "$SHOULD_BUILD" = true ]; then
  echo "✅ New versions detected – build will proceed."
else
  echo "⏭️ No changes – build skipped."
fi
