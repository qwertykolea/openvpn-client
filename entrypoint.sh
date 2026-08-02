#!/bin/bash
set -e

# Создаем устройство TUN, если его нет в контейнере
if [ ! -c /dev/net/tun ]; then
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200
    chmod 600 /dev/net/tun
fi

# Выставляем правильные права на файлы сертификатов
chmod 600 /vpn/* 2>/dev/null || true

# Включаем IP Forwarding
sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1 || true

# Настраиваем NAT
iptables -t nat -A POSTROUTING -o tun+ -j MASQUERADE
iptables -A FORWARD -i tun+ -j ACCEPT
iptables -A FORWARD -o tun+ -j ACCEPT

# Обработка учетных данных
if [ -n "$VPN_USER" ] && [ -n "$VPN_PASS" ]; then
    echo "[+] Creating auto-auth credentials file..."
    printf '%s\n' "$VPN_USER" > /tmp/credentials.txt
    printf '%s\n' "$VPN_PASS" >> /tmp/credentials.txt
    chmod 600 /tmp/credentials.txt
    AUTH_ARGS="--auth-user-pass /tmp/credentials.txt"
else
    AUTH_ARGS=""
fi

if [ -f "/vpn/config.ovpn" ]; then
    echo "[+] Starting OpenVPN with /vpn/config.ovpn..."
    exec openvpn --config /vpn/config.ovpn --cd /vpn $AUTH_ARGS
else
    echo "[-] Error: /vpn/config.ovpn not found!"
    exit 1
fi
