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
