#!/bin/sh

# Simon Prometheus Exporter for OpenWrt
# HTTP server that serves metrics in Prometheus format

EXPORTER_NAME="simon-exporter"
PID_FILE="/var/run/${EXPORTER_NAME}.pid"
DATA_DIR="/tmp/simon-metrics"
LOG_FILE="/var/log/${EXPORTER_NAME}.log"
HTTP_PORT="${SIMON_PORT:-9184}"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$EXPORTER_NAME] $1" >> "$LOG_FILE"
}

# Signal handlers
cleanup() {
    log "Exporter stopping..."
    rm -f "$PID_FILE"
    exit 0
}

trap cleanup TERM INT

# Function to serve HTTP response
serve_metrics() {
    local metrics_file="$DATA_DIR/metrics.prom"
    
    # HTTP headers
    printf "HTTP/1.1 200 OK\r\n"
    printf "Content-Type: text/plain; version=0.0.4; charset=utf-8\r\n"
    printf "Connection: close\r\n"
    printf "Access-Control-Allow-Origin: *\r\n"
    printf "\r\n"
    
    # Prometheus metrics headers
    printf "# HELP simon_cpu_cpu_seconds_total CPU time in seconds by mode\n"
    printf "# TYPE simon_cpu_cpu_seconds_total counter\n"
    printf "\n"
    printf "# HELP simon_memory_total_bytes Total physical memory in bytes\n"
    printf "# TYPE simon_memory_total_bytes gauge\n"
    printf "# HELP simon_memory_free_bytes Free physical memory in bytes\n"
    printf "# TYPE simon_memory_free_bytes gauge\n"
    printf "# HELP simon_memory_available_bytes Available physical memory in bytes\n"
    printf "# TYPE simon_memory_available_bytes gauge\n"
    printf "# HELP simon_memory_used_bytes Used physical memory in bytes\n"
    printf "# TYPE simon_memory_used_bytes gauge\n"
    printf "# HELP simon_memory_buffers_bytes Buffer memory in bytes\n"
    printf "# TYPE simon_memory_buffers_bytes gauge\n"
    printf "# HELP simon_memory_cached_bytes Cached memory in bytes\n"
    printf "# TYPE simon_memory_cached_bytes gauge\n"
    printf "\n"
    printf "# HELP simon_temp_celsius Temperature in Celsius\n"
    printf "# TYPE simon_temp_celsius gauge\n"
    printf "\n"
    printf "# HELP simon_tx_bytes_total Total bytes transmitted by device (internet + local)\n"
    printf "# TYPE simon_tx_bytes_total counter\n"
    printf "# HELP simon_rx_bytes_total Total bytes received by device (internet + local)\n"
    printf "# TYPE simon_rx_bytes_total counter\n"
    printf "# HELP simon_local_tx_bytes_total Bytes transmitted to specific local destination\n"
    printf "# TYPE simon_local_tx_bytes_total counter\n"
    printf "# HELP simon_local_rx_bytes_total Bytes received from specific local source\n"
    printf "# TYPE simon_local_rx_bytes_total counter\n"
    printf "\n"
    
    # Serve metrics if file exists
    if [ -f "$metrics_file" ]; then
        grep -v "^#" "$metrics_file" 2>/dev/null || {
            printf "# No metrics available\n"
            printf "simon_exporter_up 0\n"
        }
    else
        printf "# Metrics file not found: %s\n" "$metrics_file"
        printf "simon_exporter_up 0\n"
    fi
    
    # Add exporter status
    printf "\n"
    printf "# HELP simon_exporter_up Exporter status\n"
    printf "# TYPE simon_exporter_up gauge\n"
    printf "simon_exporter_up 1\n"
    printf "simon_exporter_last_scrape %s\n" "$(date +%s)"
}

# Function to handle HTTP request
handle_http_request() {
    local request_line=""
    
    # Read the request line
    read -r request_line
    log "Request: $request_line"
    
    # Consume remaining headers
    while read -r header && [ -n "$header" ] && [ "$header" != "$(printf '\r')" ]; do
        :
    done
    
    # Serve the metrics
    serve_metrics
}

# HTTP server using netcat (busybox version)
run_http_server_netcat() {
    log "Starting HTTP server with netcat on port $HTTP_PORT"
    log "WARNING: netcat on busybox only binds to localhost - install socat for network access"
    
    while true; do
        # Handle one request at a time
        {
            handle_http_request
        } | nc -l -p "$HTTP_PORT" 2>/dev/null
        
        # Small delay to prevent rapid cycling
        sleep 1
    done
}

