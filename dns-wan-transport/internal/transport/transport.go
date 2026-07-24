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

// Server wraps armon/go-socks5 with health-aware dialing.
type Server struct {
	addr   string
	hc     *health.Checker
	server *socks5.Server
	active atomic.Int32
}

// New creates a SOCKS5 server.
func New(listen string, hc *health.Checker) (*Server, error) {
	s := &Server{addr: listen, hc: hc}

	conf := &socks5.Config{
		Dial: s.dial,
	}

	server, err := socks5.New(conf)
	if err != nil {
		return nil, fmt.Errorf("create socks5: %w", err)
	}
	s.server = server
	return s, nil
}

// Run starts the SOCKS5 listener.
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

// dial is the custom dialer used by go-socks5.
// If health check fails, we return an error so Keenetic sees the WAN as down.
func (s *Server) dial(ctx context.Context, network, addr string) (net.Conn, error) {
	if !s.hc.IsHealthy() {
		return nil, fmt.Errorf("backend unhealthy")
	}
	var d net.Dialer
	return d.DialContext(ctx, network, addr)
}

// Active returns the number of active connections.
func (s *Server) Active() int {
	return int(s.active.Load())
}
