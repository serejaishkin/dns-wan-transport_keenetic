#!/bin/sh
[ "$1" = "up" ] || exit 0
/opt/etc/init.d/S99dns-wan-transport restart 2>/dev/null
