FROM alpine:latest

# OpenVPN version is passed as build-arg and set as environment variable
ARG OPENVPN_VERSION
ENV OPENVPN_VERSION=${OPENVPN_VERSION}

# Install runtime dependencies: iptables, iproute2 (for ip), iputils (for ping)
RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
    iptables \
    iproute2 \
    iputils && \
    rm -rf /var/cache/apk

# Copy compilation script into image and execute it
COPY scripts/ /scripts/
RUN chmod +x /scripts/openvpn-compile.sh
RUN /scripts/openvpn-compile.sh

# Default environment variables for OpenVPN and healthcheck
ENV OVPN_LOG_LEVEL=3 \
    HEALTHCHECK_HOST="" \
    HEALTHCHECK_INTERVAL=30 \
    HEALTHCHECK_MAX_FAILS=3 \
    OVPN_DNS_SERVERS=""

# Working directory where .ovpn configs and auth files will be mounted
WORKDIR /vpn

# Copy entrypoint script and make it executable
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Entrypoint handles config selection, authentication, iptables, and healthcheck
ENTRYPOINT ["/entrypoint.sh"]
