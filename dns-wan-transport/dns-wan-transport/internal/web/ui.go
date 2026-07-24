package web

import (
	"encoding/json"
	"net/http"
	"dns-wan-transport/internal/health"
)

type WebServer struct {
	addr    string
	monitor *health.Monitor
}

func NewWebServer(addr string, m *health.Monitor) *WebServer {
	return &WebServer{addr: addr, monitor: m}
}

func (ws *WebServer) Start() error {
	http.HandleFunc("/api/stats", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ws.monitor.GetSnapshot())
	})

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write([]byte(htmlPage))
	})

	return http.ListenAndServe(ws.addr, nil)
}

const htmlPage = `
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>dns-wan-transport</title>
    <style>
        body { font-family: -apple-system, sans-serif; background: #121212; color: #e0e0e0; margin: 20px; }
        .card { background: #1e1e1e; border-radius: 8px; padding: 16px; margin-bottom: 16px; box-shadow: 0 4px 6px rgba(0,0,0,0.4); }
        .status-up { color: #4caf50; font-weight: bold; }
        .status-down { color: #f44336; font-weight: bold; }
        .graph { background: #262626; height: 50px; margin-top: 12px; border-radius: 4px; overflow: hidden; }
        .sparkline { width: 100%; height: 100%; stroke: #2196f3; stroke-width: 2; fill: none; }
    </style>
</head>
<body>
    <h2>DNS WAN Transport Dashboard</h2>
    <div id="list"></div>
    <script>
        async function update() {
            try {
                const r = await fetch('/api/stats');
                const data = await r.json();
                const container = document.getElementById('list');
                container.innerHTML = '';
                data.forEach(b => {
                    const points = b.history.map((v, i) => {
                        const x = (i / 29) * 100;
                        const y = v === -1 ? 50 : 50 - Math.min((v / 150) * 50, 50);
                        return "" + x + "," + y;
                    }).join(' ');
                    container.innerHTML += '<div class="card"><h3>' + b.name + ' <span class="' + (b.is_alive ? 'status-up' : 'status-down') + '">' + (b.is_alive ? 'ONLINE' : 'OFFLINE') + '</span></h3>Latency: <strong>' + (b.latency_ms >= 0 ? b.latency_ms + ' ms' : 'Timeout') + '</strong><br><div class="graph"><svg viewBox="0 0 100 50" preserveAspectRatio="none" style="width:100%; height:100%;"><polyline class="sparkline" points="' + points + '"/></svg></div></div>';
                });
            } catch (e) {}
        }
        setInterval(update, 3000); update();
    </script>
</body>
</html>
`
