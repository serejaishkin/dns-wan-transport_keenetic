BINARY_NAME=dns-wan-transport
BUILD_DIR=build

.PHONY: all clean mipsle arm arm64

all: mipsle arm arm64

mipsle:
	mkdir -p $(BUILD_DIR)
	GOOS=linux GOARCH=mipsle GOMIPS=softfloat go build -ldflags="-s -w" -o $(BUILD_DIR)/$(BINARY_NAME)_mipsle cmd/daemon/main.go

arm:
	mkdir -p $(BUILD_DIR)
	GOOS=linux GOARCH=arm GOARM=7 go build -ldflags="-s -w" -o $(BUILD_DIR)/$(BINARY_NAME)_arm cmd/daemon/main.go

arm64:
	mkdir -p $(BUILD_DIR)
	GOOS=linux GOARCH=arm64 go build -ldflags="-s -w" -o $(BUILD_DIR)/$(BINARY_NAME)_arm64 cmd/daemon/main.go

clean:
	rm -rf $(BUILD_DIR)
