.PHONY: all build clean install package

BINARY=dns-wan-transport
VERSION=$(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
LDFLAGS=-ldflags "-s -w -X main.version=$(VERSION)"

all: build

build:
	go build $(LDFLAGS) -o $(BINARY) ./cmd/dns-wan-transport

clean:
	rm -f $(BINARY)

install: build
	install -Dm755 $(BINARY) $(DESTDIR)/opt/sbin/$(BINARY)
	install -Dm644 config.json.example $(DESTDIR)/opt/etc/dns-wan-transport/config.json
	install -Dm755 entware/S99dns-wan-transport $(DESTDIR)/opt/etc/init.d/S99dns-wan-transport
	install -Dm755 entware/010-dns-wan-transport.sh $(DESTDIR)/opt/etc/ndm/wan.d/010-dns-wan-transport.sh
	cp -r web $(DESTDIR)/opt/share/dns-wan-transport/

# Cross-compilation for Entware architectures
mipsel:
	GOOS=linux GOARCH=mipsle GOMIPS=softfloat go build $(LDFLAGS) -o $(BINARY)-mipsel ./cmd/dns-wan-transport

mips:
	GOOS=linux GOARCH=mips GOMIPS=softfloat go build $(LDFLAGS) -o $(BINARY)-mips ./cmd/dns-wan-transport

arm64:
	GOOS=linux GOARCH=arm64 go build $(LDFLAGS) -o $(BINARY)-arm64 ./cmd/dns-wan-transport

armv7:
	GOOS=linux GOARCH=arm GOARM=7 go build $(LDFLAGS) -o $(BINARY)-armv7 ./cmd/dns-wan-transport

x86_64:
	GOOS=linux GOARCH=amd64 go build $(LDFLAGS) -o $(BINARY)-x86_64 ./cmd/dns-wan-transport

package: build
	mkdir -p ipkg/control ipkg/data/opt/sbin ipkg/data/opt/etc/dns-wan-transport ipkg/data/opt/etc/init.d ipkg/data/opt/etc/ndm/wan.d ipkg/data/opt/share/dns-wan-transport
	cp $(BINARY) ipkg/data/opt/sbin/
	cp config.json.example ipkg/data/opt/etc/dns-wan-transport/config.json
	cp entware/S99dns-wan-transport ipkg/data/opt/etc/init.d/
	cp entware/010-dns-wan-transport.sh ipkg/data/opt/etc/ndm/wan.d/
	cp -r web/* ipkg/data/opt/share/dns-wan-transport/
	echo "Package: dns-wan-transport" > ipkg/control/control
	echo "Version: $(VERSION)" >> ipkg/control/control
	echo "Architecture: all" >> ipkg/control/control
	echo "Maintainer: dns-wan-transport contributors" >> ipkg/control/control
	echo "Description: SOCKS5 WAN bridge for Keenetic DNS failover" >> ipkg/control/control
