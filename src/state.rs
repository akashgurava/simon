use std::sync::{Arc, Mutex};
use std::time::Duration;

use prometheus::Registry;
use sysinfo::{Networks, System};
use tokio::sync::broadcast;
use tokio::task::JoinHandle;
use tracing::{debug, error, info};

use crate::metrics::Metrics;

pub struct AppState {
    pub(crate) registry: Registry,
    pub(crate) metrics: Arc<Metrics>,
    pub(crate) system: Arc<Mutex<System>>,
    pub(crate) networks: Arc<Mutex<Networks>>,
    shutdown_tx: Option<broadcast::Sender<()>>,
    _background_task: Option<JoinHandle<()>>,
}

impl AppState {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let registry = Registry::new();
        let metrics = Arc::new(Metrics::new(&registry)?);
        let system = Arc::new(Mutex::new(System::new_all()));
        let networks = Arc::new(Mutex::new(Networks::new_with_refreshed_list()));

        Ok(Self {
            registry,
            metrics,
            system,
            networks,
            shutdown_tx: None,
            _background_task: None,
        })
    }

    pub fn start_background_metrics_collection(
        &mut self,
    ) -> Result<(), Box<dyn std::error::Error>> {
        if self._background_task.is_some() {
            return Err("Background metrics collection already started".into());
        }

        // Create shutdown channel
        let (shutdown_tx, shutdown_rx) = broadcast::channel(1);

        // Spawn background metrics collection task
        let background_task = {
            let metrics = Arc::clone(&self.metrics);
            let system = Arc::clone(&self.system);
            let networks = Arc::clone(&self.networks);
            let mut shutdown_rx = shutdown_rx;

            tokio::spawn(async move {
                info!("Background metrics collection task started");

                loop {
                    // Check for shutdown signal
                    match shutdown_rx.try_recv() {
                        Ok(_) => {
                            info!("Background metrics task received shutdown signal");
                            break;
                        }
                        Err(broadcast::error::TryRecvError::Empty) => {
                            // No shutdown signal, continue
                        }
                        Err(broadcast::error::TryRecvError::Closed) => {
                            info!("Shutdown channel closed, stopping background task");
                            break;
                        }
                        Err(broadcast::error::TryRecvError::Lagged(_)) => {
                            // Lagged behind, but continue
                            debug!("Background task lagged behind shutdown signals");
                        }
                    }

                    // Update system metrics
                    if let Ok(mut sys) = system.lock() {
                        sys.refresh_all();
                        metrics.update_system_metrics(sys);
                    } else {
                        error!("Failed to acquire system lock for metrics update");
                    }

                    // Update network metrics
                    if let Ok(mut nets) = networks.lock() {
                        nets.refresh(false);
                        for (name, network) in nets.iter() {
                            metrics.update_network_metrics(name, network);
                        }
                    } else {
                        error!("Failed to acquire networks lock for metrics update");
                    }

                    debug!("Background metrics update completed");

                    // Sleep for 5 seconds
                    tokio::time::sleep(Duration::from_secs(5)).await;
                }

                info!("Background metrics collection task stopped");
            })
        };

        self.shutdown_tx = Some(shutdown_tx);
        self._background_task = Some(background_task);

        Ok(())
    }

    pub async fn stop_background_metrics_collection(&mut self) {
        if let Some(shutdown_tx) = &self.shutdown_tx {
            let _ = shutdown_tx.send(());
        }

        if let Some(task) = self._background_task.take() {
            let _ = task.await;
        }

        self.shutdown_tx = None;
    }
}
