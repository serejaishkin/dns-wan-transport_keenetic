package socks5

import (
	"context"
	"net"
	"sync"
)

type SocksServer struct {
	addr     string
	listener net.Listener
	mu       sync.Mutex
	conns    map[net.Conn]struct{}
	running  bool
}

func NewSocksServer(addr string) *SocksServer {
	return &SocksServer{
		addr:  addr,
		conns: make(map[net.Conn]struct{}),
	}
}

func (s *SocksServer) Start(ctx context.Context) error {
	s.mu.Lock()
	l, err := net.Listen("tcp", s.addr)
	if err != nil {
		s.mu.Unlock()
		return err
	}
	s.listener = l
	s.running = true
	s.mu.Unlock()

	go func() {
		<-ctx.Done()
		s.Stop()
	}()

	for {
		conn, err := l.Accept()
		if err != nil {
			s.mu.Lock()
			isRunning := s.running
			s.mu.Unlock()
			if !isRunning {
				return nil
			}
			continue
		}
		s.mu.Lock()
		s.conns[conn] = struct{}{}
		s.mu.Unlock()
		go s.handle(conn)
	}
}

func (s *SocksServer) Stop() {
	s.mu.Lock()
	if !s.running {
		s.mu.Unlock()
		return
	}
	s.running = false
	if s.listener != nil {
		s.listener.Close()
	}
	for conn := range s.conns {
		conn.Close()
	}
	s.conns = make(map[net.Conn]struct{})
	s.mu.Unlock()
}

func (s *SocksServer) handle(conn net.Conn) {
	defer func() {
		conn.Close()
		s.mu.Lock()
		delete(s.conns, conn)
		s.mu.Unlock()
	}()

	buf := make([]byte, 256)
	if n, err := conn.Read(buf); err != nil || n < 2 || buf[0] != 0x05 { return }
	if _, err := conn.Write([]byte{0x05, 0x00}); err != nil { return }

	if n, err := conn.Read(buf); err != nil || n < 4 || buf[0] != 0x05 { return }
	if buf[1] != 0x01 { return }

	if _, err := conn.Write([]byte{0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0}); err != nil { return }

	dummy := make([]byte, 1024)
	for {
		_, err := conn.Read(dummy)
		if err != nil {
			return
		}
	}
}
