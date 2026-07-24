BINARY_NAME=dns-wan-transport
BUILD_DIR=build

.PHONY: all clean mipsle

all: mipsle

mipsle:
	mkdir -p $(BUILD_DIR)
	# Очищаем кэш локального компилятора, чтобы не подмешивать Go 1.22+
	go clean -cache -modcache
	# Запуск изолированной чистой сборки в контейнере Go 1.21
	docker run --rm -v "$(PWD)":/usr/src/myapp -w /usr/src/myapp \
		-e CGO_ENABLED=0 -e GOOS=linux -e GOARCH=mipsle -e GOMIPS=softfloat \
		golang:1.21-alpine \
		go build -ldflags="-s -w" -o $(BUILD_DIR)/$(BINARY_NAME)_mipsle cmd/daemon/main.go

clean:
	rm -rf $(BUILD_DIR)
