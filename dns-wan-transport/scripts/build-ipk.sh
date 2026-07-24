#!/bin/bash
set -e

ARCH="${1:-mipsel}"
VERSION="${2:-0.1.0}"
BINARY="${3:-dns-wan-transport}"
OUTPUT="${4:-dns-wan-transport_${VERSION}_${ARCH}.ipk}"

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found: $BINARY"
    exit 1
fi

WORKDIR=$(mktemp -d)
trap "rm -rf $WORKDIR" EXIT

mkdir -p "$WORKDIR/data/opt/sbin"
mkdir -p "$WORKDIR/data/opt/etc/dns-wan-transport"
mkdir -p "$WORKDIR/data/opt/etc/init.d"
mkdir -p "$WORKDIR/data/opt/etc/ndm/wan.d"
mkdir -p "$WORKDIR/data/opt/share/dns-wan-transport/web"
mkdir -p "$WORKDIR/data/opt/var/run"

cp "$BINARY" "$WORKDIR/data/opt/sbin/dns-wan-transport"
chmod 755 "$WORKDIR/data/opt/sbin/dns-wan-transport"

cp config.json.example "$WORKDIR/data/opt/etc/dns-wan-transport/config.json"
chmod 644 "$WORKDIR/data/opt/etc/dns-wan-transport/config.json"

cp entware/S99dns-wan-transport "$WORKDIR/data/opt/etc/init.d/"
chmod 755 "$WORKDIR/data/opt/etc/init.d/S99dns-wan-transport"

cp entware/010-dns-wan-transport.sh "$WORKDIR/data/opt/etc/ndm/wan.d/"
chmod 755 "$WORKDIR/data/opt/etc/ndm/wan.d/010-dns-wan-transport.sh"

cp web/index.html "$WORKDIR/data/opt/share/dns-wan-transport/web/"
chmod 644 "$WORKDIR/data/opt/share/dns-wan-transport/web/index.html"

mkdir -p "$WORKDIR/control"
cat > "$WORKDIR/control/control" <<EOFC
Package: dns-wan-transport
Version: $VERSION
Architecture: $ARCH
Maintainer: dns-wan-transport contributors
Source: https://github.com/keenetic/dns-wan-transport
Description: SOCKS5 WAN bridge for Keenetic DNS failover
Section: net
Priority: optional
EOFC

cat > "$WORKDIR/control/postinst" <<'EOFP'
#!/bin/sh
/opt/etc/init.d/S99dns-wan-transport enable 2>/dev/null || true
/opt/etc/init.d/S99dns-wan-transport start 2>/dev/null || true
EOFP
chmod 755 "$WORKDIR/control/postinst"

cat > "$WORKDIR/control/postrm" <<'EOFP'
#!/bin/sh
rm -f /opt/var/run/dns-wan-transport.pid
EOFP
chmod 755 "$WORKDIR/control/postrm"

echo "2.0" > "$WORKDIR/debian-binary"

cd "$WORKDIR"
tar -czf control.tar.gz -C control .
tar -czf data.tar.gz -C data .
tar -czf "$OUTPUT" debian-binary control.tar.gz data.tar.gz

echo "Created: $OUTPUT"
ls -la "$OUTPUT"