# HTTP server using socat
run_http_server_socat() {
    log "Starting HTTP server with socat on port $HTTP_PORT"
    
    socat TCP-LISTEN:$HTTP_PORT,bind=0.0.0.0,reuseaddr,fork SYSTEM:"$0 handle_request_internal"
}

# Internal request handler for socat
handle_request_internal() {
    handle_http_request 2>/dev/null
}

# Determine best HTTP server method
detect_server_method() {
    # Prefer socat over netcat since netcat on busybox can't bind to all interfaces
    if command -v socat >/dev/null 2>&1; then
        echo "socat"
        return 0
    fi
    
    # Fallback to netcat (but warn about localhost-only binding)
    if command -v nc >/dev/null 2>&1; then
        # Test if netcat supports -l -p flags
        if echo "test" | nc -l -p 65432 -w 1 2>/dev/null &
        then
            sleep 1
            kill $! 2>/dev/null
            echo "netcat"
            return 0
        fi
    fi
    
    echo "none"
    return 1
}

# Main HTTP server function
run_http_server() {
    local server_method=$(detect_server_method)
    
    case "$server_method" in
        "netcat")
            run_http_server_netcat
            ;;
        "socat")
            run_http_server_socat
            ;;
        "none")
            log "ERROR: No suitable HTTP server method available"
            echo "ERROR: Neither netcat nor socat is available or working"
            exit 1
            ;;
        *)
            log "ERROR: Unknown server method: $server_method"
            exit 1
            ;;
    esac
}

# Function to start exporter
start_exporter() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Exporter already running (PID: $pid)"
            return 1
        else
            rm -f "$PID_FILE"
        fi
    fi
    
    # Check if port is available
    if netstat -ln 2>/dev/null | grep -q ":$HTTP_PORT "; then
        echo "ERROR: Port $HTTP_PORT is already in use"
        return 1
    fi
    
    # Verify server capability
    local server_method=$(detect_server_method)
    if [ "$server_method" = "none" ]; then
        echo "ERROR: No HTTP server capability detected"
        echo "Please install either 'netcat' or 'socat'"
        return 1
    fi
    
    echo "Starting $EXPORTER_NAME on port $HTTP_PORT using $server_method..."
    
    if [ "$1" = "handle_request_internal" ]; then
        handle_request_internal
    else
        run_http_server &
        echo $! > "$PID_FILE"
        log "Exporter started with PID: $! on port $HTTP_PORT using $server_method"
        echo "Exporter started successfully on http://localhost:$HTTP_PORT/metrics"
    fi
}

# Function to stop exporter
stop_exporter() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping $EXPORTER_NAME (PID: $pid)..."
            kill -TERM "$pid"
            
            # Wait for process to stop
            local wait_count=0
            while kill -0 "$pid" 2>/dev/null && [ $wait_count -lt 10 ]; do
                sleep 1
                wait_count=$((wait_count + 1))
            done
            
            if kill -0 "$pid" 2>/dev/null; then
                echo "Force killing exporter..."
                kill -KILL "$pid"
            fi
            
            rm -f "$PID_FILE"
            log "Exporter stopped"
            echo "Exporter stopped successfully"
        else
            echo "Exporter not running"
            rm -f "$PID_FILE"
        fi
    else
        echo "Exporter not running"
    fi
}

# Function to check exporter status
status_exporter() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "$EXPORTER_NAME is running (PID: $pid)"
            echo "HTTP endpoint: http://localhost:$HTTP_PORT/metrics"
            echo "Server method: $(detect_server_method)"
        else
            echo "$EXPORTER_NAME is not running (stale PID file)"
            rm -f "$PID_FILE"
        fi
    else
        echo "$EXPORTER_NAME is not running"
    fi
}

# Function to test metrics
test_metrics() {
    echo "Testing metrics endpoint..."
    echo "Server detection: $(detect_server_method)"
    echo ""
    serve_metrics
}

# Main script logic
case "$1" in
    start)
        start_exporter
        ;;
    stop)
        stop_exporter
        ;;
    restart)
        stop_exporter
        sleep 2
        start_exporter
        ;;
    status)
        status_exporter
        ;;
    test)
        test_metrics "$2"
        ;;
    daemon)
        # Direct daemon mode (for procd)
        run_http_server
        ;;
    handle_request_internal)
        handle_request_internal
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|test|daemon}"
        echo "  start   - Start the Prometheus exporter"
        echo "  stop    - Stop the Prometheus exporter"
        echo "  restart - Restart the Prometheus exporter"
        echo "  status  - Check exporter status"
        echo "  test    - Test metrics output"
        echo "  daemon  - Run in daemon mode (direct execution)"
        echo ""
        echo "Environment variables:"
        echo "  SIMON_PORT - HTTP port (default: 9184)"
        exit 1
        ;;
esac
