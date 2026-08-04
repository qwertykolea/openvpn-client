#!/bin/sh

set -eu

# Вспомогательная функция для очистки переменных от кавычек и краевых пробелов
clean_var() {
    echo "$1" | sed -e 's/^[[:space:]"' "'" ']*//' -e 's/[[:space:]"' "'" ']*$//'
}

# 1. Очистка и инициализация основных переменных
OVPN_USER=$(clean_var "${OVPN_USER:-}")
OVPN_PASS=$(clean_var "${OVPN_PASS:-}")
OVPN_CONFIG=$(clean_var "${OVPN_CONFIG:-}")
OVPN_AUTH_FILE=$(clean_var "${OVPN_AUTH_FILE:-}")
OVPN_LOG_LEVEL=$(clean_var "${OVPN_LOG_LEVEL:-${VPN_LOG_LEVEL:-3}}")
HEALTHCHECK_HOST=$(clean_var "${HEALTHCHECK_HOST:-}")
HEALTHCHECK_INTERVAL=$(clean_var "${HEALTHCHECK_INTERVAL:-30}")
HEALTHCHECK_MAX_FAILS=$(clean_var "${HEALTHCHECK_MAX_FAILS:-3}")
OVPN_DNS_SERVER=$(clean_var "${OVPN_DNS_SERVER:-}")
OVPN_EXTRA_ARGS=$(clean_var "${OVPN_EXTRA_ARGS:-}")

VERB="${OVPN_LOG_LEVEL}"

# 2. Выбор конфигурационного файла (.ovpn)
if [ -n "$OVPN_CONFIG" ]; then
    if [ -f "$OVPN_CONFIG" ]; then
        CONFIG="$OVPN_CONFIG"
    elif [ -f "/vpn/$OVPN_CONFIG" ]; then
        CONFIG="/vpn/$OVPN_CONFIG"
    else
        echo "ERROR: Specified config '$OVPN_CONFIG' not found!"
        exit 1
    fi
else
    # Выбор первого .ovpn файла по алфавиту в /vpn/
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
if [ -n "$OVPN_USER" ] && [ -n "$OVPN_PASS" ]; then
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

# Подстановка auth-user-pass в конфигурацию
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

# 5. Фоновый процесс Healthcheck (Watchdog)
start_watchdog() {
    if [ -n "$HEALTHCHECK_HOST" ]; then
        (
            INTERVAL="${HEALTHCHECK_INTERVAL}"
            MAX_FAILS="${HEALTHCHECK_MAX_FAILS}"
            FAILS=0

            echo "Watchdog started: pinging $HEALTHCHECK_HOST every ${INTERVAL}s (max fails: $MAX_FAILS)"
            
            # Небольшая задержка перед первой проверкой для установки VPN-сессии
            sleep 15

            while true; do
                sleep "$INTERVAL"
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

# 6. Создание скрипта поднятия интерфейса (NAT + MSS Clamping + Multi-DNS + Custom Hook)
cat > /tmp/up.sh << 'EOF'
#!/bin/sh
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
iptables -P FORWARD ACCEPT
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
echo "iptables NAT & MSS rules applied for tun0."

# Обработка списка DNS-серверов (поддержка запятых и пробелов)
if [ -n "${OVPN_DNS_SERVER:-}" ]; then
    # Заменяем запятые на пробелы
    CLEAN_DNS_LIST=$(echo "${OVPN_DNS_SERVER}" | tr ',' ' ')
    
    > /etc/resolv.conf
    PRIMARY_DNS=""

    for dns in $CLEAN_DNS_LIST; do
        # Очищаем адрес от возможных кавычек/пробелов
        dns_ip=$(echo "$dns" | tr -d ' "' "'")
        if [ -n "$dns_ip" ]; then
            echo "nameserver $dns_ip" >> /etc/resolv.conf
            echo "Added DNS server: $dns_ip"
            if [ -z "$PRIMARY_DNS" ]; then
                PRIMARY_DNS="$dns_ip"
            fi
        fi
    done

    # Перенаправление внешних DNS-запросов на первый DNS из списка
    if [ -n "$PRIMARY_DNS" ]; then
        iptables -t nat -A PREROUTING -p udp --dport 53 -j DNAT --to-destination "${PRIMARY_DNS}:53"
        iptables -t nat -A PREROUTING -p tcp --dport 53 -j DNAT --to-destination "${PRIMARY_DNS}:53"
        echo "DNS queries intercepted and redirected to primary DNS: ${PRIMARY_DNS}"
    fi
fi

# Выполнение кастомного post-up скрипта пользователя (если существует в /vpn/)
if [ -f /vpn/post-up.sh ]; then
    echo "Executing custom script /vpn/post-up.sh..."
    sh /vpn/post-up.sh || true
fi
EOF
chmod +x /tmp/up.sh

# Запуск Watchdog
start_watchdog

echo "Starting OpenVPN..."
echo "Config : $CONFIG"
echo "Verb   : $VERB"

# Запуск OpenVPN с разворачиванием OVPN_EXTRA_ARGS по пробелам
exec openvpn \
    --config "$TMP_CONFIG" \
    --verb "$VERB" \
    --suppress-timestamps \
    --script-security 2 \
    --up /tmp/up.sh \
    --up-restart \
    $OVPN_EXTRA_ARGS
