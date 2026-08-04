FROM alpine:latest

# Установка OpenVPN, iptables и сетевых утилит
RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
    openvpn \
    iptables && \
    rm -rf /var/cache/apk

ENV OVPN_LOG_LEVEL=3

WORKDIR /vpn

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
