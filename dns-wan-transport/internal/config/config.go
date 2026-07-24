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
