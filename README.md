# KaviMac v1.1.0 "Server Guard"

macOS tune-up, health monitoring, and optimization for Seth's M1 MacBook Air.
The macOS equivalent of **KaviGuard** (Windows).

Native Apple Silicon — no Rosetta. Bash only (no new dependencies).

## v1.1.0 "Server Guard" — what's new

Designed around the Air's real job: **always-on server** (BlueBubbles, RVD agent,
Tailscale). Every destructive action runs through the protected-services
whitelist and goes to Trash first — nothing is deleted without a restore path.

- **Protected-services guardrail** (`lib/guard.sh`): BlueBubbles, rvd-mac,
  Tailscale, KaviMac can never be killed, purged, or unloaded by any KaviMac
  action. `--guard` checks them all; the full run starts with this check.
- **Never-sleep verifier** (`lib/power.sh`): verifies the power baseline
  (AC sleep 0, autorestart 1, womp 1) and the **lid-close guard** (a sleeping
  laptop is not a server). `--power` reports drift; `--fix-power` re-applies
  (opt-in, never automatic).
- **Preview-first cleanup** (`lib/cleanup.sh`): every sweep shows what will be
  removed + sizes and asks first (`--yes` for trusted reruns). New targets:
  `/private/tmp` and `/var/folders` scratch (>3 days old). All trash-first.
- **Complete uninstaller** (`lib/uninstall.sh`): `--uninstall <App>` removes the
  app + leftovers; `--find-orphans` finds leftovers from long-removed apps.
- **Disk tools** (`lib/disk.sh`): `--disk [path]` size browser;
  `--snapshots` lists APFS local snapshots + purgeable space, thins on confirm.
- **Startup manager** (`lib/startup.sh`): one view of login items +
  LaunchAgents/Daemons; disable is reversible (plist → Trash), whitelisted
  services locked.
- **Language pruner** (`lib/languages.sh`): `--prune-languages` strips
  non-English `.lproj` (report first, opt-in). Architecture stripping is
  disabled by design.
- **Maintenance runner** (`lib/maintenance.sh`): `--maintenance` runs periodic
  scripts, disk verify, and DB rebuilds — each step confirmed, never scheduled.
- **Monitor upgrades**: BlueBubbles auto-restart (max 2 tries per outage, then
  notify-only — never a loop), lid-close guard check, purgeable space in disk
  warnings.
- **Services dashboard**: `--services` now shows per-service uptime and
  restart-count since boot.
- **Bug fix**: the v1.0.0 `vm.swapusage` parser grabbed the word "used" instead
  of the number, crashing the monitor under `set -u` — fixed in the monitor
  and `opt_memory_pressure`.

## v1.0.0 — original feature set (kept)

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
