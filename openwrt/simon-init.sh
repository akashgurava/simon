#!/bin/sh /etc/rc.common

# Simon System Monitor - OpenWrt Init Script
# Place this file in /etc/init.d/simon-monitor
# Enable with: /etc/init.d/simon-monitor enable

START=99
STOP=10

USE_PROCD=1

PROG_MONITOR="/usr/bin/simon-monitor"
PROG_EXPORTER="/usr/bin/simon-exporter"

# Configuration
HTTP_PORT=9090
DATA_DIR="/tmp/simon-metrics"

start_service() {
    # Ensure programs exist
    if [ ! -f "$PROG_MONITOR" ]; then
        echo "ERROR: Monitor daemon not found at $PROG_MONITOR"
        return 1
    fi
    
    if [ ! -f "$PROG_EXPORTER" ]; then
        echo "ERROR: Prometheus exporter not found at $PROG_EXPORTER"
        return 1
    fi
    
    # Create data directory
    mkdir -p "$DATA_DIR"
    
    # Start monitoring daemon
    procd_open_instance monitor
    procd_set_param command "$PROG_MONITOR" daemon
    procd_set_param pidfile /var/run/simon-monitor.pid
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn ${respawn_threshold:-3600} ${respawn_timeout:-5} ${respawn_retry:-5}
    procd_close_instance
    
    # Wait a moment for monitor to initialize
    sleep 2
    
    # Start Prometheus exporter
    procd_open_instance exporter
    procd_set_param command "$PROG_EXPORTER" daemon
    procd_set_param pidfile /var/run/simon-exporter.pid
    procd_set_param env SIMON_PORT="$HTTP_PORT"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn ${respawn_threshold:-3600} ${respawn_timeout:-5} ${respawn_retry:-5}
    procd_close_instance
    
    echo "Simon monitoring system started on port $HTTP_PORT"
}

stop_service() {
    echo "Stopping Simon monitoring system..."
    
    # Stop services using the scripts
    "$PROG_EXPORTER" stop 2>/dev/null || true
    "$PROG_MONITOR" stop 2>/dev/null || true
    
    # Cleanup
    rm -rf "$DATA_DIR"
    
    echo "Simon monitoring system stopped"
}

reload_service() {
    stop
    start
}

status() {
    echo "=== Simon Monitor Status ==="
    "$PROG_MONITOR" status
    echo ""
    echo "=== Simon Exporter Status ==="
    "$PROG_EXPORTER" status
}
