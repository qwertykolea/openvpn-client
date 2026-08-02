#!/usr/bin/env bash
set -e

cleanup() {
    if [[ $openvpn_child ]]; then
        kill SIGTERM "$openvpn_child" 2>/dev/null ||शील
    fi
    sleep 0.5
    echo "info: exiting"
    exit 0
}

trap cleanup SIGTERM SIGINT

# 1. Создаем устройство TUN, если его нет в контейнере (обязательно для MikroTik)
if [ ! -c /dev/net/tun ]; then
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200
    chmod 600 /dev/net/tun
fi

# 2. Выставляем правильные права на файлы сертификатов
chmod 600 /vpn/* 2>/dev/null || true

# 3. Включаем IP Forwarding и настраиваем NAT для туннеля
sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1 || true
iptables -t nat -A POSTROUTING -o tun+ -j MASQUERADE 2>/dev/null || true
iptables -A FORWARD -i tun+ -j ACCEPT 2>/dev/null || true
iptables -A FORWARD -o tun+ -j ACCEPT 2>/dev/null || true

echo " --- Running with the following variables --- "

# Устанавливаем уровень логирования по умолчанию, если не задан
VPN_LOG_LEVEL=${VPN_LOG_LEVEL:-4}

if [[ $VPN_CONFIG_FILE ]]; then
    echo "VPN configuration file: $VPN_CONFIG_FILE"
    config_files="/vpn/$VPN_CONFIG_FILE"
elif [[ $VPN_CONFIG_PATTERN ]]; then
    echo "VPN configuration file name pattern: $VPN_CONFIG_PATTERN"
    config_files=$(find /vpn -name "$VPN_CONFIG_PATTERN" 2> /dev/null)
else
    # По умолчанию ищем в папке /vpn, включая твой config.ovpn
    config_files=$(find /vpn -name '*.conf' -o -name '*.ovpn' 2> /dev/null)
fi

if [[ -z $config_files ]]; then
    >&2 echo 'Error: No openvpn configuration files found.'
    exit 1
fi

# Загрузка кастомных правил iptables, если они указаны и существуют
if [[ $IPTABLES_RULES ]] && [[ -f /vpn/$IPTABLES_RULES ]]; then
    echo "Loading iptables from /vpn/$IPTABLES_RULES"
    iptables-restore /vpn/$IPTABLES_RULES
else
    echo "No custom iptables rules file found."
fi

default_gateway=$(ip -4 route | grep 'default via' | awk '{print $3}')
echo "Default gateway is $default_gateway"

# Обработка учетных данных из переменных окружения
if [ -n "$VPN_USER" ] && [ -n "$VPN_PASS" ]; then
    echo "[+] Creating auto-auth credentials file..."
    printf '%s\n' "$VPN_USER" > /tmp/credentials.txt
    printf '%s\n' "$VPN_PASS" >> /tmp/credentials.txt
    chmod 600 /tmp/credentials.txt
    AUTH_FLAG=1
    AUTH_FILE="/tmp/credentials.txt"
elif [[ $VPN_AUTH_SECRET ]]; then
    AUTH_FLAG=1
    AUTH_FILE="/run/secrets/$VPN_AUTH_SECRET"
else
    AUTH_FLAG=0
fi

for CONFIG_FILE in $config_files
do
    echo "Starting OpenVPN using config file $CONFIG_FILE"
    openvpn_args=(
        "--config" "$CONFIG_FILE"
        "--cd" "/vpn"
        "--auth-nocache"
        "--pull-filter" "ignore" "ifconfig-ipv6"
        "--pull-filter" "ignore" "route-ipv6"
        "--script-security" "2"
        "--up-restart"
        "--verb" "$VPN_LOG_LEVEL"
    )

    # Добавляем параметры авторизации раздельно, если они нужны
    if [ "$AUTH_FLAG" -eq 1 ]; then
        openvpn_args+=("--auth-user-pass" "$AUTH_FILE")
    fi

    openvpn "${openvpn_args[@]}" &
    openvpn_child=$!
done

wait < <(jobs -p)
