package health

import (
	"context"
	"net"
	"strings"
	"sync"
	"time"
)

type Backend struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Address   string    `json:"address"`
	Priority  int       `json:"priority"`
	IsAlive   bool      `json:"is_alive"`
	LatencyMS int64     `json:"latency_ms"`
	History   []int64   `json:"history"`
}

type Monitor struct {
	mu            sync.RWMutex
	backends      []*Backend
	interval      time.Duration
	timeout       time.Duration
	failThreshold int
	failCount     int
	queryDomain   string
	rawQuery      []byte
	statusCh      chan bool
	isSystemAlive bool
}

func NewMonitor(backends []*Backend, interval, timeout time.Duration, threshold int, domain string, statusCh chan bool) *Monitor {
	return &Monitor{
		backends:      backends,
		interval:      interval,
		timeout:       timeout,
		failThreshold: threshold,
		queryDomain:   domain,
		rawQuery:      buildDNSQuery(domain),
		statusCh:      statusCh,
		isSystemAlive: true,
	}
}

func buildDNSQuery(domain string) []byte {
	packet := []byte{
		0xAA, 0xBB, // Transaction ID
		0x01, 0x00, // Flags: Standard query
		0x00, 0x01, // Questions: 1
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Answer, Authority, Additional RRs = 0
	}
	parts := strings.Split(domain, ".")
	for _, part := range parts {
		packet = append(packet, byte(len(part)))
		packet = append(packet, part...)
	}
	packet = append(packet, 0x00) // End of domain
	packet = append(packet, 0x00, 0x01) // Type: A
	packet = append(packet, 0x00, 0x01) // Class: IN
	return packet
}

func (m *Monitor) Start(ctx context.Context) {
	ticker := time.NewTicker(m.interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			m.checkAll()
		}
	}
}

func (m *Monitor) checkAll() {
	m.mu.Lock()
	defer m.mu.Unlock()

	anyAlive := false
	for _, b := range m.backends {
		start := time.Now()
		err := m.pingDNS(b.Address)
		duration := time.Since(start).Milliseconds()

		if err == nil {
			b.IsAlive = true
			b.LatencyMS = duration
			anyAlive = true
			if len(b.History) >= 30 { b.History = b.History[1:] }
			b.History = append(b.History, duration)
		} else {
			b.IsAlive = false
			b.LatencyMS = -1
			if len(b.History) >= 30 { b.History = b.History[1:] }
			b.History = append(b.History, -1)
		}
	}

	if anyAlive {
		m.failCount = 0
		if !m.isSystemAlive {
			m.isSystemAlive = true
			m.statusCh <- true
		}
	} else {
		m.failCount++
		if m.failCount >= m.failThreshold && m.isSystemAlive {
			m.isSystemAlive = false
			m.statusCh <- false
		}
	}
}

func (m *Monitor) pingDNS(addr string) error {
	d := net.Dialer{Timeout: m.timeout}
	conn, err := d.Dial("udp", addr)
	if err != nil {
		return err
	}
	defer conn.Close()

	if _, err := conn.Write(m.rawQuery); err != nil {
		return err
	}

	buf := make([]byte, 512)
	_ = conn.SetReadDeadline(time.Now().Add(m.timeout))
	_, err = conn.Read(buf)
	return err
}

func (m *Monitor) GetSnapshot() []*Backend {
	m.mu.RLock()
	defer m.mu.RUnlock()
	
	cp := make([]*Backend, len(m.backends))
	for i, b := range m.backends {
		h := make([]int64, len(b.History))
		copy(h, b.History)
		cp[i] = &Backend{
			ID: b.ID, Name: b.Name, Address: b.Address, Priority: b.Priority,
			IsAlive: b.IsAlive, LatencyMS: b.LatencyMS, History: h,
		}
	}
	return cp
}
