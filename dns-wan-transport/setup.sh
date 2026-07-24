#!/bin/bash
set -e

echo "=== Creating dns-wan-transport project files ==="

# Create directories
mkdir -p cmd/dns-wan-transport internal/config internal/health internal/service internal/transport internal/web web entware scripts .github/workflows

# go.mod
cat > go.mod << 'EOF'
module github.com/keenetic/dns-wan-transport

go 1.21

require (
	github.com/armon/go-socks5 v0.0.0-20160902184237-e75332964ef5
	github.com/miekg/dns v1.1.57
)

require golang.org/x/net v0.19.0 // indirect
EOF

# .gitignore
cat > .gitignore << 'EOF'
dns-wan-transport
*.log
*.pid
*.ipk
/build/
/dist/
ipkg/
*.zip
EOF

# LICENSE
cat > LICENSE << 'EOF'
MIT License

Copyright (c) 2026 dns-wan-transport contributors
EOF

# Makefile
cat > Makefile << 'EOF'
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
EOF

# config.json.example
cat > config.json.example << 'EOF'
{
  "listen": "127.0.0.1:11000",
  "backend": {
    "type": "dns",
    "address": "127.0.0.1:5354",
    "domain": "health.check.internal."
  },
  "interval": "5s",
  "timeout": "3s",
  "fails": 3,
  "web": "127.0.0.1:11001"
}
EOF

# main.go
cat > cmd/dns-wan-transport/main.go << 'EOF'
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
EOF

# config.go
cat > internal/config/config.go << 'EOF'
package config

import (
	"encoding/json"
	"fmt"
	"os"
	"time"
)

type Config struct {
	Listen   string  `json:"listen"`
	Backend  Backend `json:"backend"`
	Interval string  `json:"interval"`
	Timeout  string  `json:"timeout"`
	Fails    int     `json:"fails"`
	Web      string  `json:"web"`
}

type Backend struct {
	Type    string `json:"type"`
	Address string `json:"address"`
	Domain  string `json:"domain"`
}

func (c Config) Parsed() (interval, timeout time.Duration, err error) {
	interval, err = time.ParseDuration(c.Interval)
	if err != nil {
		return 0, 0, fmt.Errorf("parse interval: %w", err)
	}
	timeout, err = time.ParseDuration(c.Timeout)
	if err != nil {
		return 0, 0, fmt.Errorf("parse timeout: %w", err)
	}
	return interval, timeout, nil
}

func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config: %w", err)
	}

	cfg := &Config{
		Listen:   "127.0.0.1:11000",
		Interval: "5s",
		Timeout:  "3s",
		Fails:    3,
		Web:      "127.0.0.1:11001",
		Backend: Backend{
			Type:    "dns",
			Address: "127.0.0.1:5354",
			Domain:  "health.check.internal.",
		},
	}

	if err := json.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}

	if _, _, err := cfg.Parsed(); err != nil {
		return nil, err
	}

	return cfg, nil
}
EOF

# health.go
cat > internal/health/health.go << 'EOF'
package health

import (
	"context"
	"fmt"
	"log"
	"net"
	"net/http"
	"sync"
	"sync/atomic"
	"time"

	"github.com/keenetic/dns-wan-transport/internal/config"
	"github.com/miekg/dns"
)

type Checker struct {
	cfg       config.Config
	interval  time.Duration
	timeout   time.Duration
	checkFunc func() error

	healthy   atomic.Bool
	failCount atomic.Int32
	lastCheck atomic.Value
	lastError atomic.Value
	latency   atomic.Int64

	mu      sync.RWMutex
	history []Result
}

type Result struct {
	Time    time.Time `json:"time"`
	Healthy bool      `json:"healthy"`
	Latency int64     `json:"latency_ms"`
	Error   string    `json:"error,omitempty"`
}

