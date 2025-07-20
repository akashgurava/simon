#!/bin/sh

# System Monitor Daemon for OpenWrt
# Collects CPU, Memory, and Temperature metrics at various intervals
# Author: Generated for OpenWrt monitoring

DAEMON_NAME="simon-monitor"
PID_FILE="/var/run/${DAEMON_NAME}.pid"
DATA_DIR="/tmp/simon-metrics"
LOG_FILE="/var/log/${DAEMON_NAME}.log"

# Metric intervals (in seconds)
INTERVALS="1 5 10 15 30"

# Create data directory
mkdir -p "$DATA_DIR"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$DAEMON_NAME] $1" >> "$LOG_FILE"
}

# Signal handlers
cleanup() {
    log "Daemon stopping..."
    rm -f "$PID_FILE"
    rm -rf "$DATA_DIR"
    exit 0
}

trap cleanup TERM INT

# Function to get CPU stats
get_cpu_stats() {
    grep "^cpu[0-9]" /proc/stat | while IFS=' ' read -r core user nice system idle iowait irq softirq steal guest guest_nice; do
        # Handle missing fields
        user=${user:-0}; nice=${nice:-0}; system=${system:-0}; idle=${idle:-0}
        iowait=${iowait:-0}; irq=${irq:-0}; softirq=${softirq:-0}; steal=${steal:-0}
        guest=${guest:-0}; guest_nice=${guest_nice:-0}
        
        # Calculate totals
        total=$((user + nice + system + idle + iowait + irq + softirq + steal))
        active=$((user + nice + system + iowait + irq + softirq + steal))
        
        echo "$core $total $active"
    done
}

# Function to calculate CPU usage percentage
calculate_cpu_usage() {
    local core="$1"
    local prev_total="$2"
    local prev_active="$3"
    local curr_total="$4"
    local curr_active="$5"
    
    local total_diff=$((curr_total - prev_total))
    local active_diff=$((curr_active - prev_active))
    
    if [ "$total_diff" -gt 0 ]; then
        # Use awk for floating point calculation
        awk "BEGIN { printf \"%.2f\", ($active_diff * 100.0) / $total_diff }"
    else
        echo "0.00"
    fi
}

# Function to get memory stats
get_memory_stats() {
    local mem_total mem_free mem_available mem_buffers mem_cached mem_used
    
    mem_total=$(awk '/MemTotal/ { print $2 * 1024 }' /proc/meminfo)
    mem_free=$(awk '/MemFree/ { print $2 * 1024 }' /proc/meminfo)
    mem_available=$(awk '/MemAvailable/ { print $2 * 1024 }' /proc/meminfo)
    mem_buffers=$(awk '/Buffers/ { print $2 * 1024 }' /proc/meminfo)
    mem_cached=$(awk '/^Cached/ { print $2 * 1024 }' /proc/meminfo)
    
    # Handle missing MemAvailable (older kernels)
    mem_available=${mem_available:-$mem_free}
    mem_buffers=${mem_buffers:-0}
    mem_cached=${mem_cached:-0}
    
    # Calculate used memory
    mem_used=$((mem_total - mem_free - mem_buffers - mem_cached))
    
    echo "mem_total_bytes $mem_total"
    echo "mem_free_bytes $mem_free"
    echo "mem_available_bytes $mem_available"
    echo "mem_used_bytes $mem_used"
    echo "mem_buffers_bytes $mem_buffers"
    echo "mem_cached_bytes $mem_cached"
}

# Function to get temperature stats
get_temperature_stats() {
    local temp_data=""
    
    # Find temperature files and process them
    {
        find /sys -name "temp" -type f 2>/dev/null
        find /sys -name "*temp*_input" -type f 2>/dev/null
    } | while read temp_file; do
        if [ -f "$temp_file" ]; then
            raw_temp=$(cat "$temp_file" 2>/dev/null)
            if [ -n "$raw_temp" ] && [ "$raw_temp" -gt 0 ]; then
                # Determine temperature scaling
                if [ "$raw_temp" -gt 1000 ]; then
                    temp=$(awk "BEGIN {printf \"%.1f\", $raw_temp / 1000}")
                else
                    temp="$raw_temp"
                fi
                
                # Create sensor name from path
                sensor_name=$(echo "$temp_file" | sed 's|/sys/||' | sed 's|/|_|g' | sed 's|_temp$\|_temp.*_input$||')
                
                echo "temp_celsius{sensor=\"$sensor_name\"} $temp"
            fi
        fi
    done
}

