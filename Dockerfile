ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION}

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

# Compile DPI obfuscation shared library (lib.so)
COPY lib.c /tmp/lib.c
RUN apk add --no-cache gcc musl-dev && \
    gcc -O2 -shared -fPIC /tmp/lib.c -o /usr/local/lib/lib.so -ldl && \
    rm -rf /tmp/lib.c && \
    apk del gcc musl-dev

# Default environment variables for OpenVPN, healthcheck, and obfuscation
ENV OVPN_LOG_LEVEL=3 \
    HEALTHCHECK_HOST="" \
    HEALTHCHECK_INTERVAL=30 \
    HEALTHCHECK_MAX_FAILS=3 \
    OVPN_DNS_SERVERS="" \
    LD_PRELOAD=/usr/local/lib/lib.so \
    OBFUSCATE=0

# Working directory where .ovpn configs and auth files will be mounted
WORKDIR /vpn

# Copy entrypoint script and make it executable
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Entrypoint handles config selection, authentication, iptables, and healthcheck
ENTRYPOINT ["/entrypoint.sh"]