func New(cfg config.Config) (*Checker, error) {
	interval, timeout, err := cfg.Parsed()
	if err != nil {
		return nil, err
	}

	c := &Checker{
		cfg:      cfg,
		interval: interval,
		timeout:  timeout,
		history:  make([]Result, 0, 100),
	}
	c.healthy.Store(false)
	c.lastCheck.Store(time.Time{})
	c.lastError.Store("")
	c.latency.Store(0)

	switch cfg.Backend.Type {
	case "tcp":
		c.checkFunc = c.checkTCP
	case "http":
		c.checkFunc = c.checkHTTP
	default:
		c.checkFunc = c.checkDNS
	}

	return c, nil
}

func (c *Checker) Run(ctx context.Context) {
	c.checkOnce()
	ticker := time.NewTicker(c.interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			c.checkOnce()
		}
	}
}

func (c *Checker) checkOnce() {
	start := time.Now()
	err := c.checkFunc()
	ms := time.Since(start).Milliseconds()
	c.latency.Store(ms)

	res := Result{Time: start, Latency: ms}
	if err != nil {
		res.Error = err.Error()
		c.lastError.Store(err.Error())
		c.failCount.Add(1)
		if int(c.failCount.Load()) >= c.cfg.Fails {
			c.healthy.Store(false)
		}
		log.Printf("[health] FAIL: %v (%dms)", err, ms)
	} else {
		c.failCount.Store(0)
		c.healthy.Store(true)
		c.lastError.Store("")
		log.Printf("[health] OK (%dms)", ms)
	}
	res.Healthy = c.healthy.Load()
	c.lastCheck.Store(start)

	c.mu.Lock()
	c.history = append(c.history, res)
	if len(c.history) > 100 {
		c.history = c.history[len(c.history)-100:]
	}
	c.mu.Unlock()
}

func (c *Checker) checkDNS() error {
	msg := new(dns.Msg)
	domain := c.cfg.Backend.Domain
	if domain == "" {
		domain = "health.check.internal."
	}
	msg.SetQuestion(dns.Fqdn(domain), dns.TypeA)
	msg.RecursionDesired = true

	client := &dns.Client{Net: "udp", Timeout: c.timeout}
	r, _, err := client.Exchange(msg, c.cfg.Backend.Address)
	if err != nil {
		return err
	}
	if r.Rcode != dns.RcodeSuccess && r.Rcode != dns.RcodeNameError {
		return fmt.Errorf("dns rcode: %s", dns.RcodeToString[r.Rcode])
	}
	return nil
}

func (c *Checker) checkTCP() error {
	conn, err := net.DialTimeout("tcp", c.cfg.Backend.Address, c.timeout)
	if err != nil {
		return err
	}
	conn.Close()
	return nil
}

func (c *Checker) checkHTTP() error {
	client := &http.Client{Timeout: c.timeout}
	resp, err := client.Get(c.cfg.Backend.Address)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 500 {
		return fmt.Errorf("http status: %d", resp.StatusCode)
	}
	return nil
}

func (c *Checker) IsHealthy() bool   { return c.healthy.Load() }
func (c *Checker) LastCheck() time.Time { return c.lastCheck.Load().(time.Time) }
func (c *Checker) LastError() string    { return c.lastError.Load().(string) }
func (c *Checker) Latency() int64       { return c.latency.Load() }

func (c *Checker) History() []Result {
	c.mu.RLock()
	defer c.mu.RUnlock()
	h := make([]Result, len(c.history))
	copy(h, c.history)
	return h
}
EOF

# transport.go
cat > internal/transport/transport.go << 'EOF'
package transport

import (
	"context"
	"fmt"
	"log"
	"net"
	"sync/atomic"

	"github.com/armon/go-socks5"
	"github.com/keenetic/dns-wan-transport/internal/health"
)

type Server struct {
	addr   string
	hc     *health.Checker
	server *socks5.Server
	active atomic.Int32
}

func New(listen string, hc *health.Checker) (*Server, error) {
	s := &Server{addr: listen, hc: hc}
	conf := &socks5.Config{Dial: s.dial}
	server, err := socks5.New(conf)
	if err != nil {
		return nil, fmt.Errorf("create socks5: %w", err)
	}
	s.server = server
	return s, nil
}

