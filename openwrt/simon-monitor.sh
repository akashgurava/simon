#!/bin/sh

# System Monitor Daemon for OpenWrt
# Collects CPU, Memory, and Temperature metrics every second and writes to a file.

DAEMON_NAME="simon-monitor"
PID_FILE="/var/run/${DAEMON_NAME}.pid"
DATA_DIR="/tmp/simon-metrics"
LOG_FILE="/var/log/${DAEMON_NAME}.log"

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
        user=${user:-0}; nice=${nice:-0}; system=${system:-0}; idle=${idle:-0}
        iowait=${iowait:-0}; irq=${irq:-0}; softirq=${softirq:-0}; steal=${steal:-0}
        guest=${guest:-0}; guest_nice=${guest_nice:-0}
        core_num=$(echo "$core" | sed 's/cpu//')
        echo "simon_cpu_cpu_seconds_total{core=\"$core_num\",mode=\"user\"} $user"
        echo "simon_cpu_cpu_seconds_total{core=\"$core_num\",mode=\"nice\"} $nice"
        echo "simon_cpu_cpu_seconds_total{core=\"$core_num\",mode=\"system\"} $system"
        echo "simon_cpu_cpu_seconds_total{core=\"$core_num\",mode=\"idle\"} $idle"
        echo "simon_cpu_cpu_seconds_total{core=\"$core_num\",mode=\"iowait\"} $iowait"
        echo "simon_cpu_cpu_seconds_total{core=\"$core_num\",mode=\"irq\"} $irq"
        echo "simon_cpu_cpu_seconds_total{core=\"$core_num\",mode=\"softirq\"} $softirq"
        echo "simon_cpu_cpu_seconds_total{core=\"$core_num\",mode=\"steal\"} $steal"
        echo "simon_cpu_cpu_seconds_total{core=\"$core_num\",mode=\"guest\"} $guest"
        echo "simon_cpu_cpu_seconds_total{core=\"$core_num\",mode=\"guest_nice\"} $guest_nice"
    done
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

