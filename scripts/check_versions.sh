#!/bin/bash
set -e

CURRENT_FILE="current_versions"
if [ -f "$CURRENT_FILE" ]; then
  source "$CURRENT_FILE"
else
  echo "❌ current_versions not found" >&2
  exit 1
fi

# Все информационные сообщения направляем в stderr, чтобы они не попадали в stdout
echo "🔍 Current versions:" >&2
echo "  Alpine  : $current_alpine_version" >&2
echo "  OpenVPN : $current_openvpn_version" >&2
echo "  iptables: $current_iptables_version" >&2

# Функция получения версий пакетов для заданной Alpine (возвращает две строки: openvpn iptables)
get_package_versions() {
  local alpine_ver=$1
  echo "🐳 Fetching package versions for Alpine $alpine_ver..." >&2
  if ! docker pull "alpine:$alpine_ver" > /dev/null 2>&1; then
    echo "⚠️  Image alpine:$alpine_ver not found" >&2
    return 1
  fi
  local output
  output=$(docker run --rm "alpine:$alpine_ver" sh -c "apk list openvpn iptables 2>/dev/null")
  if [ -z "$output" ]; then
    echo "⚠️  No packages found with 'apk list'" >&2
    return 1
  fi
  local openvpn_ver=$(echo "$output" | grep '^openvpn-' | head -1 | sed -n 's/^openvpn-\([0-9.]*\)-.*/\1/p')
  local iptables_ver=$(echo "$output" | grep '^iptables-' | head -1 | sed -n 's/^iptables-\([0-9.]*\)-.*/\1/p')
  if [ -z "$openvpn_ver" ] || [ -z "$iptables_ver" ]; then
    echo "⚠️  Could not parse versions from output:" >&2
    echo "$output" >&2
    return 1
  fi
  # Проверяем, что версии состоят только из цифр и точек
  if [[ ! "$openvpn_ver" =~ ^[0-9.]+$ ]] || [[ ! "$iptables_ver" =~ ^[0-9.]+$ ]]; then
    echo "⚠️  Invalid version format: openvpn='$openvpn_ver', iptables='$iptables_ver'" >&2
    return 1
  fi
  echo "$openvpn_ver $iptables_ver"
  return 0
}

# 1) Получаем последнюю стабильную версию Alpine
echo "🌐 Fetching latest stable Alpine..." >&2
LATEST_ALPINE=$(curl -s https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/latest-releases.yaml | grep 'version:' | head -1 | awk '{print $2}')
if [ -z "$LATEST_ALPINE" ]; then
  echo "❌ Failed to get Alpine version" >&2
  echo "should_build=false" >> $GITHUB_OUTPUT
  exit 0
fi
echo "  Latest Alpine: $LATEST_ALPINE" >&2

# Пытаемся получить версии для последней Alpine
if ! read -r OPENVPN_VERSION IPTABLES_VERSION <<< $(get_package_versions "$LATEST_ALPINE"); then
  echo "⚠️  Failed for $LATEST_ALPINE, trying fallback to major version (without patch)..." >&2
  FALLBACK_MAJOR=$(echo "$LATEST_ALPINE" | cut -d. -f1,2)
  if [ "$FALLBACK_MAJOR" != "$LATEST_ALPINE" ]; then
    if read -r OPENVPN_VERSION IPTABLES_VERSION <<< $(get_package_versions "$FALLBACK_MAJOR"); then
      LATEST_ALPINE="$FALLBACK_MAJOR"
      echo "  ✅ Using fallback Alpine version: $LATEST_ALPINE" >&2
    else
      echo "❌ Fallback also failed. No build will be triggered." >&2
      echo "should_build=false" >> $GITHUB_OUTPUT
      exit 0
    fi
  else
    echo "❌ No fallback version available. Skipping build." >&2
    echo "should_build=false" >> $GITHUB_OUTPUT
    exit 0
  fi
fi

# Проверяем, что переменные не пустые (дополнительная страховка)
if [ -z "$OPENVPN_VERSION" ] || [ -z "$IPTABLES_VERSION" ]; then
  echo "❌ Empty version variables after all attempts." >&2
  echo "should_build=false" >> $GITHUB_OUTPUT
  exit 0
fi

echo "  OpenVPN : $OPENVPN_VERSION" >&2
echo "  iptables: $IPTABLES_VERSION" >&2

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
  echo "✅ New versions detected – build will proceed." >&2
else
  echo "⏭️ No changes – build skipped." >&2
fi
