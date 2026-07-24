package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
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

func logInfo(format string, v ...interface{}) {
	msg := fmt.Sprintf(format, v...)
	fmt.Fprintf(os.Stdout, "<6>dns-wan-transport: %s\n", msg)
}

func logError(format string, v ...interface{}) {
	msg := fmt.Sprintf(format, v...)
	fmt.Fprintf(os.Stderr, "<3>dns-wan-transport: %s\n", msg)
}

func main() {
	configPath := flag.String("config", "/opt/etc/dns-wan-transport/config.json", "Path to json config")
	flag.Parse()

	file, err := os.Open(*configPath)
	if err != nil {
		logError("Failed to open config: %v", err)
		os.Exit(1)
	}
	defer file.Close()

	var cfg Config
	if err := json.NewDecoder(file).Decode(&cfg); err != nil {
		logError("Failed to parse json config: %v", err)
		os.Exit(1)
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
			logError("Web UI server error: %v", err)
		}
	}()

	logInfo("Service started successfully. Monitoring initiated.")

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
					logInfo("DNS Upstreams are healthy [OK]. Restoring SOCKS5 bridge interface.")
					socksCtx, socksCancel = context.WithCancel(ctx)
					srv = socks5.NewSocksServer(cfg.Server.Socks5Addr)
					go srv.Start(socksCtx)
				} else {
					logError("CRITICAL: All DNS Upstreams down! Dropping SOCKS5 bridge to trigger Keenetic WAN Failover.")
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
	logInfo("Shutting down dns-wan-transport daemon gracefully...")
}