# Get per-IP bandwidth stats with detailed local traffic destination tracking
get_nlbwmon_stats() {
    echo "# Per-IP bandwidth statistics from conntrack with hostnames and tags"
    
    # Create mapping using simple shell commands
    tmp_mapping=$(mktemp)
    
    # Extract all DHCP host entries and build mapping
    uci show dhcp | grep "dhcp\.@host\[" | while IFS='=' read key value; do
        if echo "$key" | grep -q "\.ip$"; then
            section=$(echo "$key" | sed 's/.*\[\([0-9]*\)\]\.ip/\1/')
            ip=$(echo "$value" | tr -d "'")
            
            hostname=$(uci get dhcp.@host[$section].name 2>/dev/null || echo "")
            tags=$(uci get dhcp.@host[$section].tag 2>/dev/null || echo "")
            
            if [ -n "$hostname" ] && [ -n "$ip" ]; then
                user=$(echo "$tags" | awk '{print $1}' | tr -d "'")
                cat=$(echo "$tags" | awk '{print $2}' | tr -d "'")
                os=$(echo "$tags" | awk '{print $3}' | tr -d "'")
                
                [ -z "$user" ] && user="unknown"
                [ -z "$cat" ] && cat="unknown"
                [ -z "$os" ] && os="unknown"
                
                echo "$ip $hostname $user $cat $os" >> "$tmp_mapping"
            fi
        fi
    done
    
    # Process conntrack with detailed local traffic tracking
    awk -v mapping_file="$tmp_mapping" '
    BEGIN {
        while (getline < mapping_file) {
            ip_to_hostname[$1] = $2;
            ip_to_user[$1] = $3;
            ip_to_cat[$1] = $4;
            ip_to_os[$1] = $5;
        }
        close(mapping_file);
    }
    
    # Function to get hostname for IP
    function get_hostname(ip) {
        if (ip == "192.168.1.1") return "asus";
        if (ip == "192.168.29.1") return "jio-gateway";
        if (ip == "192.168.29.2") return "asus-wan";
        return (ip in ip_to_hostname) ? ip_to_hostname[ip] : "unknown";
    }
    
    # Function to get user/cat/os for IP
    function get_tags(ip, tag_type) {
        if (ip == "192.168.1.1") {
            if (tag_type == "user") return "home";
            if (tag_type == "cat") return "personal";
            if (tag_type == "os") return "openwrt";
        }
        if (ip == "192.168.29.1") {
            if (tag_type == "user") return "home";
            if (tag_type == "cat") return "personal";
            if (tag_type == "os") return "jio";
        }
        if (ip == "192.168.29.2") {
            if (tag_type == "user") return "home";
            if (tag_type == "cat") return "personal";
            if (tag_type == "os") return "openwrt";
        }
        
        if (tag_type == "user") return (ip in ip_to_user) ? ip_to_user[ip] : "unknown";
        if (tag_type == "cat") return (ip in ip_to_cat) ? ip_to_cat[ip] : "unknown";
        if (tag_type == "os") return (ip in ip_to_os) ? ip_to_os[ip] : "unknown";
    }
    
    {
        # Parse the conntrack entry structure
        src1 = ""; dst1 = ""; bytes1 = 0;
        src2 = ""; dst2 = ""; bytes2 = 0;
        sport1 = ""; dport1 = "";
        sport2 = ""; dport2 = "";
        
        direction = 1;
        for (i=1; i<=NF; i++) {
            if ($i ~ /^src=/) {
                gsub("src=", "", $i);
                if (direction == 1) {
                    src1 = $i;
                } else {
                    src2 = $i;
                }
            } else if ($i ~ /^dst=/) {
                gsub("dst=", "", $i);
                if (direction == 1) {
                    dst1 = $i;
                } else {
                    dst2 = $i;
                }
            } else if ($i ~ /^sport=/) {
                gsub("sport=", "", $i);
                if (direction == 1) {
                    sport1 = $i;
                } else {
                    sport2 = $i;
                }
            } else if ($i ~ /^dport=/) {
                gsub("dport=", "", $i);
                if (direction == 1) {
                    dport1 = $i;
                } else {
                    dport2 = $i;
                }
            } else if ($i ~ /^bytes=/) {
                gsub("bytes=", "", $i);
                if (direction == 1) {
                    bytes1 = $i;
                    direction = 2;
                } else {
                    bytes2 = $i;
                }
            }
        }
        
        # Handle NAT mapping for return traffic
        if (src1 ~ /^192\.168\.1\./ && dst2 == "192.168.29.2" && sport1 == dport2) {
            # NAT return traffic - map to original device
            original_device = src1;
            
            # Count total TX/RX for original device
            tx_bytes_total[original_device] += bytes1;
            rx_bytes_total[original_device] += bytes2;
            
            # No local traffic for NAT (internet traffic)
        } else {
            # Normal processing for non-NAT traffic
            # Direction 1: src1 -> dst1
            if (src1 ~ /^192\.168\./ && src1 != "127.0.0.1" && src1 != "0.0.0.0") {
                tx_bytes_total[src1] += bytes1;
                
                # Local traffic with destination tracking
                if (dst1 ~ /^192\.168\./) {
                    key = src1 SUBSEP dst1;
                    tx_bytes_local_detailed[key] += bytes1;
                }
            }
            if (dst1 ~ /^192\.168\./ && dst1 != "127.0.0.1" && dst1 != "0.0.0.0") {
                rx_bytes_total[dst1] += bytes1;
                
                # Local traffic with source tracking
                if (src1 ~ /^192\.168\./) {
                    key = dst1 SUBSEP src1;
                    rx_bytes_local_detailed[key] += bytes1;
                }
            }
            
            # Direction 2: src2 -> dst2
            if (src2 ~ /^192\.168\./ && src2 != "127.0.0.1" && src2 != "0.0.0.0") {
                tx_bytes_total[src2] += bytes2;
                
                # Local traffic with destination tracking
                if (dst2 ~ /^192\.168\./) {
                    key = src2 SUBSEP dst2;
                    tx_bytes_local_detailed[key] += bytes2;
                }
            }
            if (dst2 ~ /^192\.168\./ && dst2 != "127.0.0.1" && dst2 != "0.0.0.0") {
                rx_bytes_total[dst2] += bytes2;
                
                # Local traffic with source tracking
                if (src2 ~ /^192\.168\./) {
                    key = dst2 SUBSEP src2;
                    rx_bytes_local_detailed[key] += bytes2;
                }
            }
        }
    }
    
    END {
        # Output total traffic metrics (aggregated per IP)
        for (ip in tx_bytes_total) {
            hostname = get_hostname(ip);
            user = get_tags(ip, "user");
            cat = get_tags(ip, "cat");
            os = get_tags(ip, "os");
            
            total_tx = (ip in tx_bytes_total) ? tx_bytes_total[ip] : 0;
            total_rx = (ip in rx_bytes_total) ? rx_bytes_total[ip] : 0;
            
            print "simon_tx_bytes_total{ip=\"" ip "\",hostname=\"" hostname "\",user=\"" user "\",cat=\"" cat "\",os=\"" os "\"} " total_tx;
            print "simon_rx_bytes_total{ip=\"" ip "\",hostname=\"" hostname "\",user=\"" user "\",cat=\"" cat "\",os=\"" os "\"} " total_rx;
        }
        
        # Output detailed local TX traffic (per source-destination pair)
        for (key in tx_bytes_local_detailed) {
            split(key, parts, SUBSEP);
            src_ip = parts[1];
            dst_ip = parts[2];
            
            src_hostname = get_hostname(src_ip);
            src_user = get_tags(src_ip, "user");
            src_cat = get_tags(src_ip, "cat");
            src_os = get_tags(src_ip, "os");
            
            dst_hostname = get_hostname(dst_ip);
            
            print "simon_local_tx_bytes_total{ip=\"" src_ip "\",hostname=\"" src_hostname "\",user=\"" src_user "\",cat=\"" src_cat "\",os=\"" src_os "\",dst_ip=\"" dst_ip "\",dst_hostname=\"" dst_hostname "\"} " tx_bytes_local_detailed[key];
        }
        
        # Output detailed local RX traffic (per destination-source pair)
        for (key in rx_bytes_local_detailed) {
            split(key, parts, SUBSEP);
            dst_ip = parts[1];
            src_ip = parts[2];
            
            dst_hostname = get_hostname(dst_ip);
            dst_user = get_tags(dst_ip, "user");
            dst_cat = get_tags(dst_ip, "cat");
            dst_os = get_tags(dst_ip, "os");
            
            src_hostname = get_hostname(src_ip);
            
            print "simon_local_rx_bytes_total{ip=\"" dst_ip "\",hostname=\"" dst_hostname "\",user=\"" dst_user "\",cat=\"" dst_cat "\",os=\"" dst_os "\",src_ip=\"" src_ip "\",src_hostname=\"" src_hostname "\"} " rx_bytes_local_detailed[key];
        }
    }
    ' /proc/net/nf_conntrack
    
    rm -f "$tmp_mapping"
}

