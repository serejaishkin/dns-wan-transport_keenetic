#!/bin/bash
set -e
VERSION=${1:-0.1.1}
ARCH=${2:-mipsel}
BIN=${3:-dns-wan-transport}
PKG=dns-wan-transport_${VERSION}_${ARCH}
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
mkdir -p $TMP/$PKG/opt/sbin
mkdir -p $TMP/$PKG/opt/etc/dns-wan-transport
mkdir -p $TMP/$PKG/opt/etc/init.d
mkdir -p $TMP/$PKG/CONTROL
if [ ! -f "$BIN" ]; then echo "ERROR: binary $BIN not found!"; ls -la; exit 1; fi
cp "$BIN" $TMP/$PKG/opt/sbin/dns-wan-transport
cp config.json.example $TMP/$PKG/opt/etc/dns-wan-transport/config.json
cp entware/S99dns-wan-transport $TMP/$PKG/opt/etc/init.d/
cat > $TMP/$PKG/CONTROL/control << EOFC
Package: dns-wan-transport
Version: $VERSION
Architecture: $ARCH
Maintainer: serejaishkin
Description: SOCKS5 WAN bridge for Keenetic with DNS health check
EOFC
cat > $TMP/$PKG/CONTROL/postinst << EOF
#!/bin/sh
chmod +x /opt/etc/init.d/S99dns-wan-transport
EOF
chmod +x $TMP/$PKG/CONTROL/postinst
cat > $TMP/$PKG/CONTROL/postrm << EOF
#!/bin/sh
rm -rf /opt/etc/dns-wan-transport
EOF
chmod +x $TMP/$PKG/CONTROL/postrm
mkdir -p ipkg
cd $TMP
tar czf $TMP/data.tar.gz -C $PKG/opt .
tar czf $TMP/control.tar.gz -C $PKG/CONTROL .
echo "2.0" > $TMP/debian-binary
ar r $OLDPWD/ipkg/${PKG}.ipk $TMP/control.tar.gz $TMP/data.tar.gz $TMP/debian-binary
echo "Built: ipkg/${PKG}.ipk"
ls -la $OLDPWD/ipkg/
