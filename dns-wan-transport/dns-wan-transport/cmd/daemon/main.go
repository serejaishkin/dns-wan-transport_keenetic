package main

import (
	"context"
	"encoding/json"
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"dns-wan-transport/internal/health"
	"dns-wan-transport/internal/socks5"
	"dns-wan-transport/internal/web"
)

type Config struct {
	Server struct {
		Socks5Addr string `json:"socks5_addr"`
		WebUIAddr  string `json:"web_ui_addr"`
	} `json:"server"`
	HealthCheck struct {
		IntervalMS    int    `json:"interval_ms"`
		TimeoutMS     int    `json:"timeout_ms"`
		FailThreshold int    `json:"fail_threshold"`
		QueryDomain   string `json:"query_domain"`
	} `json:"health_check"`
	Backends []*health.Backend `json:"backends"`
}

func main() {
	configPath := flag.String("config", "/opt/etc/dns-wan-transport/config.json", "Path to json config")
	flag.Parse()

	file, err := os.Open(*configPath)
	if err != nil {
		log.Fatalf("Failed to open config: %v", err)
	}
	defer file.Close()

	var cfg Config
	if err := json.NewDecoder(file).Decode(&cfg); err != nil {
		log.Fatalf("Failed to parse json config: %v", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	statusCh := make(chan bool, 5)
	monitor := health.NewMonitor(
		cfg.Backends,
		time.Duration(cfg.HealthCheck.IntervalMS)*time.Millisecond,
		time.Duration(cfg.HealthCheck.TimeoutMS)*time.Millisecond,
		cfg.HealthCheck.FailThreshold,
		cfg.HealthCheck.QueryDomain,
		statusCh,
	)

	go monitor.Start(ctx)

	webServer := web.NewWebServer(cfg.Server.WebUIAddr, monitor)
	go func() {
		if err := webServer.Start(); err != nil {
			log.Printf("Web UI server error: %v", err)
		}
	}()

	go func() {
		var socksCtx context.Context
		var socksCancel context.CancelFunc
		var srv *socks5.SocksServer

		socksCtx, socksCancel = context.WithCancel(ctx)
		srv = socks5.NewSocksServer(cfg.Server.Socks5Addr)
		go srv.Start(socksCtx)

		for {
			select {
			case <-ctx.Done():
				if socksCancel != nil { socksCancel() }
				return
			case alive := <-statusCh:
				if alive {
					log.Println("DNS Upstreams are healthy. Starting SOCKS5 bridge...")
					socksCtx, socksCancel = context.WithCancel(ctx)
					srv = socks5.NewSocksServer(cfg.Server.Socks5Addr)
					go srv.Start(socksCtx)
				} else {
					log.Println("DNS Upstreams failed! Dropping SOCKS5 bridge to trigger Keenetic Failover...")
					if socksCancel != nil {
						socksCancel()
					}
				}
			}
		}
	}()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	<-sigCh
	log.Println("Shutting down dns-wan-transport...")
}
