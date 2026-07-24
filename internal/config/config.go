package config

import (
	"encoding/json"
	"fmt"
	"os"
	"time"
)

// Config is the root configuration.
type Config struct {
	Listen   string  `json:"listen"`   // SOCKS5 listen address
	Backend  Backend `json:"backend"`  // Health check backend
	Interval string  `json:"interval"` // Check interval as string, e.g. "5s"
	Timeout  string  `json:"timeout"`  // Check timeout as string, e.g. "3s"
	Fails    int     `json:"fails"`      // Consecutive fails before unhealthy
	Web      string  `json:"web"`        // Web UI listen address
}

// Parsed returns durations parsed from string fields.
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

// Backend describes a health-check target.
type Backend struct {
	Type    string `json:"type"`    // "dns", "tcp", "http"
	Address string `json:"address"` // e.g. "127.0.0.1:5354" or "http://127.0.0.1:3000/health"
	Domain  string `json:"domain"`  // For DNS: query domain (optional)
}

// Load reads and parses the JSON config file.
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

	// Validate durations
	if _, _, err := cfg.Parsed(); err != nil {
		return nil, err
	}

	return cfg, nil
}
