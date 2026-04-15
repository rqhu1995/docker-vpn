FROM alpine:3.23

RUN apk add --no-cache \
        openconnect \
        expect \
        curl \
        supervisor \
        py3-pip \
    && pip install --break-system-packages --no-cache-dir pproxy

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
