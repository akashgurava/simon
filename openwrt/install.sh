#!/bin/sh

# Simon System Monitor Installation Script for OpenWrt
# This script installs and configures the monitoring system

set -e

INSTALL_DIR="/usr/bin"
INIT_DIR="/etc/init.d"
LOG_DIR="/var/log"

echo "=== Simon System Monitor Installation ==="
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Function to install file with permissions
install_file() {
    local src_file="$1"
    local dst_file="$2"
    local permissions="$3"
    
    if [ ! -f "$src_file" ]; then
        echo "ERROR: Source file $src_file not found"
        return 1
    fi
    
    echo "Installing $dst_file..."
    cp "$src_file" "$dst_file"
    chmod "$permissions" "$dst_file"
    
    if [ -f "$dst_file" ]; then
        echo "  ✓ Installed successfully"
    else
        echo "  ✗ Installation failed"
        return 1
    fi
}

# Install main scripts
echo "1. Installing main scripts..."
if [ -f "./simon-monitor.sh" ]; then
    install_file "./simon-monitor.sh" "$INSTALL_DIR/simon-monitor" "755"
else
    echo "ERROR: simon-monitor.sh not found in current directory"
    echo "Please ensure all script files are in the current directory:"
    echo "  - simon-monitor.sh (main daemon)"
    echo "  - simon-exporter.sh (prometheus exporter)"
    echo "  - simon-init.sh (init script)"
    exit 1
fi

if [ -f "./simon-exporter.sh" ]; then
    install_file "./simon-exporter.sh" "$INSTALL_DIR/simon-exporter" "755"
else
    echo "ERROR: simon-exporter.sh not found in current directory"
    exit 1
fi

# Install init script
echo ""
echo "2. Installing init script..."
if [ -f "./simon-init.sh" ]; then
    install_file "./simon-init.sh" "$INIT_DIR/simon-monitor" "755"
else
    echo "ERROR: simon-init.sh not found in current directory"
    exit 1
fi

# Create log directory
echo ""
echo "3. Setting up directories..."
mkdir -p "$LOG_DIR"
mkdir -p "/tmp/simon-metrics"
echo "  ✓ Created log directory: $LOG_DIR"
echo "  ✓ Created metrics directory: /tmp/simon-metrics"

# Test dependencies
echo ""
echo "4. Checking dependencies..."

# Check for required tools
check_tool() {
    local tool="$1"
    local required="$2"
    
    if command -v "$tool" >/dev/null 2>&1; then
        echo "  ✓ $tool found"
        return 0
    else
        if [ "$required" = "required" ]; then
            echo "  ✗ $tool not found (REQUIRED)"
            return 1
        else
            echo "  ! $tool not found (optional)"
            return 0
        fi
    fi
}

deps_ok=true
check_tool "awk" "required" || deps_ok=false
check_tool "grep" "required" || deps_ok=false
check_tool "find" "required" || deps_ok=false
check_tool "printf" "required" || deps_ok=false
check_tool "netstat" "optional"

# Enhanced HTTP server capability testing
echo ""
echo "5. Testing HTTP server capabilities..."

test_netcat() {
    if command -v nc >/dev/null 2>&1; then
        echo "  ✓ netcat (nc) found"
        
        # Test if netcat can bind to a port (quick test)
        local test_port=65432
        if echo "test" | timeout 2 nc -l -p $test_port 2>/dev/null &
        then
            local nc_pid=$!
            sleep 0.5
            kill $nc_pid 2>/dev/null
            wait $nc_pid 2>/dev/null
            echo "  ✓ netcat port binding test passed"
            return 0
        else
            echo "  ! netcat found but port binding test failed"
            return 1
        fi
    else
        echo "  ! netcat (nc) not found"
        return 1
    fi
}

test_socat() {
    if command -v socat >/dev/null 2>&1; then
        echo "  ✓ socat found"
        
        # Test basic socat functionality
        if timeout 2 socat -h >/dev/null 2>&1; then
            echo "  ✓ socat functionality test passed"
            return 0
        else
            echo "  ! socat found but functionality test failed"
            return 1
        fi
    else
        echo "  ! socat not found"
        return 1
    fi
}

# Test HTTP server options
http_server_available=false

if test_netcat; then
    http_server_available=true
    echo "  ✓ HTTP server capability: netcat"
