package main

import (
	"flag"
	"fmt"
	"log"
	"net"

	"github.com/keenetic/dns-wan-transport/internal/config"
	"github.com/keenetic/dns-wan-transport/internal/service"
)

var (
	configPath = flag.String("config", "/opt/etc/dns-wan-transport/config.json", "Path to config file")
	version    = "dev"
)

// checkPort verifies that a TCP address is available.
func checkPort(name, addr string) error {
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return fmt.Errorf("%s port %s already in use: %w", name, addr, err)
	}
	ln.Close()
	return nil
}

func main() {
	flag.Parse()

	cfg, err := config.Load(*configPath)
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Verify required ports are free before starting
	if err := checkPort("SOCKS5", cfg.Listen); err != nil {
		log.Fatalf("Port check failed: %v", err)
	}
	if err := checkPort("Web UI", cfg.Web); err != nil {
		log.Fatalf("Port check failed: %v", err)
	}

	app, err := service.New(*cfg, version)
	if err != nil {
		log.Fatalf("Failed to create app: %v", err)
	}

	app.Run()
}
