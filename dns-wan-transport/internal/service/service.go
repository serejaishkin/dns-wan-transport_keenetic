package service

import (
	"context"
	"log"
	"os"
	"os/signal"
	"sync"
	"syscall"

	"github.com/keenetic/dns-wan-transport/internal/config"
	"github.com/keenetic/dns-wan-transport/internal/health"
	"github.com/keenetic/dns-wan-transport/internal/transport"
	"github.com/keenetic/dns-wan-transport/internal/web"
)

type App struct {
	cfg   config.Config
	ver   string
	hc    *health.Checker
	socks *transport.Server
	web   *web.Server
}

func New(cfg config.Config, version string) (*App, error) {
	hc, err := health.New(cfg)
	if err != nil {
		return nil, err
	}
	socks, err := transport.New(cfg.Listen, hc)
	if err != nil {
		return nil, err
	}
	w := web.New(cfg, hc, socks, version)
	return &App{cfg: cfg, ver: version, hc: hc, socks: socks, web: w}, nil
}

func (a *App) Run() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var wg sync.WaitGroup

	wg.Add(1)
	go func() { defer wg.Done(); a.hc.Run(ctx) }()

	for i := 0; i < 50 && !a.hc.IsHealthy(); i++ {}

	wg.Add(1)
	go func() {
		defer wg.Done()
		if err := a.socks.Run(ctx); err != nil {
			log.Printf("[socks5] %v", err)
		}
	}()

	wg.Add(1)
	go func() {
		defer wg.Done()
		if err := a.web.Run(ctx); err != nil {
			log.Printf("[web] %v", err)
		}
	}()

	log.Printf("dns-wan-transport %s", a.ver)
	log.Printf("SOCKS5  -> %s", a.cfg.Listen)
	log.Printf("Web UI  -> http://%s", a.cfg.Web)
	log.Printf("Backend -> %s %s", a.cfg.Backend.Type, a.cfg.Backend.Address)

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	<-sigCh

	log.Println("Shutting down...")
	cancel()
	wg.Wait()
	log.Println("Done.")
}
