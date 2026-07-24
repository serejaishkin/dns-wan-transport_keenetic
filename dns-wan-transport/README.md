# dns-wan-transport

SOCKS5 WAN Bridge for Keenetic with DNS/TCP/HTTP health-check failover.

## What it does

Turns any local DNS server (AdGuard Home, SmartDNS, Unbound, Technitium DNS, etc.) into a native Keenetic SOCKS5 WAN connection with automatic failover.

```
Keenetic
   │
   └── SOCKS5 WAN ──► 127.0.0.1:11000
                          │
              dns-wan-transport
                          │
           ┌──────────────┴──────────────┐
           │         Health Check          │
           │  DNS / TCP / HTTP backend   │
           └─────────────────────────────┘
                          │
                    AdGuard Home
                    127.0.0.1:5354
```

## How it works

1. Your DNS server listens on `127.0.0.1:5354`
2. **dns-wan-transport** runs a SOCKS5 proxy on `127.0.0.1:11000`
3. Keenetic has a SOCKS5 WAN pointing to `127.0.0.1:11000`
4. Every few seconds a **real health check** is performed against the backend
5. While healthy → SOCKS5 accepts connections → Keenetic keeps WAN active
6. When backend fails → SOCKS5 rejects new connections → Keenetic fails over to backup WAN

## Install (Entware)

```bash
opkg install dns-wan-transport
```

Or manually:

```bash
cp dns-wan-transport /opt/sbin/
mkdir -p /opt/etc/dns-wan-transport
cp config.json.example /opt/etc/dns-wan-transport/config.json
/opt/etc/init.d/S99dns-wan-transport start
```

## Configuration

Single JSON file:

```json
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
```

### Backend types

| Type | Address example | Description |
|------|-----------------|-------------|
| `dns` | `127.0.0.1:5354` | Sends a real DNS query (A record). NXDOMAIN is OK. |
| `tcp` | `127.0.0.1:8080` | Opens a TCP connection and immediately closes. |
| `http` | `http://127.0.0.1:3000/health` | HTTP GET, 5xx = fail. |

## Keenetic setup

1. **Internet → Other Connections → Add connection**
2. Type: **SOCKS5 proxy**
3. Address: `127.0.0.1:11000`
4. Add to your routing policy
5. (Optional) Bind DNS to this WAN in **Network Rules → Internet Safety → DNS**

## Web UI

Open `http://<router-ip>:11001/`

Shows real-time status, latency, history, and active SOCKS5 connections.

## API

- `GET /api/status` — current health, version, latency
- `GET /api/history` — last 100 check results
- `GET /api/config` — running configuration

## Build

```bash
# Native
go build ./cmd/dns-wan-transport

# Entware cross-compile
make mipsel    # MT7621 (Keenetic Giga/Viva)
make arm64     # Keenetic Peak/Ultra
make armv7     # Keenetic Hop/Duo
make x86_64    # Virtual machines
```

## Project structure

```
dns-wan-transport/
├── cmd/dns-wan-transport/
│   └── main.go           # Entry point (~20 lines)
├── internal/
│   ├── config/
│   │   └── config.go     # JSON config (~50 lines)
│   ├── health/
│   │   └── health.go       # Health checker (~150 lines)
│   ├── transport/
│   │   └── transport.go    # SOCKS5 via armon/go-socks5 (~60 lines)
│   ├── web/
│   │   └── web.go          # HTTP API + static files (~80 lines)
│   └── service/
│       └── service.go      # Orchestrator (~60 lines)
├── web/
│   └── index.html          # Dark UI dashboard
├── entware/
│   ├── S99dns-wan-transport
│   └── 010-dns-wan-transport.sh
├── config.json.example
├── Makefile
├── go.mod
└── README.md
```

Total: **~700 lines of Go**.

## License

MIT
