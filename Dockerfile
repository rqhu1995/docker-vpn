ARG ALPINE_VERSION=3.23

FROM alpine:${ALPINE_VERSION} AS openconnect-builder

ARG OPENCONNECT_VERSION=9.21
ARG OPENCONNECT_SHA256=5b32369467db6e5f317aa1ed12cfcbb81ed00bdbc765450b6bfcbdc300944a58
# https://www.infradead.org/openconnect/download.html
ARG OPENCONNECT_SIGNING_FINGERPRINT=BE07D9FD54809AB2C4B0FF5F63762CDA67E2F359

WORKDIR /build

RUN apk add --no-cache \
        autoconf \
        automake \
        build-base \
        curl \
        gnupg \
        intltool \
        krb5-dev \
        libproxy-dev \
        libxml2-dev \
        linux-headers \
        lz4-dev \
        oath-toolkit-dev \
        openssl-dev \
        pcsc-lite-dev \
        pkgconf \
        python3-dev \
        stoken-dev

COPY keys/openconnect-release-key.asc /tmp/openconnect-release-key.asc

RUN set -eux; \
    key_fingerprint="$(gpg --batch --show-keys --with-colons /tmp/openconnect-release-key.asc \
        | awk -F: '$1 == "fpr" { print $10; exit }')"; \
    test "$key_fingerprint" = "$OPENCONNECT_SIGNING_FINGERPRINT"; \
    gpg --batch --import /tmp/openconnect-release-key.asc; \
    curl -fsSLO "https://www.infradead.org/openconnect/download/openconnect-${OPENCONNECT_VERSION}.tar.gz"; \
    curl -fsSLO "https://www.infradead.org/openconnect/download/openconnect-${OPENCONNECT_VERSION}.tar.gz.asc"; \
    signature_status="$(gpg --batch --status-fd 1 \
        --verify "openconnect-${OPENCONNECT_VERSION}.tar.gz.asc" \
        "openconnect-${OPENCONNECT_VERSION}.tar.gz" 2>/dev/null)"; \
    echo "$signature_status" \
        | grep -F "[GNUPG:] VALIDSIG ${OPENCONNECT_SIGNING_FINGERPRINT} "; \
    echo "${OPENCONNECT_SHA256}  openconnect-${OPENCONNECT_VERSION}.tar.gz" | sha256sum -c -; \
    tar -xzf "openconnect-${OPENCONNECT_VERSION}.tar.gz"; \
    cd "openconnect-${OPENCONNECT_VERSION}"; \
    ./configure \
        --prefix=/usr \
        --sbindir=/usr/bin \
        --disable-static \
        --disable-rpath \
        --with-openssl \
        --with-stoken \
        --with-vpnc-script=/etc/vpnc/vpnc-script \
        --disable-nls; \
    make -j"$(getconf _NPROCESSORS_ONLN)"; \
    make DESTDIR=/openconnect-root install-exec

FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache \
        curl \
        expect \
        iproute2 \
        krb5-libs \
        libproxy \
        libxml2 \
        lz4-libs \
        oath-toolkit-libpskc \
        openssl \
        pcsc-lite-libs \
        py3-pip \
        stoken \
        supervisor \
        vpnc \
    && pip install --break-system-packages --no-cache-dir pproxy

COPY --from=openconnect-builder /openconnect-root/usr/ /usr/

# Fix "Cannot open /proc/sys/net/ipv4/route/flush: Read-only file system"
# https://serverfault.com/questions/878443/
RUN rm -f /etc/vpnc/vpnc-script \
    && curl -fsSL https://gitlab.com/openconnect/vpnc-scripts/-/raw/master/vpnc-script \
         -o /etc/vpnc/vpnc-script \
    && chmod +x /etc/vpnc/vpnc-script

COPY etc/supervisord.conf /etc/
COPY hku-connect.exp /usr/local/bin/hku-connect
RUN chmod +x /usr/local/bin/hku-connect

ENTRYPOINT ["/usr/local/bin/hku-connect"]
