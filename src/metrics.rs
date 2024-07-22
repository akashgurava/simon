use prometheus::{CounterVec, Gauge, GaugeVec, Opts, Registry};

/// Struct containing all the metrics we're tracking
pub struct Metrics {
    /// CPU Usage percentage per core
    pub(crate) cpu_usage: GaugeVec,
    /// Total physical memory in bytes
    pub(crate) memory_total: Gauge,
    /// Free physical memory in bytes
    pub(crate) memory_free: Gauge,
    /// Available physical memory in bytes
    pub(crate) memory_available: Gauge,
    /// Used physical memory in bytes
    pub(crate) memory_used: Gauge,
    /// Total swap memory in bytes
    pub(crate) swap_total: Gauge,
    /// Free swap memory in bytes
    pub(crate) swap_free: Gauge,
    /// Used swap memory in bytes
    pub(crate) swap_used: Gauge,
    /// Memory usage per process
    pub(crate) process_memory: GaugeVec,
    /// Virtual memory usage per process
    pub(crate) process_virtual_memory: GaugeVec,
    /// Start time per process (seconds since epoch)
    pub(crate) process_start_time: GaugeVec,
    /// Runtime per process in seconds
    pub(crate) process_runtime: GaugeVec,
    /// CPU usage per process
    pub(crate) process_cpu_usage: GaugeVec,
    /// Disk read per process
    pub(crate) process_disk_read_total: CounterVec,
    /// Disk write per process
    pub(crate) process_disk_write_total: CounterVec,
    /// Total number of bytes received, per network interface
    pub(crate) network_received_total: CounterVec,
    /// Total number of bytes transmitted, per network interface
    pub(crate) network_transmitted_total: CounterVec,
    /// Total number of packets received, per network interface
    pub(crate) network_packets_received_total: CounterVec,
    /// Total number of packets transmitted, per network interface
    pub(crate) network_packets_transmitted_total: CounterVec,
    /// Total number of errors on received packets, per network interface
    pub(crate) network_errors_on_received_total: CounterVec,
    /// Total number of errors on transmitted packets, per network interface
    pub(crate) network_errors_on_transmitted_total: CounterVec,
}

