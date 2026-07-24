#!/bin/bash
set -e

# Usage: ./scripts/build-ipk.sh <arch> <version> <binary> <output_ipk>
# Example: ./scripts/build-ipk.sh mipsel 0.1.0 dns-wan-transport-mipsel dns-wan-transport_0.1.0_mipsel.ipk

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

# Create data directory structure
mkdir -p "$WORKDIR/data/opt/sbin"
mkdir -p "$WORKDIR/data/opt/etc/dns-wan-transport"
mkdir -p "$WORKDIR/data/opt/etc/init.d"
mkdir -p "$WORKDIR/data/opt/etc/ndm/wan.d"
mkdir -p "$WORKDIR/data/opt/share/dns-wan-transport/web"
mkdir -p "$WORKDIR/data/opt/var/run"

# Copy files
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

# Create control file
mkdir -p "$WORKDIR/control"
cat > "$WORKDIR/control/control" <<EOF
Package: dns-wan-transport
Version: $VERSION
Architecture: $ARCH
Maintainer: dns-wan-transport contributors
Source: https://github.com/keenetic/dns-wan-transport
Description: SOCKS5 WAN bridge for Keenetic DNS failover. Turns local DNS into a native Keenetic WAN connection with automatic failover.
Section: net
Priority: optional
EOF

# Create postinst script
cat > "$WORKDIR/control/postinst" <<'EOF'
#!/bin/sh
# Enable autostart
/opt/etc/init.d/S99dns-wan-transport enable 2>/dev/null || true
# Start if not running
/opt/etc/init.d/S99dns-wan-transport start 2>/dev/null || true
EOF
chmod 755 "$WORKDIR/control/postinst"

# Create postrm script
cat > "$WORKDIR/control/postrm" <<'EOF'
#!/bin/sh
rm -f /opt/var/run/dns-wan-transport.pid
EOF
chmod 755 "$WORKDIR/control/postrm"

# Create debian-binary
echo "2.0" > "$WORKDIR/debian-binary"

# Package
cd "$WORKDIR"
tar -czf control.tar.gz -C control .
tar -czf data.tar.gz -C data .

# Build .ipk (ar archive for OpenWrt/Entware)
# Note: Entware uses standard tar.gz ipk, not ar
# We create a tar.gz with control.tar.gz, data.tar.gz, debian-binary inside
tar -czf "$OUTPUT" debian-binary control.tar.gz data.tar.gz

echo "Created: $OUTPUT"
ls -la "$OUTPUT"