# Function to write metrics to file
write_metrics() {
    local interval="$1"
    local timestamp="$2"
    local metrics_file="$DATA_DIR/metrics_${interval}s.prom"
    
    # Write CPU metrics
    if [ -f "$DATA_DIR/cpu_current" ] && [ -f "$DATA_DIR/cpu_previous" ]; then
        while IFS=' ' read -r core curr_total curr_active; do
            # Find corresponding previous values
            prev_line=$(grep "^$core " "$DATA_DIR/cpu_previous" 2>/dev/null)
            if [ -n "$prev_line" ]; then
                prev_total=$(echo "$prev_line" | cut -d' ' -f2)
                prev_active=$(echo "$prev_line" | cut -d' ' -f3)
                
                # Calculate usage percentage
                usage=$(calculate_cpu_usage "$core" "$prev_total" "$prev_active" "$curr_total" "$curr_active")
                core_num=$(echo "$core" | sed 's/cpu//')
                
                echo "simon_cpu_usage_percentage{core=\"$core_num\"} $usage" >> "$metrics_file.tmp"
            fi
        done < "$DATA_DIR/cpu_current"
    fi
    
    # Write memory metrics
    get_memory_stats | while read metric_name value; do
        prometheus_name=$(echo "$metric_name" | sed 's/mem_/simon_memory_/')
        echo "$prometheus_name $value" >> "$metrics_file.tmp"
    done
    
    # Write temperature metrics
    get_temperature_stats | while read metric_line; do
        echo "simon_$metric_line" >> "$metrics_file.tmp"
    done
    
    # Add timestamp and move to final location
    echo "# Generated at: $(date)" > "$metrics_file"
    echo "# Interval: ${interval}s" >> "$metrics_file"
    if [ -f "$metrics_file.tmp" ]; then
        cat "$metrics_file.tmp" >> "$metrics_file"
        rm -f "$metrics_file.tmp"
    fi
}

# Main daemon function
run_daemon() {
    log "Starting daemon..."
    
    # Initialize CPU stats
    get_cpu_stats > "$DATA_DIR/cpu_previous"
    
    local counter=0
    
    while true; do
        counter=$((counter + 1))
        
        # Get current CPU stats
        get_cpu_stats > "$DATA_DIR/cpu_current"
        
        # Check which intervals to write
        for interval in $INTERVALS; do
            if [ $((counter % interval)) -eq 0 ]; then
                write_metrics "$interval" "$(date +%s)"
            fi
        done
        
        # Copy current to previous for next iteration
        cp "$DATA_DIR/cpu_current" "$DATA_DIR/cpu_previous"
        
        sleep 1
    done
}

# Function to start daemon
start_daemon() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Daemon already running (PID: $pid)"
            return 1
        else
            rm -f "$PID_FILE"
        fi
    fi
    
    echo "Starting $DAEMON_NAME..."
    run_daemon &
    echo $! > "$PID_FILE"
    log "Daemon started with PID: $!"
    echo "Daemon started successfully"
}

# Function to stop daemon
stop_daemon() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping $DAEMON_NAME (PID: $pid)..."
            kill -TERM "$pid"
            
            # Wait for process to stop
            local wait_count=0
            while kill -0 "$pid" 2>/dev/null && [ $wait_count -lt 10 ]; do
                sleep 1
                wait_count=$((wait_count + 1))
            done
            
            if kill -0 "$pid" 2>/dev/null; then
                echo "Force killing daemon..."
                kill -KILL "$pid"
            fi
            
            rm -f "$PID_FILE"
            log "Daemon stopped"
            echo "Daemon stopped successfully"
        else
            echo "Daemon not running"
            rm -f "$PID_FILE"
        fi
    else
        echo "Daemon not running"
    fi
}

# Function to check daemon status
status_daemon() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "$DAEMON_NAME is running (PID: $pid)"
            echo "Data directory: $DATA_DIR"
            echo "Available metric files:"
            ls -la "$DATA_DIR"/metrics_*.prom 2>/dev/null || echo "  No metric files found"
        else
            echo "$DAEMON_NAME is not running (stale PID file)"
            rm -f "$PID_FILE"
        fi
    else
        echo "$DAEMON_NAME is not running"
    fi
}

# Main script logic
case "$1" in
    start)
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    restart)
        stop_daemon
        sleep 2
        start_daemon
        ;;
    status)
        status_daemon
        ;;
    daemon)
        # Direct daemon mode (for procd)
        run_daemon
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|daemon}"
        echo "  start   - Start the monitoring daemon"
        echo "  stop    - Stop the monitoring daemon"
        echo "  restart - Restart the monitoring daemon"
        echo "  status  - Check daemon status"
        echo "  daemon  - Run in daemon mode (direct execution)"
        exit 1
        ;;
esac
