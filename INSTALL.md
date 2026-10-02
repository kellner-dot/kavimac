# KaviGuard Installation

## 1. Download

Get `kaviguard-v1.1.1.tar.gz` from Google Drive (link from Kavi).

## 2. Extract

Double-click the `.tar.gz` in Finder, or:

```bash
cd ~/Downloads
tar -xzf kaviguard-v1.1.1.tar.gz
```

## 3. Install

```bash
cd ~/Downloads/kaviguard
sudo bash install.sh
```

The installer:
- Copies everything to `/opt/kaviguard/`
- Makes scripts executable
- Installs the monitor LaunchAgent (`com.seth.kaviguard`)
- Creates `/opt/kaviguard/vpn/` for future KaviVPN config

## 4. Run a tune-up

```bash
# Full tune-up
/opt/kaviguard/kavimac.sh

# Or individual parts
/opt/kaviguard/kavimac.sh --cleanup
/opt/kaviguard/kavimac.sh --optimize
/opt/kaviguard/kavimac.sh --health
/opt/kaviguard/kavimac.sh --services
/opt/kaviguard/kavimac.sh --vpn-status
```

For system cache cleanup, run with sudo:

```bash
sudo /opt/kaviguard/kavimac.sh --cleanup
```

## 5. Monitor

The background monitor runs every 15 minutes automatically after install.
Logs: `/tmp/kavimac-monitor.log`

Check it's loaded:

```bash
launchctl list | grep kaviguard
```

## KaviVPN (when server is deployed)

1. Copy your client config from the Oracle VM:
   ```bash
   sudo cp kavivpn.conf /opt/kaviguard/vpn/
   ```
2. Install WireGuard tools:
   ```bash
   brew install wireguard-tools
   ```
3. Connect:
   ```bash
   source /opt/kaviguard/lib/vpn.sh && vpn_connect
   ```
4. Auto-connect on boot:
   ```bash
   source /opt/kaviguard/lib/vpn.sh && vpn_autoconnect on
   ```
