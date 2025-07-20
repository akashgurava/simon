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
use tracing::{debug, error, info};

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
    debug!("Metrics endpoint called");

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
    let mut app_state = AppState::new()?;

    // Start background metrics collection
    app_state.start_background_metrics_collection()?;

    let app_state = Arc::new(app_state);

    let app = Router::new()
        .route("/", get(home))
        .route("/metrics", get(metrics))
        .with_state(app_state);

    // Run our app
    let listener = tokio::net::TcpListener::bind("0.0.0.0:9184").await?;
    println!("Listening on http://0.0.0.0:9184");
    axum::serve(listener, app).await?;

    // Background task will be cleaned up when the process terminates
    Ok(())
}