# Function to write metrics to file
write_metrics() {
    local timestamp="$(date +%s)"
    local metrics_file="$DATA_DIR/metrics.prom"
    
    # Write CPU metrics (raw counters)
    get_cpu_stats >> "$metrics_file.tmp"
    
    # Write memory metrics
    get_memory_stats | while read metric_name value; do
        prometheus_name=$(echo "$metric_name" | sed 's/mem_/simon_memory_/')
        echo "$prometheus_name $value" >> "$metrics_file.tmp"
    done
    
    # Write temperature metrics
    get_temperature_stats | while read metric_line; do
        echo "simon_$metric_line" >> "$metrics_file.tmp"
    done
    
    # Write network bandwidth metrics
    get_nlbwmon_stats >> "$metrics_file.tmp"
    
    # Add timestamp and move to final location
    echo "# Generated at: $(date)" > "$metrics_file"
    echo "# Timestamp: $timestamp" >> "$metrics_file"
    if [ -f "$metrics_file.tmp" ]; then
        cat "$metrics_file.tmp" >> "$metrics_file"
        rm -f "$metrics_file.tmp"
    fi
}

# Main daemon function
run_daemon() {
    log "Starting daemon..."
    
    while true; do
        # Write metrics once per second
        write_metrics
        
        sleep 15
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
            echo "Metrics file:"
            ls -la "$DATA_DIR"/metrics.prom 2>/dev/null || echo "  No metrics file found"
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
