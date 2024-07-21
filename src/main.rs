mod metrics;
mod state;

use std::sync::Arc;
use std::time::Instant;

use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse, Response},
    routing::get,
    Router,
};
use prometheus::{Encoder, TextEncoder};
use tracing::{error, info};

use state::AppState;

async fn home() -> Html<String> {
    Html(format!(
        r#"
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>System Metrics Exporter</title>
            <style>
                body {{ font-family: Arial, sans-serif; line-height: 1.6; padding: 20px; }}
                h1 {{ color: #333; }}
                a {{ color: #0066cc; }}
            </style>
        </head>
        <body>
            <h1>Welcome to System Metrics Exporter</h1>
            <p>This service exports various system metrics in Prometheus format.</p>
            <p>You can access the metrics at: <a href="/metrics">/metrics</a></p>
            <h2>Available Metrics:</h2>
            <ul>
                <li>CPU usage per core</li>
                <li>Memory usage</li>
                <li>Network usage (received and transmitted bytes per interface)</li>
                <li>Disk I/O (read and write bytes per disk)</li>
            </ul>
            <p>These metrics can be scraped by Prometheus and visualized using tools like Grafana.</p>
        </body>
        </html>
        "#
    ))
}

async fn metrics(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    info!("Metrics endpoint called");

    let start_time = Instant::now();
    let result = try_get_metrics(state);
    let total_duration = start_time.elapsed();
    info!("Total request processing time: {:?}", total_duration);

    match result {
        Ok(response) => response,
        Err(e) => {
            error!("Error generating metrics: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                "Error generating metrics",
            )
                .into_response()
        }
    }
}

fn try_get_metrics(state: Arc<AppState>) -> Result<Response, Box<dyn std::error::Error>> {
    let mut system = state.system.lock().unwrap();
    let mut networks = state.networks.lock().unwrap();
    system.refresh_all();
    networks.refresh();

    // Update CPU usage per core
    for (i, cpu) in system.cpus().iter().enumerate() {
        state
            .metrics
            .cpu_usage
            .with_label_values(&[&i.to_string()])
            .set(cpu.cpu_usage() as f64);
    }

    // Update memory metrics
    state.metrics.memory_total.set(system.total_memory() as f64);
    state.metrics.memory_free.set(system.free_memory() as f64);
    state
        .metrics
        .memory_available
        .set(system.available_memory() as f64);
    state.metrics.memory_used.set(system.used_memory() as f64);

    // Update swap metrics
    state.metrics.swap_total.set(system.total_swap() as f64);
    state.metrics.swap_free.set(system.free_swap() as f64);
    state.metrics.swap_used.set(system.used_swap() as f64);

    for (pid, process) in system.processes() {
        let name = process.name();
        let pid_str = pid.to_string();

        state
            .metrics
            .process_memory
            .with_label_values(&[name, &pid_str])
            .set(process.memory() as f64);
        state
            .metrics
            .process_virtual_memory
            .with_label_values(&[name, &pid_str])
            .set(process.virtual_memory() as f64);
        state
            .metrics
            .process_start_time
            .with_label_values(&[name, &pid_str])
            .set(process.start_time() as f64);
        state
            .metrics
            .process_runtime
            .with_label_values(&[name, &pid_str])
            .set(process.run_time() as f64);
        state
            .metrics
            .process_cpu_usage
            .with_label_values(&[name, &pid_str])
            .set(process.cpu_usage() as f64);
        state
            .metrics
            .process_disk_read_total
            .with_label_values(&[name, &pid_str])
            .set(process.disk_usage().total_read_bytes as f64);
        state
            .metrics
            .process_disk_write_total
            .with_label_values(&[name, &pid_str])
            .set(process.disk_usage().total_written_bytes as f64);
    }

    // Update network metrics
    for (name, network) in networks.iter() {
        state
            .metrics
            .network_received_total
            .with_label_values(&[name])
            .set(network.received() as f64);

        state
            .metrics
            .network_transmitted_total
            .with_label_values(&[name])
            .set(network.transmitted() as f64);

        state
            .metrics
            .network_packets_received_total
            .with_label_values(&[name])
            .set(network.packets_received() as f64);

        state
            .metrics
            .network_packets_transmitted_total
            .with_label_values(&[name])
            .set(network.packets_transmitted() as f64);

        state
            .metrics
            .network_errors_on_received_total
            .with_label_values(&[name])
            .set(network.errors_on_received() as f64);

        state
            .metrics
            .network_errors_on_transmitted_total
            .with_label_values(&[name])
            .set(network.errors_on_transmitted() as f64);
    }

    // Encode the metrics as a string
    let mut buffer = vec![];
    let encoder = TextEncoder::new();
    encoder.encode(&state.registry.gather(), &mut buffer)?;

    // Convert the format_type to a String
    let content_type = encoder.format_type().to_string();

    Ok((
        StatusCode::OK,
        [(axum::http::header::CONTENT_TYPE, content_type)],
        buffer,
    )
        .into_response())
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Create the app state
    let app_state = Arc::new(AppState::new()?);

    let app = Router::new()
        .route("/", get(home))
        .route("/metrics", get(metrics))
        .with_state(app_state);

    // Run our app
    let listener = tokio::net::TcpListener::bind("0.0.0.0:9184").await?;
    println!("Listening on http://0.0.0.0:9184");
    axum::serve(listener, app).await?;

    Ok(())
}
