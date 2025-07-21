# Simon System Monitor for OpenWrt

A lightweight, high-performance system monitoring solution designed specifically for OpenWrt routers and embedded devices. Provides real-time CPU, memory, and temperature metrics in Prometheus format.

## Features

- **Real-time Monitoring**: Collects metrics every second
- **Prometheus Compatible**: Native Prometheus format with proper HELP and TYPE headers
- **Low Resource Usage**: Designed for resource-constrained embedded devices
- **Temperature Monitoring**: Auto-discovers and monitors all available temperature sensors
- **Per-Core CPU Stats**: Individual CPU core raw counters for detailed monitoring
- **Detailed Memory Stats**: Total, free, available, used, buffers, and cached memory
- **HTTP API**: Built-in HTTP server for metric exposure
- **OpenWrt Integration**: Native init.d script with procd support
- **Background Operation**: Runs continuously as system daemon

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  simon-monitor  │    │   Metric File    │    │ simon-exporter  │
│   (Data Collector) ──▶│ /tmp/simon-metrics/ ──▶│  (HTTP Server)   │
│                 │    │                  │    │                 │
│ • CPU Stats     │    │ metrics.prom     │    │ :9184/metrics   │
│ • Memory Stats  │    │                  │    │                 │
│ • Temperature   │    │                  │    │ Prometheus      │
│                 │    │                  │    │ Compatible      │
│                 │    │                  │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Quick Start

### Installation

1. **Download the scripts** to your OpenWrt device:

   ```bash
   # Save the scripts as:
   # - simon-monitor.sh
   # - simon-exporter.sh
   # - simon-init.sh
   # - install.sh
   ```

2. **Run the installer**:

   ```bash
   chmod +x install.sh
   ./install.sh
   ```

3. **Verify installation**:
   ```bash
   /etc/init.d/simon-monitor status
   curl http://localhost:9184/metrics
   ```

### Manual Installation

If you prefer manual installation:

```bash
# Copy scripts to system locations
cp simon-monitor.sh /usr/bin/simon-monitor
cp simon-exporter.sh /usr/bin/simon-exporter
cp simon-init.sh /etc/init.d/simon-monitor

# Set permissions
chmod 755 /usr/bin/simon-monitor
chmod 755 /usr/bin/simon-exporter
chmod 755 /etc/init.d/simon-monitor

# Enable and start service
/etc/init.d/simon-monitor enable
/etc/init.d/simon-monitor start
```

## Usage

### Service Management

```bash
# Start the monitoring system
/etc/init.d/simon-monitor start

# Stop the monitoring system
/etc/init.d/simon-monitor stop

# Restart the monitoring system
/etc/init.d/simon-monitor restart

# Check service status
/etc/init.d/simon-monitor status
```

### Individual Component Control

```bash
# Monitor daemon
/usr/bin/simon-monitor {start|stop|restart|status}

# Prometheus exporter
/usr/bin/simon-exporter {start|stop|restart|status|test}
```

### Accessing Metrics

```bash
# Get current metrics
curl http://localhost:9184/metrics

# Test metrics output
/usr/bin/simon-exporter test
```

## Metric Examples

### CPU Metrics

```
# CPU usage metrics as counters
simon_cpu_user_total{core="0"} 152354
simon_cpu_system_total{core="0"} 89756
simon_cpu_idle_total{core="0"} 845673
simon_cpu_iowait_total{core="0"} 1234
simon_cpu_irq_total{core="0"} 567
simon_cpu_softirq_total{core="0"} 2345
simon_cpu_steal_total{core="0"} 12
simon_cpu_guest_total{core="0"} 0
```

### Memory Metrics

```
# HELP simon_memory_total_bytes Total physical memory in bytes
# TYPE simon_memory_total_bytes gauge
simon_memory_total_bytes 536870912

# HELP simon_memory_free_bytes Free physical memory in bytes
# TYPE simon_memory_free_bytes gauge
simon_memory_free_bytes 123456789

# HELP simon_memory_available_bytes Available physical memory in bytes
# TYPE simon_memory_available_bytes gauge
simon_memory_available_bytes 234567890

# HELP simon_memory_used_bytes Used physical memory in bytes
# TYPE simon_memory_used_bytes gauge
simon_memory_used_bytes 345678901
```

### Temperature Metrics

```
# HELP simon_temp_celsius Temperature in Celsius
# TYPE simon_temp_celsius gauge
simon_temp_celsius{sensor="class_thermal_thermal_zone0"} 45.2
simon_temp_celsius{sensor="class_hwmon_hwmon0_temp1"} 42.8
```

## Configuration

### Environment Variables

```bash
# Set custom HTTP port
export SIMON_PORT=9091

# Custom data directory
export DATA_DIR="/var/lib/simon-metrics"
```

### Configuration File

Create `/etc/simon-monitor.conf` for persistent configuration:

```bash
# HTTP server settings
HTTP_PORT=9184
BIND_ADDRESS="0.0.0.0"

# Collection rate
# Metrics are collected every second

# Enable/disable features
ENABLE_CPU_MONITORING=true
ENABLE_MEMORY_MONITORING=true
ENABLE_TEMPERATURE_MONITORING=true
```

