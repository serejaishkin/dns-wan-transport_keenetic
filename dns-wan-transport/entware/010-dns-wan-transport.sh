#!/bin/sh
# WAN hook for dns-wan-transport
# Place in /opt/etc/ndm/wan.d/

[ "$1" = "up" ] || exit 0

# Restart dns-wan-transport when WAN comes up to ensure fresh state
/opt/etc/init.d/S99dns-wan-transport restart 2>/dev/null