func (s *Server) Run(ctx context.Context) error {
	ln, err := net.Listen("tcp", s.addr)
	if err != nil {
		return fmt.Errorf("listen %s: %w", s.addr, err)
	}
	go func() {
		<-ctx.Done()
		ln.Close()
	}()

	for {
		conn, err := ln.Accept()
		if err != nil {
			select {
			case <-ctx.Done():
				return nil
			default:
				log.Printf("[socks5] accept error: %v", err)
				continue
			}
		}
		s.active.Add(1)
		go func(c net.Conn) {
			defer s.active.Add(-1)
			s.server.ServeConn(c)
		}(conn)
	}
}

func (s *Server) dial(ctx context.Context, network, addr string) (net.Conn, error) {
	if !s.hc.IsHealthy() {
		return nil, fmt.Errorf("backend unhealthy")
	}
	var d net.Dialer
	return d.DialContext(ctx, network, addr)
}

func (s *Server) Active() int { return int(s.active.Load()) }
EOF

# web.go
cat > internal/web/web.go << 'EOF'
package web

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/keenetic/dns-wan-transport/internal/config"
	"github.com/keenetic/dns-wan-transport/internal/health"
	"github.com/keenetic/dns-wan-transport/internal/transport"
)

type Server struct {
	cfg     config.Config
	hc      *health.Checker
	socks   *transport.Server
	version string
	mux     *http.ServeMux
}

func New(cfg config.Config, hc *health.Checker, socks *transport.Server, version string) *Server {
	s := &Server{cfg: cfg, hc: hc, socks: socks, version: version, mux: http.NewServeMux()}
	s.setupRoutes()
	return s
}

func (s *Server) setupRoutes() {
	s.mux.HandleFunc("/api/status", s.handleStatus)
	s.mux.HandleFunc("/api/history", s.handleHistory)
	s.mux.HandleFunc("/api/config", s.handleConfig)
	s.mux.Handle("/", http.FileServer(http.Dir("./web")))
}

func (s *Server) Run(ctx context.Context) error {
	srv := &http.Server{Addr: s.cfg.Web, Handler: s.mux}
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		srv.Shutdown(shutdownCtx)
	}()
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		return fmt.Errorf("web server: %w", err)
	}
	return nil
}

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, map[string]interface{}{
		"version": s.version, "healthy": s.hc.IsHealthy(),
		"last_check": s.hc.LastCheck(), "last_error": s.hc.LastError(),
		"latency_ms": s.hc.Latency(), "active_socks5": s.socks.Active(),
	})
}

func (s *Server) handleHistory(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, map[string]interface{}{"history": s.hc.History()})
}

func (s *Server) handleConfig(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, map[string]interface{}{
		"listen": s.cfg.Listen, "backend": s.cfg.Backend, "web": s.cfg.Web,
	})
}

func writeJSON(w http.ResponseWriter, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}
EOF

# service.go
cat > internal/service/service.go << 'EOF'
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
EOF

