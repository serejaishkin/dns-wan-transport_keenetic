.PHONY: all build clean install package release mipsel mips arm64 armv7 x86_64

BINARY=dns-wan-transport
VERSION=$(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
LDFLAGS=-ldflags "-s -w -X main.version=$(VERSION)"

all: build

build:
	go build $(LDFLAGS) -o $(BINARY) ./cmd/dns-wan-transport

clean:
	rm -f $(BINARY) $(BINARY)-* *.ipk

install: build
	install -Dm755 $(BINARY) $(DESTDIR)/opt/sbin/$(BINARY)
	install -Dm644 config.json.example $(DESTDIR)/opt/etc/dns-wan-transport/config.json
	install -Dm755 entware/S99dns-wan-transport $(DESTDIR)/opt/etc/init.d/S99dns-wan-transport
	install -Dm755 entware/010-dns-wan-transport.sh $(DESTDIR)/opt/etc/ndm/wan.d/010-dns-wan-transport.sh
	install -Dm644 web/index.html $(DESTDIR)/opt/share/dns-wan-transport/web/index.html

# Cross-compilation targets
mipsel:
	GOOS=linux GOARCH=mipsle GOMIPS=softfloat go build $(LDFLAGS) -o $(BINARY)-mipsel ./cmd/dns-wan-transport

mips:
	GOOS=linux GOARCH=mips GOMIPS=softfloat go build $(LDFLAGS) -o $(BINARY)-mips ./cmd/dns-wan-transport

arm64:
	GOOS=linux GOARCH=arm64 go build $(LDFLAGS) -o $(BINARY)-aarch64 ./cmd/dns-wan-transport

armv7:
	GOOS=linux GOARCH=arm GOARM=7 go build $(LDFLAGS) -o $(BINARY)-armv7 ./cmd/dns-wan-transport

x86_64:
	GOOS=linux GOARCH=amd64 go build $(LDFLAGS) -o $(BINARY)-x86_64 ./cmd/dns-wan-transport

# Build all architectures
release: clean mipsel mips arm64 armv7 x86_64
	@echo "Built all architectures:"
	@ls -la $(BINARY)-*

# Build local opkg package (requires binary to exist)
ipk: build
	./scripts/build-ipk.sh mipsel $(VERSION:v%=%) $(BINARY) $(BINARY)_$(VERSION:v%=%)_mipsel.ipk

# Build opkg for specific arch
ipk-%: $(BINARY)-%
	./scripts/build-ipk.sh $* $(VERSION:v%=%) $(BINARY)-$* $(BINARY)_$(VERSION:v%=%)_$*.ipk
