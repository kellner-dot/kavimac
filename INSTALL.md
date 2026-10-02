# KaviMac Installation

## 1. Download

Get `kavimac-v1.0.0.tar.gz` from Google Drive (link from Kavi).

## 2. Extract

Double-click the `.tar.gz` in Finder, or:

```bash
cd ~/Downloads
tar -xzf kavimac-v1.0.0.tar.gz
```

## 3. Install

```bash
cd ~/Downloads/kavimac
sudo bash install.sh
```

The installer:
- Copies everything to `/opt/kavimac/`
- Makes scripts executable
- Installs the monitor LaunchAgent (`com.seth.kavimac`)
- Creates `/opt/kavimac/vpn/` for future KaviVPN config

## 4. Run a tune-up

```bash
# Full tune-up
/opt/kavimac/kavimac.sh

# Or individual parts
/opt/kavimac/kavimac.sh --cleanup
/opt/kavimac/kavimac.sh --optimize
/opt/kavimac/kavimac.sh --health
/opt/kavimac/kavimac.sh --services
/opt/kavimac/kavimac.sh --vpn-status
```

For system cache cleanup, run with sudo:

```bash
sudo /opt/kavimac/kavimac.sh --cleanup
```

## 5. Monitor

The background monitor runs every 15 minutes automatically after install.
Logs: `/tmp/kavimac-monitor.log`

Check it's loaded:

```bash
launchctl list | grep kavimac
```

## KaviVPN (when server is deployed)

1. Copy your client config from the Oracle VM:
   ```bash
   sudo cp kavivpn.conf /opt/kavimac/vpn/
   ```
2. Install WireGuard tools:
   ```bash
   brew install wireguard-tools
   ```
3. Connect:
   ```bash
   source /opt/kavimac/lib/vpn.sh && vpn_connect
   ```
4. Auto-connect on boot:
   ```bash
   source /opt/kavimac/lib/vpn.sh && vpn_autoconnect on
   ```
