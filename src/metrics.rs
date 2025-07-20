use prometheus::{CounterVec, Gauge, GaugeVec, Opts, Registry};

/// Struct containing all the metrics we're tracking
pub struct Metrics {
    /// CPU Usage percentage per core
    cpu_usage: GaugeVec,

    /// Total physical memory in bytes
    memory_total: Gauge,
    /// Free physical memory in bytes
    memory_free: Gauge,
    /// Available physical memory in bytes
    memory_available: Gauge,
    /// Used physical memory in bytes
    memory_used: Gauge,

    /// Total swap memory in bytes
    swap_total: Gauge,
    /// Free swap memory in bytes
    swap_free: Gauge,
    /// Used swap memory in bytes
    swap_used: Gauge,

    /// CPU usage per process (aggregated by name)
    process_cpu_usage: GaugeVec,

    /// Start time per process (earliest start time by name)
    process_start_time: GaugeVec,
    /// Runtime per process (max runtime by name)
    process_runtime: GaugeVec,

    /// Memory usage per process (aggregated by name)
    process_memory: GaugeVec,
    /// Virtual memory usage per process (aggregated by name)
    process_virtual_memory: GaugeVec,

    /// Disk read per process (aggregated by name)
    process_disk_read_total: CounterVec,
    /// Disk write per process (aggregated by name)
    process_disk_write_total: CounterVec,

    /// Total number of bytes received, per network interface
    network_received_total: CounterVec,
    /// Total number of bytes transmitted, per network interface
    network_transmitted_total: CounterVec,
    /// Total number of packets received, per network interface
    network_packets_received_total: CounterVec,
    /// Total number of packets transmitted, per network interface
    network_packets_transmitted_total: CounterVec,
    /// Total number of errors on received packets, per network interface
    network_errors_on_received_total: CounterVec,
    /// Total number of errors on transmitted packets, per network interface
    network_errors_on_transmitted_total: CounterVec,
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

        let process_memory_opts = Opts::new(
            "memory_bytes",
            "Memory usage per process (aggregated by name)",
        )
        .namespace("simon")
        .subsystem("process");
        let process_memory = GaugeVec::new(process_memory_opts, &["name"])?;

        let process_virtual_memory_opts = Opts::new(
            "virtual_memory_bytes",
            "Virtual memory usage per process (aggregated by name)",
        )
        .namespace("simon")
        .subsystem("process");
        let process_virtual_memory = GaugeVec::new(process_virtual_memory_opts, &["name"])?;

        let process_start_time_opts = Opts::new(
            "start_time_seconds",
            "Start time per process (earliest start time by name)",
        )
        .namespace("simon")
        .subsystem("process");
        let process_start_time = GaugeVec::new(process_start_time_opts, &["name"])?;

        let process_runtime_opts = Opts::new(
            "runtime_seconds",
            "Runtime per process (max runtime by name)",
        )
        .namespace("simon")
        .subsystem("process");
        let process_runtime = GaugeVec::new(process_runtime_opts, &["name"])?;

        let process_cpu_usage_opts = Opts::new(
            "cpu_usage_percentage",
            "CPU usage per process (aggregated by name)",
        )
        .namespace("simon")
        .subsystem("process");
        let process_cpu_usage = GaugeVec::new(process_cpu_usage_opts, &["name"])?;

        let process_disk_read_total_opts = Opts::new(
            "disk_read_bytes_total",
            "Disk read per process (aggregated by name)",
        )
        .namespace("simon")
        .subsystem("process");
        let process_disk_read_total = CounterVec::new(process_disk_read_total_opts, &["name"])?;

        let process_disk_write_total_opts = Opts::new(
            "disk_write_bytes_total",
            "Disk write per process (aggregated by name)",
        )
        .namespace("simon")
        .subsystem("process");
        let process_disk_write_total = CounterVec::new(process_disk_write_total_opts, &["name"])?;

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

/// Implementation for System Metrics
impl Metrics {
    fn update_cpu_usage(&self, label: &str, value: f32) -> Result<(), Box<dyn std::error::Error>> {
        self.cpu_usage.with_label_values(&[label]).set(value.into());

        Ok(())
    }

