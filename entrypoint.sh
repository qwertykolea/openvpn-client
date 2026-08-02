#!/bin/bash
set -e

# Включаем IP Forwarding внутри контейнера
sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1 || true

# Настраиваем NAT (MASQUERADE) для трафика из подсети MikroTik через туннель tun0
iptables -t nat -A POSTROUTING -o tun+ -j MASQUERADE
iptables -A FORWARD -i tun+ -j ACCEPT
iptables -A FORWARD -o tun+ -j ACCEPT

# Если переданы логин и пароль через Environment Variables, создаем файл авторизации
if [ -n "$VPN_USER" ] && [ -n "$VPN_PASS" ]; then
    echo "[+] Creating auto-auth credentials file..."
    printf '%s\n' "$VPN_USER" > /tmp/credentials.txt
    printf '%s\n' "$VPN_PASS" >> /tmp/credentials.txt
    chmod 600 /tmp/credentials.txt
    AUTH_ARGS="--auth-user-pass /tmp/credentials.txt"
else
    AUTH_ARGS=""
fi

# Запуск OpenVPN
if [ -f "/vpn/config.ovpn" ]; then
    echo "[+] Starting OpenVPN with /vpn/config.ovpn..."
    exec openvpn --config /vpn/config.ovpn --cd /vpn $AUTH_ARGS
else
    echo "[-] Error: /vpn/config.ovpn not found!"
    exit 1
fi
