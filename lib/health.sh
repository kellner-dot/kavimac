#!/bin/bash
#===============================================================================
# lib/health.sh — KaviGuard health check functions
# Reports CPU, memory, disk, battery, network. No changes made.
#===============================================================================

health_cpu() {
    # Overall CPU idle -> usage
    local cpu_line usage
    cpu_line=$(top -l 1 -n 0 2>/dev/null | grep "CPU usage")
    # "CPU usage: 12.34% user, 5.67% sys, 81.99% idle"
    usage=$(echo "$cpu_line" | awk -F'[:,%]' '{print 100 - $8}' 2>/dev/null)
    usage=${usage:-?}
    local load1 load5
    load1=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
    load5=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $3}')
    echo "CPU: ${usage}% used | load avg ${load1} / ${load5} (1m / 5m)"
}

health_memory() {
    local total used pressure
    total=$(sysctl -n hw.memsize 2>/dev/null)
    total=$((total / 1073741824))
    # vm_stat pages -> MB
    local page_size=16384  # M1 page size
    local free_pages inactive_pages
    free_pages=$(vm_stat 2>/dev/null | awk '/Pages free/{gsub(/\./,"",$3); print $3}')
    inactive_pages=$(vm_stat 2>/dev/null | awk '/Pages inactive/{gsub(/\./,"",$3); print $3}')
    free_pages=${free_pages:-0}; inactive_pages=${inactive_pages:-0}
    local avail_mb=$(( (free_pages + inactive_pages) * page_size / 1048576 ))
    local used_gb
    used_gb=$(echo "scale=1; $total - $avail_mb / 1024" | bc 2>/dev/null)
    # Memory pressure (0-4 scale via vm.memory_pressure if available)
    pressure=$(memory_pressure 2>/dev/null | grep -i "system-wide" | head -1 || echo "")
    echo "Memory: ${used_gb} GB / ${total} GB used"
    [[ -n "$pressure" ]] && echo "  $pressure"
}

health_disk() {
    df -h / 2>/dev/null | awk 'NR==2 {print "Disk (/): " $3 " used of " $2 " (" $5 " full), " $4 " free"}'
    # Also check /System/Volumes/Data if separate
    local data_line
    data_line=$(df -h /System/Volumes/Data 2>/dev/null | awk 'NR==2 {print $3 " used of " $2 " (" $5 "), " $4 " free"}')
    [[ -n "$data_line" && "$data_line" != "$(df -h / 2>/dev/null | awk 'NR==2{print $3" used of "$2" ("$5"), "$4" free"}')" ]] \
        && echo "Disk (Data): $data_line"
}

health_battery() {
    local info maxcap designcap cycles condition
    info=$(ioreg -rn AppleSmartBattery 2>/dev/null)
    maxcap=$(echo "$info" | grep '"MaxCapacity"' | head -1 | awk '{print $3}')
    designcap=$(echo "$info" | grep '"DesignCapacity"' | head -1 | awk '{print $3}')
    cycles=$(echo "$info" | grep '"CycleCount"' | head -1 | awk '{print $3}')
    if [[ -n "$maxcap" && -n "$designcap" && "$designcap" -gt 0 ]]; then
        local health_pct
        health_pct=$(( maxcap * 100 / designcap ))
        echo "Battery: ${health_pct}% health | ${cycles:-?} cycles"
        if (( health_pct < 80 )); then
            echo "  WARNING: battery health below 80% — consider service"
        fi
    else
        echo "Battery: info unavailable"
    fi
    # Charging state
    local charging
    charging=$(pmset -g batt 2>/dev/null | head -1)
    echo "  $charging"
}

health_network() {
    local iface ip
    iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
    ip=$(ipconfig getifaddr "$iface" 2>/dev/null)
    echo "Network: ${iface:-?} (${ip:-no IP})"
    # Quick latency check to a reliable host
    local ping_ms
    ping_ms=$(ping -c 1 -t 2 1.1.1.1 2>/dev/null | awk -F'time=' '/time=/{print $2}' | awk '{print $1}')
    if [[ -n "$ping_ms" ]]; then
        echo "  Latency to 1.1.1.1: ${ping_ms} ms"
    else
        echo "  WARNING: no internet connectivity (ping failed)"
    fi
    # Tailnet status
    if pgrep -x tailscaled >/dev/null 2>&1 || pgrep -x tailscale >/dev/null 2>&1; then
        echo "  Tailscale: running"
    else
        echo "  Tailscale: not running"
    fi
}

health_power() {
    local sleep_val
    sleep_val=$(pmset -g 2>/dev/null | awk '/^ sleep/{print $2}')
    echo "Power: sleep=${sleep_val:-?} (0 = never, good for server use)"
    if [[ "$sleep_val" != "0" ]]; then
        echo "  NOTE: Mac may sleep — BlueBubbles/RVG will drop. Run: sudo pmset -c sleep 0; sudo pmset -b sleep 0"
    fi
}

run_health() {
    echo "=== KaviGuard Health Check ==="
    echo "$(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    health_cpu
    health_memory
    health_disk
    echo ""
    health_battery
    echo ""
    health_network
    echo ""
    health_power
}