elif test_socat; then
    http_server_available=true
    echo "  ✓ HTTP server capability: socat"
else
    echo "  ✗ No HTTP server capability found"
    echo "    Please install either:"
    echo "    - netcat: opkg install netcat"
    echo "    - socat: opkg install socat"
    deps_ok=false
fi

# Test timeout command (useful for server testing)
if command -v timeout >/dev/null 2>&1; then
    echo "  ✓ timeout command available"
else
    echo "  ! timeout command not found (optional, improves reliability)"
fi

if [ "$deps_ok" = "false" ]; then
    echo ""
    echo "ERROR: Missing required dependencies. Please install:"
    echo "  Basic tools:"
    echo "    opkg install coreutils"
    echo "    # OR"
    echo "    opkg install busybox"
    echo ""
    echo "  HTTP server (choose one):"
    echo "    opkg install netcat"
    echo "    # OR"
    echo "    opkg install socat"
    exit 1
fi

# Test CPU stats
echo ""
echo "6. Testing system compatibility..."
if [ -f "/proc/stat" ] && grep -q "^cpu[0-9]" /proc/stat; then
    cpu_cores=$(grep "^cpu[0-9]" /proc/stat | wc -l)
    echo "  ✓ CPU stats available ($cpu_cores cores detected)"
else
    echo "  ✗ CPU stats not available in /proc/stat"
    deps_ok=false
fi

# Test memory stats
if [ -f "/proc/meminfo" ] && grep -q "MemTotal" /proc/meminfo; then
    mem_total=$(awk '/MemTotal/ { print $2 }' /proc/meminfo)
    echo "  ✓ Memory stats available (${mem_total}KB total)"
else
    echo "  ✗ Memory stats not available in /proc/meminfo"
    deps_ok=false
fi

# Test temperature sensors
temp_sensors=$(find /sys -name "temp" -o -name "*temp*_input" 2>/dev/null | wc -l)
if [ "$temp_sensors" -gt 0 ]; then
    echo "  ✓ Temperature sensors found ($temp_sensors sensors)"
    echo "    Sample sensors:"
    find /sys -name "temp" -o -name "*temp*_input" 2>/dev/null | head -3 | while read sensor; do
        echo "      $sensor"
    done
else
    echo "  ! No temperature sensors found (optional)"
fi

if [ "$deps_ok" = "false" ]; then
    echo ""
    echo "ERROR: System compatibility issues found"
    exit 1
fi

# Test port availability
echo ""
echo "7. Testing network configuration..."
HTTP_PORT=9090

if command -v netstat >/dev/null 2>&1; then
    if netstat -ln 2>/dev/null | grep -q ":$HTTP_PORT "; then
        echo "  ! WARNING: Port $HTTP_PORT appears to be in use"
        echo "    You may need to change the port using SIMON_PORT environment variable"
    else
        echo "  ✓ Port $HTTP_PORT is available"
    fi
else
    echo "  ! Cannot check port availability (netstat not found)"
fi

# Configure service
echo ""
echo "8. Configuring service..."

# Enable the service
if /etc/init.d/simon-monitor enable 2>/dev/null; then
    echo "  ✓ Service enabled for automatic startup"
else
    echo "  ! Could not enable service for automatic startup"
fi

# Start the service
echo ""
echo "9. Starting services..."
if /etc/init.d/simon-monitor start; then
    echo "  ✓ Simon monitoring system started successfully"
    
    # Wait for startup
    echo "  Waiting for services to initialize..."
    sleep 5
    
    # Check if services are running
    if /usr/bin/simon-monitor status | grep -q "running"; then
        echo "  ✓ Monitor daemon is running"
    else
        echo "  ! Monitor daemon may not be running properly"
        echo "    Check logs: tail /var/log/simon-monitor.log"
    fi
    
    if /usr/bin/simon-exporter status | grep -q "running"; then
        echo "  ✓ Prometheus exporter is running"
        
        # Test HTTP endpoint
        echo "  Testing HTTP endpoint..."
        if command -v curl >/dev/null 2>&1; then
            if curl -s http://localhost:$HTTP_PORT/metrics | grep -q "simon_exporter_up"; then
                echo "  ✓ HTTP endpoint is responding correctly"
            else
                echo "  ! HTTP endpoint test failed"
            fi
        elif command -v wget >/dev/null 2>&1; then
            if wget -qO- http://localhost:$HTTP_PORT/metrics | grep -q "simon_exporter_up"; then
                echo "  ✓ HTTP endpoint is responding correctly"
            else
                echo "  ! HTTP endpoint test failed"
            fi
        else
            echo "  ! Cannot test HTTP endpoint (curl/wget not available)"
        fi
    else
        echo "  ! Prometheus exporter may not be running properly"
        echo "    Check logs: tail /var/log/simon-exporter.log"
    fi