## File Structure

```
/usr/bin/
├── simon-monitor          # Main monitoring daemon
└── simon-exporter         # Prometheus HTTP exporter

/etc/init.d/
└── simon-monitor          # OpenWrt init script

/tmp/simon-metrics/        # Metric storage (runtime)
└── metrics.prom           # Metrics file (updated every second)

/var/log/
├── simon-monitor.log      # Monitor daemon logs
└── simon-exporter.log     # Exporter logs

/var/run/
├── simon-monitor.pid      # Monitor daemon PID
└── simon-exporter.pid     # Exporter daemon PID
```

## Prometheus Configuration

Add to your `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: "openwrt-simon"
    static_configs:
      - targets: ["your-openwrt-ip:9184"]
    scrape_interval: 30s
    metrics_path: /metrics
```

## Grafana Dashboard

Example Grafana queries:

```promql
# CPU usage by core (as percentage)
100 * (
  rate(simon_cpu_user_total{core="0"}[1m]) +
  rate(simon_cpu_system_total{core="0"}[1m]) +
  rate(simon_cpu_irq_total{core="0"}[1m]) +
  rate(simon_cpu_softirq_total{core="0"}[1m])
) / (
  rate(simon_cpu_user_total{core="0"}[1m]) +
  rate(simon_cpu_system_total{core="0"}[1m]) +
  rate(simon_cpu_irq_total{core="0"}[1m]) +
  rate(simon_cpu_softirq_total{core="0"}[1m]) +
  rate(simon_cpu_idle_total{core="0"}[1m])
)

# System CPU usage (simpler formula)
rate(simon_cpu_system_total{core="0"}[1m]) / (
  rate(simon_cpu_system_total{core="0"}[1m]) +
  rate(simon_cpu_idle_total{core="0"}[1m])
)

# Memory usage percentage
(simon_memory_used_bytes / simon_memory_total_bytes) * 100

# Available memory percentage
(simon_memory_available_bytes / simon_memory_total_bytes) * 100

# Temperature by sensor
simon_temp_celsius
```

## Troubleshooting

### Check Service Status

```bash
# Overall status
/etc/init.d/simon-monitor status

# Individual components
/usr/bin/simon-monitor status
/usr/bin/simon-exporter status
```

### View Logs

```bash
# Monitor daemon logs
tail -f /var/log/simon-monitor.log

# Exporter logs
tail -f /var/log/simon-exporter.log

# System logs
logread | grep simon
```

### Test Components

```bash
# Test metric collection
/usr/bin/simon-monitor daemon &
sleep 5
ls -la /tmp/simon-metrics/

# Test HTTP server
/usr/bin/simon-exporter test
curl http://localhost:9184/metrics
```

### Common Issues

**Port already in use:**

```bash
# Check what's using port 9184
netstat -tlnp | grep :9184

# Use different port
export SIMON_PORT=9091
/etc/init.d/simon-monitor restart
```

**No temperature sensors:**

```bash
# Check available sensors
find /sys -name "temp*" -type f 2>/dev/null
find /sys -name "*temp*" -type f 2>/dev/null
```

**Missing dependencies:**

```bash
# Install required packages
opkg update
opkg install coreutils
# or
opkg install busybox
```

## Performance Characteristics

- **CPU Usage**: < 1% on typical OpenWrt device
- **Memory Usage**: < 2MB RAM
- **Disk Usage**: < 50KB for scripts, ~100KB for metric files
- **Network**: HTTP responses typically < 5KB
- **Collection Overhead**: < 100ms per collection cycle

## Supported Platforms

- OpenWrt 19.07+
- LEDE 17.01+
- Any Linux system with:
  - `/proc/stat` (CPU stats)
  - `/proc/meminfo` (memory stats)
  - `/sys` filesystem (temperature)
  - `busybox` or `coreutils`
  - `netcat` or `socat`

## Development

### Testing

```bash
# Run in foreground for debugging
/usr/bin/simon-monitor daemon

# Test individual functions
/usr/bin/simon-exporter test
```

### Customization

The scripts are designed to be easily customizable. Key areas:

- **Data collection**: Edit `get_*_stats()` functions
- **Output format**: Modify `write_metrics()` function
- **HTTP server**: Customize `serve_metrics()` function

## License

This project is released under the MIT License. Free for personal and commercial use.

## Contributing

Contributions welcome! Please:

1. Test on actual OpenWrt hardware
2. Maintain shell script compatibility
3. Keep resource usage minimal
4. Follow existing code style
5. Update documentation

## Support

For issues and questions:

1. Check the logs first: `tail -f /var/log/simon-*.log`
2. Verify system compatibility: `/usr/bin/simon-monitor` should run without errors
3. Test individual components: `/usr/bin/simon-exporter test`
4. Check network connectivity: `curl http://localhost:9184/metrics`
5. Check dependencies: `which nc socat`

---

**Simon System Monitor** - Lightweight monitoring for OpenWrt and embedded systems
