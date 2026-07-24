BINARY_NAME=dns-wan-transport
BUILD_DIR=build

.PHONY: all clean mipsle

all: mipsle

mipsle:
	mkdir -p $(BUILD_DIR)
	CGO_ENABLED=0 GOOS=linux GOARCH=mipsle GOMIPS=softfloat go build -tags=purego -gcflags=all="-N -l" -ldflags="-s -w" -o $(BUILD_DIR)/$(BINARY_NAME)_mipsle cmd/daemon/main.go

clean:
	rm -rf $(BUILD_DIR)
