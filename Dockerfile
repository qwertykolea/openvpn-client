ARG ALPINE_VERSION
ARG OPENVPN_VERSION
ARG IPTABLES_VERSION

FROM alpine:${ALPINE_VERSION}

# Установка OpenVPN, iptables и сетевых утилит
RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
    openvpn=${OPENVPN_VERSION} \
    iptables=${IPTABLES_VERSION} && \
    rm -rf /var/cache/apk


ENV VPN_LOG_LEVEL=7

WORKDIR /vpn

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
