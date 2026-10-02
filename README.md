# KaviMac v1.0.0

macOS tune-up, health monitoring, and optimization for Seth's M1 MacBook Air.
The macOS equivalent of **KaviGuard** (Windows).

Native Apple Silicon — no Rosetta. Bash + Python (both ship with macOS).

## What's inside

```
kavimac/
├── kavimac.sh              # Main tune-up (cleanup + optimize + health)
├── kavimac-monitor.sh      # Background health monitor (LaunchAgent)
├── lib/
│   ├── cleanup.sh          # Safe cache/log/trash cleanup, reports space freed
│   ├── health.sh           # CPU, memory, disk, battery, network, power
│   ├── optimize.sh         # Login items, Spotlight, FileVault, updates, swap
│   ├── vpn.sh              # KaviVPN management (WireGuard, macOS-native)
│   └── services.sh         # BlueBubbles, RVG agent, Tailscale status
├── com.seth.kavimac.plist  # LaunchAgent — monitor every 15 min
├── INSTALL.md
└── VERSION
```

## Features

**Cleanup** (safe only — never touches documents, photos, music):
- User caches (keeps Safari/Finder caches)
- System caches (sudo only, safe subset)
- Trash (all volumes)
- Logs older than 7 days
- DNS cache flush
- Xcode DerivedData (often GBs of junk)

**Optimization** (report-first philosophy):
- Login items inventory
- Spotlight indexing status
- FileVault status
- Pending macOS updates
- Swap/memory pressure (flags >2GB swap on 8GB machine)
- Server tweaks verification (sleep settings for BlueBubbles/RVG)

**Health monitoring:**
- CPU usage + load average
- Memory (used/total, pressure)
- Disk usage
- Battery health %, cycle count, charging state
- Network (interface, IP, latency, Tailscale)
- Power settings (warns if sleep is on — kills BlueBubbles/RVG)

**Service watchdog** (monitor script, every 15 min):
- BlueBubbles (port 1234) — alerts if down
- RVG Mac agent (port 8899) — alerts if down
- Disk >90% — alerts
- Heavy swap >2GB — alerts
- KaviVPN auto-reconnect (if AutoConnect enabled)

**KaviVPN integration:**
- `vpn_status` / `vpn_connect` / `vpn_disconnect`
- Auto-connect via LaunchAgent
- Kill switch via pf anchor (manual, full-tunnel mode only)
- Status in health reports
- Design mirrors Windows `KAVIGUARD_INTEGRATION.md`
- **Note:** KaviVPN server not yet deployed (needs Oracle Cloud VM).
  All VPN functions degrade to "not configured" until then.

## Design notes

- **Idempotent**: safe to run repeatedly.
- **No destructive ops**: cleanup only removes regenerable caches/logs/trash.
- **Structured output**: `KEY=VALUE` lines for scripting, human text for reading.
- **Apple Silicon native**: uses `screencapture`, `pmset`, `sysctl`, `ioreg`,
  `vm_stat`, `pfctl`, `wg` — no Intel binaries.
