FROM alpine:latest

RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
    iptables \
    iproute2 \
    iputils && \
    rm -rf /var/cache/apk

COPY scripts/ /scripts/

RUN /scripts/openvpn-compile.sh

ENV OVPN_LOG_LEVEL=3 \
    HEALTHCHECK_HOST="" \
    HEALTHCHECK_INTERVAL=30 \
    HEALTHCHECK_MAX_FAILS=3 \
    OVPN_DNS_SERVER=""

WORKDIR /vpn

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