impl Metrics {
    pub fn new(registry: &Registry) -> Result<Self, Box<dyn std::error::Error>> {
        // Define options for each metric
        let cpu_usage_opts = Opts::new("usage_percentage", "CPU usage percentage per core")
            .namespace("simon")
            .subsystem("cpu");
        let cpu_usage = GaugeVec::new(cpu_usage_opts, &["core"])?;

        let memory_total_opts = Opts::new("total_bytes", "Total physical memory in bytes")
            .namespace("simon")
            .subsystem("memory");
        let memory_total = Gauge::with_opts(memory_total_opts)?;

        let memory_free_opts = Opts::new("free_bytes", "Free physical memory in bytes")
            .namespace("simon")
            .subsystem("memory");
        let memory_free = Gauge::with_opts(memory_free_opts)?;

        let memory_available_opts =
            Opts::new("available_bytes", "Available physical memory in bytes")
                .namespace("simon")
                .subsystem("memory");
        let memory_available = Gauge::with_opts(memory_available_opts)?;

        let memory_used_opts = Opts::new("used_bytes", "Used physical memory in bytes")
            .namespace("simon")
            .subsystem("memory");
        let memory_used = Gauge::with_opts(memory_used_opts)?;

        let swap_total_opts = Opts::new("total_bytes", "Total swap memory in bytes")
            .namespace("simon")
            .subsystem("swap");
        let swap_total = Gauge::with_opts(swap_total_opts)?;

        let swap_free_opts = Opts::new("free_bytes", "Free swap memory in bytes")
            .namespace("simon")
            .subsystem("swap");
        let swap_free = Gauge::with_opts(swap_free_opts)?;

        let swap_used_opts = Opts::new("used_bytes", "Used swap memory in bytes")
            .namespace("simon")
            .subsystem("swap");
        let swap_used = Gauge::with_opts(swap_used_opts)?;

        let process_memory_opts = Opts::new("memory_bytes", "Memory usage per process")
            .namespace("simon")
            .subsystem("process");
        let process_memory = GaugeVec::new(process_memory_opts, &["name", "pid"])?;

        let process_virtual_memory_opts =
            Opts::new("virtual_memory_bytes", "Virtual memory usage per process")
                .namespace("simon")
                .subsystem("process");
        let process_virtual_memory = GaugeVec::new(process_virtual_memory_opts, &["name", "pid"])?;

        let process_start_time_opts = Opts::new(
            "start_time_seconds",
            "Start time per process (seconds since epoch)",
        )
        .namespace("simon")
        .subsystem("process");
        let process_start_time = GaugeVec::new(process_start_time_opts, &["name", "pid"])?;

        let process_runtime_opts = Opts::new("runtime_seconds", "Runtime per process in seconds")
            .namespace("simon")
            .subsystem("process");
        let process_runtime = GaugeVec::new(process_runtime_opts, &["name", "pid"])?;

        let process_cpu_usage_opts = Opts::new("cpu_usage_percentage", "CPU usage per process")
            .namespace("simon")
            .subsystem("process");
        let process_cpu_usage = GaugeVec::new(process_cpu_usage_opts, &["name", "pid"])?;

        let process_disk_read_total_opts =
            Opts::new("disk_read_bytes_total", "Disk read per process")
                .namespace("simon")
                .subsystem("process");
        let process_disk_read_total =
            CounterVec::new(process_disk_read_total_opts, &["name", "pid"])?;

        let process_disk_write_total_opts =
            Opts::new("disk_write_bytes_total", "Disk write per process")
                .namespace("simon")
                .subsystem("process");
        let process_disk_write_total =
            CounterVec::new(process_disk_write_total_opts, &["name", "pid"])?;

        let network_received_total_opts = Opts::new(
            "received_bytes_total",
            "Total number of bytes received, per network interface",
        )
        .namespace("simon")
        .subsystem("network");
        let network_received_total = CounterVec::new(network_received_total_opts, &["interface"])?;

        let network_transmitted_total_opts = Opts::new(
            "transmitted_bytes_total",
            "Total number of bytes transmitted, per network interface",
        )
        .namespace("simon")
        .subsystem("network");
        let network_transmitted_total =
            CounterVec::new(network_transmitted_total_opts, &["interface"])?;

        let network_packets_received_total_opts = Opts::new(
            "packets_received_total",
            "Total number of packets received, per network interface",
        )
        .namespace("simon")
        .subsystem("network");
        let network_packets_received_total =
            CounterVec::new(network_packets_received_total_opts, &["interface"])?;

        let network_packets_transmitted_total_opts = Opts::new(
            "packets_transmitted_total",
            "Total number of packets transmitted, per network interface",
        )
        .namespace("simon")
        .subsystem("network");
        let network_packets_transmitted_total =
            CounterVec::new(network_packets_transmitted_total_opts, &["interface"])?;

        let network_errors_on_received_total_opts = Opts::new(
            "errors_on_received_total",
            "Total number of errors on received packets, per network interface",
        )
        .namespace("simon")
        .subsystem("network");
        let network_errors_on_received_total =
            CounterVec::new(network_errors_on_received_total_opts, &["interface"])?;

        let network_errors_on_transmitted_total_opts = Opts::new(
            "errors_on_transmitted_total",
            "Total number of errors on transmitted packets, per network interface",
        )
        .namespace("simon")
        .subsystem("network");
        let network_errors_on_transmitted_total =
            CounterVec::new(network_errors_on_transmitted_total_opts, &["interface"])?;

        // Register all metrics with the provided registry
        registry.register(Box::new(cpu_usage.clone()))?;
        registry.register(Box::new(memory_total.clone()))?;
        registry.register(Box::new(memory_free.clone()))?;
        registry.register(Box::new(memory_available.clone()))?;
        registry.register(Box::new(memory_used.clone()))?;
        registry.register(Box::new(swap_total.clone()))?;
        registry.register(Box::new(swap_free.clone()))?;
        registry.register(Box::new(swap_used.clone()))?;
        registry.register(Box::new(process_memory.clone()))?;
        registry.register(Box::new(process_virtual_memory.clone()))?;
        registry.register(Box::new(process_start_time.clone()))?;
        registry.register(Box::new(process_runtime.clone()))?;
        registry.register(Box::new(process_cpu_usage.clone()))?;
        registry.register(Box::new(process_disk_read_total.clone()))?;
        registry.register(Box::new(process_disk_write_total.clone()))?;
        registry.register(Box::new(network_received_total.clone()))?;
        registry.register(Box::new(network_transmitted_total.clone()))?;
        registry.register(Box::new(network_packets_received_total.clone()))?;
        registry.register(Box::new(network_packets_transmitted_total.clone()))?;
        registry.register(Box::new(network_errors_on_received_total.clone()))?;
        registry.register(Box::new(network_errors_on_transmitted_total.clone()))?;

        Ok(Metrics {
            cpu_usage,
            memory_total,
            memory_free,
            memory_available,
            memory_used,
            swap_total,
            swap_free,
            swap_used,
            process_memory,
            process_virtual_memory,
            process_start_time,
            process_runtime,
            process_cpu_usage,
            process_disk_read_total,
            process_disk_write_total,
            network_received_total,
            network_transmitted_total,
            network_packets_received_total,
            network_packets_transmitted_total,
            network_errors_on_received_total,
            network_errors_on_transmitted_total,
        })
    }
}
