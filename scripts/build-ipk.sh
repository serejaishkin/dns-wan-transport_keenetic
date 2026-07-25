#!/bin/bash
set -e

# Usage:
# ./scripts/build-ipk.sh <arch> <version> <binary> <output_ipk>

ARCH="${1:-mipsel}"
VERSION="${2:-0.1.0}"
BINARY="${3:-dns-wan-transport}"
OUTPUT="${4:-dns-wan-transport_${VERSION}_${ARCH}.ipk}"

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found: $BINARY"
    exit 1
fi

PROJECT_DIR="$(pwd)"
WORKDIR="$(mktemp -d)"
trap "rm -rf \"$WORKDIR\"" EXIT

mkdir -p "$WORKDIR/data/opt/sbin"
mkdir -p "$WORKDIR/data/opt/etc/dns-wan-transport"
mkdir -p "$WORKDIR/data/opt/etc/init.d"
mkdir -p "$WORKDIR/data/opt/etc/ndm/wan.d"
mkdir -p "$WORKDIR/data/opt/share/dns-wan-transport/web"
mkdir -p "$WORKDIR/control"

cp "$BINARY" "$WORKDIR/data/opt/sbin/dns-wan-transport"
chmod 755 "$WORKDIR/data/opt/sbin/dns-wan-transport"

cp config.json.example "$WORKDIR/data/opt/etc/dns-wan-transport/config.json"
cp entware/S99dns-wan-transport "$WORKDIR/data/opt/etc/init.d/"
cp entware/010-dns-wan-transport.sh "$WORKDIR/data/opt/etc/ndm/wan.d/"
cp web/index.html "$WORKDIR/data/opt/share/dns-wan-transport/web/"

cat > "$WORKDIR/control/control" <<CTRL
Package: dns-wan-transport
Version: $VERSION
Architecture: $ARCH
Maintainer: dns-wan-transport contributors
Section: net
Priority: optional
Description: SOCKS5 WAN bridge for Keenetic DNS failover
CTRL

cat > "$WORKDIR/control/postinst" <<'POST'
#!/bin/sh
/opt/etc/init.d/S99dns-wan-transport enable >/dev/null 2>&1 || true
/opt/etc/init.d/S99dns-wan-transport start >/dev/null 2>&1 || true
exit 0
POST
chmod 755 "$WORKDIR/control/postinst"

cat > "$WORKDIR/control/postrm" <<'POST'
#!/bin/sh
rm -f /opt/var/run/dns-wan-transport.pid
exit 0
POST
chmod 755 "$WORKDIR/control/postrm"

cd "$WORKDIR"

echo "2.0" > debian-binary

tar -czf control.tar.gz -C control .
tar -czf data.tar.gz -C data .

ar r "$PROJECT_DIR/$OUTPUT" \
    debian-binary \
    control.tar.gz \
    data.tar.gz >/dev/null

echo
echo "Created: $PROJECT_DIR/$OUTPUT"

ar t "$PROJECT_DIR/$OUTPUT"

ls -lh "$PROJECT_DIR/$OUTPUT"
