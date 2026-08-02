FROM alpine:latest

# Установка OpenVPN, iptables и сетевых утилит
RUN apk add --no-cache \
    openvpn \
    iptables \
    bind-tools \
    iproute2 \
    ca-certificates \
    curl \
    openssl \
    bash


ENV VPN_LOG_LEVEL=7
ENV IPTABLES_RULES=iptables_rules

WORKDIR /vpn

HEALTHCHECK --interval=30s \
            --timeout=5s \
            --start-period=20s \
            --retries=3 \
            CMD /healthcheck.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
