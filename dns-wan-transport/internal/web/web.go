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
