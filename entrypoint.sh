#!/bin/sh

set -eu

# 1. Уровень логирования
VERB="${OVPN_LOG_LEVEL:-${VPN_LOG_LEVEL:-3}}"

# 2. Выбор конфигурационного файла (.ovpn)
if [ -n "${OVPN_CONFIG:-}" ]; then
    if [ -f "$OVPN_CONFIG" ]; then
        CONFIG="$OVPN_CONFIG"
    elif [ -f "/vpn/$OVPN_CONFIG" ]; then
        CONFIG="/vpn/$OVPN_CONFIG"
    else
        echo "ERROR: Specified config '$OVPN_CONFIG' not found!"
        exit 1
    fi
else
    # Выбор первого файла по алфавиту в /vpn/
    CONFIG=$(ls -1 /vpn/*.ovpn 2>/dev/null | sort | head -n 1 || true)
    if [ -z "$CONFIG" ]; then
        echo "ERROR: No .ovpn config files found in /vpn!"
        exit 1
    fi
fi

echo "Selected config: $CONFIG"

TMP_CONFIG="/tmp/config.ovpn"
cp "$CONFIG" "$TMP_CONFIG"

# 3. Настройка авторизации (Приоритет: Переменные > Файл)
AUTH_FILE=""
if [ -n "${OVPN_USER:-}" ] && [ -n "${OVPN_PASS:-}" ]; then
    AUTH_FILE="/tmp/auth_env.txt"
    printf "%s\n%s\n" "$OVPN_USER" "$OVPN_PASS" > "$AUTH_FILE"
    chmod 600 "$AUTH_FILE"
    echo "Using credentials from environment variables (OVPN_USER / OVPN_PASS)."
else
    DEFAULT_AUTH_FILE="${OVPN_AUTH_FILE:-/vpn/auth.txt}"
    if [ -f "$DEFAULT_AUTH_FILE" ]; then
        AUTH_FILE="$DEFAULT_AUTH_FILE"
        echo "Using credentials from file: $AUTH_FILE"
    fi
fi

# Подстановка auth-user-pass
if [ -n "$AUTH_FILE" ]; then
    if grep -Eq '^[[:space:]]*auth-user-pass([[:space:]]+.*)?$' "$TMP_CONFIG"; then
        sed -i -E "s|^[[:space:]]*auth-user-pass.*|auth-user-pass $AUTH_FILE|" "$TMP_CONFIG"
    else
        echo "auth-user-pass $AUTH_FILE" >> "$TMP_CONFIG"
    fi
fi

# 4. Проверка и автоматическое создание TUN-устройства
if [ ! -c /dev/net/tun ]; then
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200
    chmod 600 /dev/net/tun
fi

# 5. Фоновый процес Healthcheck (Watchdog)
start_watchdog() {
    if [ -n "${HEALTHCHECK_HOST:-}" ]; then
        (
            INTERVAL="${HEALTHCHECK_INTERVAL:-30}"
            MAX_FAILS="${HEALTHCHECK_MAX_FAILS:-3}"
            FAILS=0

            echo "Watchdog started: pinging $HEALTHCHECK_HOST every ${INTERVAL}s (max fails: $MAX_FAILS)"
            
            # Небольшая задержка перед первой проверкой на время установки VPN-сессии
            sleep 15

            while true; do
                sleep "$INTERVAL"
                # Проверка ping строго через интерфейс tun0
                if ping -I tun0 -c 1 -W 3 "$HEALTHCHECK_HOST" >/dev/null 2>&1; then
                    FAILS=0
                else
                    FAILS=$((FAILS + 1))
                    echo "WARNING: Healthcheck failed ($FAILS/$MAX_FAILS) for host $HEALTHCHECK_HOST"
                    if [ "$FAILS" -ge "$MAX_FAILS" ]; then
                        echo "CRITICAL: VPN tunnel dead. Killing container for restart..."
                        pkill -9 openvpn || true
                        exit 1
                    fi
                fi
            done
        ) &
    fi
}

# 6. Создание скрипта поднятия интерфейса (NAT + MSS Clamping + DNS)
cat > /tmp/up.sh << EOF
#!/bin/sh
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
iptables -P FORWARD ACCEPT
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
echo "iptables NAT & MSS rules applied for tun0."

# Настройка и перехват DNS при указании OVPN_DNS_SERVER
if [ -n "${OVPN_DNS_SERVER:-}" ]; then
    echo "nameserver ${OVPN_DNS_SERVER}" > /etc/resolv.conf
    iptables -t nat -A PREROUTING -p udp --dport 53 -j DNAT --to-destination ${OVPN_DNS_SERVER}:53
    iptables -t nat -A PREROUTING -p tcp --dport 53 -j DNAT --to-destination ${OVPN_DNS_SERVER}:53
    echo "DNS redirected to ${OVPN_DNS_SERVER} via iptables DNAT."
fi
EOF
chmod +x /tmp/up.sh

# Запуск Watchdog
start_watchdog

echo "Starting OpenVPN..."
echo "Config : $CONFIG"
echo "Verb   : $VERB"

exec openvpn \
    --config "$TMP_CONFIG" \
    --verb "$VERB" \
    --suppress-timestamps \
    --script-security 2 \
    --up /tmp/up.sh \
    --up-restart \
    ${OVPN_EXTRA_ARGS:-}
