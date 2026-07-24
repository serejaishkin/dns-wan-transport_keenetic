.PHONY: all build clean release mipsel mips arm64 armv7 x86_64

BINARY=dns-wan-transport
VERSION=$(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
LDFLAGS=-ldflags "-s -w -X main.version=$(VERSION)"

all: build

build:
	go build $(LDFLAGS) -o $(BINARY) ./cmd/dns-wan-transport

clean:
	rm -f $(BINARY) $(BINARY)-* *.ipk

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

release: clean mipsel mips arm64 armv7 x86_64