else
    echo "  ✗ Failed to start services"
    echo "    Check system logs: logread | grep simon"
fi

# Display final information
echo ""
echo "=== Installation Complete ==="
echo ""
echo "Services installed:"
echo "  • Monitor daemon: /usr/bin/simon-monitor"
echo "  • Prometheus exporter: /usr/bin/simon-exporter"
echo "  • Init script: /etc/init.d/simon-monitor"
echo ""
echo "Configuration:"
echo "  • HTTP Port: $HTTP_PORT"
echo "  • Metrics directory: /tmp/simon-metrics"
echo "  • Log files: /var/log/simon-*.log"
if [ "$http_server_available" = "true" ]; then
    echo "  • HTTP Server: Available"
else
    echo "  • HTTP Server: NOT AVAILABLE - Install netcat or socat"
fi
echo ""
echo "Usage:"
echo "  • Manual control: /etc/init.d/simon-monitor {start|stop|restart|status}"
echo "  • Prometheus endpoint: http://$(uci get network.lan.ipaddr 2>/dev/null || echo "your-ip"):$HTTP_PORT/metrics"
echo "  • Available intervals: ?interval=1,5,10,15,30 (seconds)"
echo ""
echo "Examples:"
echo "  # Check status"
echo "  /etc/init.d/simon-monitor status"
echo ""
echo "  # View metrics"
echo "  curl 'http://localhost:$HTTP_PORT/metrics'"
echo "  curl 'http://localhost:$HTTP_PORT/metrics?interval=30'"
echo ""
echo "  # View raw metric files"
echo "  ls /tmp/simon-metrics/"
echo "  cat /tmp/simon-metrics/metrics_1s.prom"
echo ""

# Test the installation
echo "Testing installation..."
echo "Waiting 10 seconds for metrics generation..."
sleep 10

if [ -f "/tmp/simon-metrics/metrics_1s.prom" ]; then
    echo "✓ Metrics file created successfully"
    echo ""
    echo "Sample metrics:"
    head -20 "/tmp/simon-metrics/metrics_1s.prom" | grep -E "(simon_cpu_usage|simon_memory)" | head -5
    echo "..."
else
    echo "! Metrics file not found - check logs:"
    echo "  tail /var/log/simon-monitor.log"
    echo "  tail /var/log/simon-exporter.log"
fi

# Final HTTP test
echo ""
echo "Final HTTP server test..."
if command -v curl >/dev/null 2>&1; then
    if timeout 5 curl -s "http://localhost:$HTTP_PORT/metrics?interval=1" | head -10; then
        echo ""
        echo "✓ HTTP server is working correctly"
    else
        echo "✗ HTTP server test failed"
        echo "Troubleshooting steps:"
        echo "1. Check exporter status: /usr/bin/simon-exporter status"
        echo "2. Check logs: tail /var/log/simon-exporter.log"
        echo "3. Test manually: /usr/bin/simon-exporter test"
    fi
else
    echo "Install curl to test HTTP endpoint: opkg install curl"
fi

echo ""
echo "🎉 Simon System Monitor installation completed!"
echo ""
echo "Next steps:"
echo "1. Configure your Prometheus server to scrape: http://your-openwrt-ip:$HTTP_PORT/metrics"
echo "2. Set up Grafana dashboards using the simon_* metrics"
echo "3. Monitor the logs for any issues"
echo ""
echo "For troubleshooting, check:"
echo "  • Service status: /etc/init.d/simon-monitor status"
echo "  • Monitor logs: tail -f /var/log/simon-monitor.log"
echo "  • Exporter logs: tail -f /var/log/simon-exporter.log"
echo "  • Test exporter: /usr/bin/simon-exporter test"
echo "  • Server capability: /usr/bin/simon-exporter status"
echo ""