    fn update_memory_metrics(
        &self,
        total: u64,
        free: u64,
        available: u64,
        used: u64,
    ) -> Result<(), Box<dyn std::error::Error>> {
        self.memory_total.set(total as f64);
        self.memory_free.set(free as f64);
        self.memory_available.set(available as f64);
        self.memory_used.set(used as f64);

        Ok(())
    }

    fn update_swap_metrics(
        &self,
        total: u64,
        free: u64,
        used: u64,
    ) -> Result<(), Box<dyn std::error::Error>> {
        self.swap_total.set(total as f64);
        self.swap_free.set(free as f64);
        self.swap_used.set(used as f64);

        Ok(())
    }

    pub fn update_system_metrics(
        &self,
        system: &mut sysinfo::System,
    ) -> Result<(), Box<dyn std::error::Error>> {
        system.refresh_all();

        // Update CPU usage per core
        for (i, cpu) in system.cpus().iter().enumerate() {
            self.update_cpu_usage(&i.to_string(), cpu.cpu_usage())?;
        }

        // Update memory metrics
        self.update_memory_metrics(
            system.total_memory(),
            system.free_memory(),
            system.available_memory(),
            system.used_memory(),
        )?;

        // Update swap metrics
        self.update_swap_metrics(system.total_swap(), system.free_swap(), system.used_swap())?;

        // Update process metrics (aggregated by name)
        for (_pid, process) in system.processes() {
            let name = process.name().to_str().unwrap();
            self.update_process_metrics(name, process)?;
        }

        Ok(())
    }

    fn update_process_metrics(
        &self,
        name: &str,
        process: &sysinfo::Process,
    ) -> Result<(), Box<dyn std::error::Error>> {
        // Get current values for aggregation (since we reset at start of cycle)
        let current_cpu = self.process_cpu_usage.with_label_values(&[name]).get();
        let current_memory = self.process_memory.with_label_values(&[name]).get();
        let current_virtual_memory = self.process_virtual_memory.with_label_values(&[name]).get();
        let current_start_time = self.process_start_time.with_label_values(&[name]).get();
        let current_run_time = self.process_runtime.with_label_values(&[name]).get();

        // Sum CPU usage, memory, virtual memory
        self.process_cpu_usage
            .with_label_values(&[name])
            .set(current_cpu + process.cpu_usage() as f64);

        self.process_memory
            .with_label_values(&[name])
            .set(current_memory + process.memory() as f64);

        self.process_virtual_memory
            .with_label_values(&[name])
            .set(current_virtual_memory + process.virtual_memory() as f64);

        // Add total disk bytes for this process to the aggregated counter
        // Use read_bytes and written_bytes for proper counter semantics
        let disk_usage = process.disk_usage();
        self.process_disk_read_total
            .with_label_values(&[name])
            .inc_by(disk_usage.read_bytes as f64);

        self.process_disk_write_total
            .with_label_values(&[name])
            .inc_by(disk_usage.written_bytes as f64);

        // Use min for start_time (earliest start time)
        let new_start_time = if current_start_time == 0.0 {
            process.start_time() as f64
        } else {
            current_start_time.min(process.start_time() as f64)
        };
        self.process_start_time
            .with_label_values(&[name])
            .set(new_start_time);

        // Use max for run_time (longest running time)
        let new_run_time = current_run_time.max(process.run_time() as f64);
        self.process_runtime
            .with_label_values(&[name])
            .set(new_run_time);

        Ok(())
    }
}

/// Implementation for Network Metrics
impl Metrics {
    pub fn update_network_metrics(
        &self,
        interface_name: &str,
        network: &sysinfo::NetworkData,
    ) -> Result<(), Box<dyn std::error::Error>> {
        self.network_received_total
            .with_label_values(&[interface_name])
            .inc_by(network.received() as f64);

        self.network_transmitted_total
            .with_label_values(&[interface_name])
            .inc_by(network.transmitted() as f64);

        self.network_packets_received_total
            .with_label_values(&[interface_name])
            .inc_by(network.packets_received() as f64);

        self.network_packets_transmitted_total
            .with_label_values(&[interface_name])
            .inc_by(network.packets_transmitted() as f64);

        self.network_errors_on_received_total
            .with_label_values(&[interface_name])
            .inc_by(network.errors_on_received() as f64);

        self.network_errors_on_transmitted_total
            .with_label_values(&[interface_name])
            .inc_by(network.errors_on_transmitted() as f64);

        Ok(())
    }
}