# index.html
cat > web/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>dns-wan-transport</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#0b0f19;color:#c9d1d9;padding:2rem}
.container{max-width:900px;margin:0 auto}
h1{font-size:1.6rem;color:#f0f6fc;margin-bottom:.25rem}
.subtitle{color:#8b949e;margin-bottom:2rem;font-size:.9rem}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:1rem;margin-bottom:2rem}
.card{background:#161b22;border-radius:10px;padding:1.2rem;border:1px solid #30363d}
.label{font-size:.7rem;text-transform:uppercase;letter-spacing:.05em;color:#8b949e;margin-bottom:.4rem}
.value{font-size:1.4rem;font-weight:600;color:#f0f6fc}
.value.ok{color:#3fb950}
.value.fail{color:#f85149}
.history{background:#161b22;border-radius:10px;padding:1.2rem;border:1px solid #30363d}
.history h2{font-size:1rem;margin-bottom:1rem;color:#f0f6fc}
table{width:100%;border-collapse:collapse;font-size:.82rem}
th{text-align:left;padding:.5rem;color:#8b949e;border-bottom:1px solid #30363d;font-weight:500}
td{padding:.5rem;border-bottom:1px solid #21262d}
.ok{color:#3fb950}
.fail{color:#f85149}
.refresh{position:fixed;top:1.5rem;right:1.5rem;background:#238636;color:#fff;border:none;padding:.5rem 1rem;border-radius:6px;cursor:pointer;font-size:.85rem;font-weight:500}
.refresh:hover{background:#2ea043}
.footer{margin-top:2rem;color:#484f58;font-size:.8rem}
</style>
</head>
<body>
<div class="container">
<h1>dns-wan-transport</h1>
<p class="subtitle">Keenetic SOCKS5 WAN Bridge &mdash; <span id="ver">-</span></p>
<button class="refresh" onclick="load()">Refresh</button>
<div class="grid">
<div class="card"><div class="label">Backend Status</div><div class="value" id="status">Loading...</div></div>
<div class="card"><div class="label">Last Check</div><div class="value" id="last">-</div></div>
<div class="card"><div class="label">Latency</div><div class="value" id="lat">-</div></div>
<div class="card"><div class="label">Active SOCKS5</div><div class="value" id="socks">-</div></div>
<div class="card"><div class="label">Backend Type</div><div class="value" id="btype">-</div></div>
<div class="card"><div class="label">Backend Address</div><div class="value" id="baddr">-</div></div>
</div>
<div class="history">
<h2>Recent Checks</h2>
<table><thead><tr><th>Time</th><th>Status</th><th>Latency</th><th>Error</th></tr></thead>
<tbody id="tbody"></tbody></table>
</div>
<div class="footer">dns-wan-transport &mdash; auto-refresh every 5s</div>
</div>
<script>
async function load(){
try{
const [st,hi,cf]=await Promise.all([
fetch('/api/status').then(r=>r.json()),
fetch('/api/history').then(r=>r.json()),
fetch('/api/config').then(r=>r.json())
]);
const el=document.getElementById('status');
el.textContent=st.healthy?'HEALTHY':'UNHEALTHY';
el.className='value '+(st.healthy?'ok':'fail');
document.getElementById('ver').textContent=st.version;
document.getElementById('last').textContent=st.last_check?new Date(st.last_check).toLocaleTimeString():'Never';
document.getElementById('lat').textContent=st.latency_ms+' ms';
document.getElementById('socks').textContent=st.active_socks5;
document.getElementById('btype').textContent=cf.backend.type;
document.getElementById('baddr').textContent=cf.backend.address;
const tb=document.getElementById('tbody');
tb.innerHTML=hi.history.slice().reverse().slice(0,20).map(h=>`<tr><td>${new Date(h.time).toLocaleTimeString()}</td><td class="${h.healthy?'ok':'fail'}">${h.healthy?'OK':'FAIL'}</td><td>${h.latency_ms} ms</td><td>${h.error||'-'}</td></tr>`).join('');
}catch(e){console.error(e)}
}
load();
setInterval(load,5000);
</script>
</body>
</html>
EOF

# S99dns-wan-transport
cat > entware/S99dns-wan-transport << 'EOF'
#!/bin/sh

ENABLED=yes
PROCS=dns-wan-transport
ARGS="-config /opt/etc/dns-wan-transport/config.json"
PREARGS=""
DESC="DNS WAN Transport for Keenetic"
PIDFILE=/opt/var/run/dns-wan-transport.pid
PATH=/opt/sbin:/opt/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

start_pre() {
    if [ -f "$PIDFILE" ]; then
        OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            logger -t dns-wan-transport "Already running (PID $OLD_PID)"
            exit 0
        fi
        rm -f "$PIDFILE"
    fi
    if netstat -tln 2>/dev/null | grep -qE ':11000[[:space:]]'; then
        logger -t dns-wan-transport "ERROR: Port 11000 is already in use!"
        exit 1
    fi
    if netstat -tln 2>/dev/null | grep -qE ':11001[[:space:]]'; then
        logger -t dns-wan-transport "ERROR: Port 11001 is already in use!"
        exit 1
    fi
    [ -d /opt/etc/dns-wan-transport ] || mkdir -p /opt/etc/dns-wan-transport
    if [ ! -f /opt/etc/dns-wan-transport/config.json ]; then
        cat > /opt/etc/dns-wan-transport/config.json <<'EOFCFG'
{
  "listen": "127.0.0.1:11000",
  "backend": {
    "type": "dns",
    "address": "127.0.0.1:5354",
    "domain": "health.check.internal."
  },
  "interval": "5s",
  "timeout": "3s",
  "fails": 3,
  "web": "127.0.0.1:11001"
}
EOFCFG
        logger -t dns-wan-transport "Created default config"
    fi
    [ -d /opt/var/run ] || mkdir -p /opt/var/run
}

start_post() {
    PID=$(pidof dns-wan-transport)
    if [ -n "$PID" ]; then
        echo "$PID" > "$PIDFILE"
    fi
    logger -t dns-wan-transport "Started (PID ${PID:-unknown})"
}

stop_post() {
    rm -f "$PIDFILE"
    logger -t dns-wan-transport "Stopped"
}

. /opt/etc/init.d/rc.func
EOF
chmod 755 entware/S99dns-wan-transport

# 010-dns-wan-transport.sh
cat > entware/010-dns-wan-transport.sh << 'EOF'
#!/bin/sh
[ "$1" = "up" ] || exit 0
/opt/etc/init.d/S99dns-wan-transport restart 2>/dev/null
EOF
chmod 755 entware/010-dns-wan-transport.sh

# build-ipk.sh
cat > scripts/build-ipk.sh << 'EOF'
#!/bin/bash
set -e

ARCH="${1:-mipsel}"
VERSION="${2:-0.1.0}"
BINARY="${3:-dns-wan-transport}"
OUTPUT="${4:-dns-wan-transport_${VERSION}_${ARCH}.ipk}"

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found: $BINARY"
    exit 1
fi

WORKDIR=$(mktemp -d)
trap "rm -rf $WORKDIR" EXIT

mkdir -p "$WORKDIR/data/opt/sbin"
mkdir -p "$WORKDIR/data/opt/etc/dns-wan-transport"
mkdir -p "$WORKDIR/data/opt/etc/init.d"
mkdir -p "$WORKDIR/data/opt/etc/ndm/wan.d"
mkdir -p "$WORKDIR/data/opt/share/dns-wan-transport/web"
mkdir -p "$WORKDIR/data/opt/var/run"

cp "$BINARY" "$WORKDIR/data/opt/sbin/dns-wan-transport"
chmod 755 "$WORKDIR/data/opt/sbin/dns-wan-transport"

cp config.json.example "$WORKDIR/data/opt/etc/dns-wan-transport/config.json"
chmod 644 "$WORKDIR/data/opt/etc/dns-wan-transport/config.json"

cp entware/S99dns-wan-transport "$WORKDIR/data/opt/etc/init.d/"
chmod 755 "$WORKDIR/data/opt/etc/init.d/S99dns-wan-transport"

cp entware/010-dns-wan-transport.sh "$WORKDIR/data/opt/etc/ndm/wan.d/"
chmod 755 "$WORKDIR/data/opt/etc/ndm/wan.d/010-dns-wan-transport.sh"

cp web/index.html "$WORKDIR/data/opt/share/dns-wan-transport/web/"
chmod 644 "$WORKDIR/data/opt/share/dns-wan-transport/web/index.html"

mkdir -p "$WORKDIR/control"
cat > "$WORKDIR/control/control" <<EOFC
Package: dns-wan-transport
Version: $VERSION
Architecture: $ARCH
Maintainer: dns-wan-transport contributors
Source: https://github.com/keenetic/dns-wan-transport
Description: SOCKS5 WAN bridge for Keenetic DNS failover
Section: net
Priority: optional
EOFC

cat > "$WORKDIR/control/postinst" <<'EOFP'
#!/bin/sh
/opt/etc/init.d/S99dns-wan-transport enable 2>/dev/null || true
/opt/etc/init.d/S99dns-wan-transport start 2>/dev/null || true
EOFP
chmod 755 "$WORKDIR/control/postinst"

cat > "$WORKDIR/control/postrm" <<'EOFP'
#!/bin/sh
rm -f /opt/var/run/dns-wan-transport.pid
EOFP
chmod 755 "$WORKDIR/control/postrm"

echo "2.0" > "$WORKDIR/debian-binary"

cd "$WORKDIR"
tar -czf control.tar.gz -C control .
tar -czf data.tar.gz -C data .
tar -czf "$OUTPUT" debian-binary control.tar.gz data.tar.gz

echo "Created: $OUTPUT"
ls -la "$OUTPUT"
EOF
chmod 755 scripts/build-ipk.sh

# build.yml
cat > .github/workflows/build.yml << 'EOF'
name: Build and Release

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:
    inputs:
      tag:
        description: 'Release tag (e.g. v0.1.0)'
        required: true
        default: 'v0.1.0'

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        include:
          - goarch: mipsle
            gomips: softfloat
            entarch: mipsel
            desc: 'MIPS little-endian (Keenetic Giga, Viva, Extra, Start)'
          - goarch: mips
            gomips: softfloat
            entarch: mips
            desc: 'MIPS big-endian (legacy)'
          - goarch: arm64
            entarch: aarch64
            desc: 'ARM64 (Keenetic Peak, Ultra, Speedster, Giant)'
          - goarch: arm
            goarm: '7'
            entarch: armv7
            desc: 'ARMv7 (Keenetic Hop, Duo, City, Air)'
          - goarch: amd64
            entarch: x86_64
            desc: 'x86_64 (VM, Docker)'

    steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-go@v5
      with:
        go-version: '1.21'

    - name: Build binary
      env:
        GOOS: linux
        GOARCH: ${{ matrix.goarch }}
        GOARM: ${{ matrix.goarm }}
        GOMIPS: ${{ matrix.gomips }}
      run: |
        VERSION=${GITHUB_REF_NAME:-${{ github.event.inputs.tag }}}
        LDFLAGS="-s -w -X main.version=$VERSION"
        BIN="dns-wan-transport-${{ matrix.entarch }}"
        go build -ldflags "$LDFLAGS" -o "$BIN" ./cmd/dns-wan-transport
        echo "Built: $BIN"
        ls -la "$BIN"
        file "$BIN"

    - name: Build opkg package
      run: |
        VERSION=${GITHUB_REF_NAME:-${{ github.event.inputs.tag }}}
        VERSION=${VERSION#v}
        ./scripts/build-ipk.sh           "${{ matrix.entarch }}"           "$VERSION"           "dns-wan-transport-${{ matrix.entarch }}"           "dns-wan-transport_${VERSION}_${{ matrix.entarch }}.ipk"

    - name: Upload artifacts
      uses: actions/upload-artifact@v4
      with:
        name: dns-wan-transport-${{ matrix.entarch }}
        path: |
          dns-wan-transport-${{ matrix.entarch }}
          dns-wan-transport_*.ipk

  release:
    needs: build
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
    - uses: actions/checkout@v4
    - uses: actions/download-artifact@v4
      with:
        path: artifacts
        merge-multiple: true
    - uses: softprops/action-gh-release@v1
      if: startsWith(github.ref, 'refs/tags/')
      with:
        files: artifacts/*
        generate_release_notes: true
EOF

echo "=== All files created ==="
ls -la
echo ""
echo "GitHub workflow:"
ls .github/workflows/
echo ""
echo "Go source files:"
find cmd internal -name "*.go" | sort
