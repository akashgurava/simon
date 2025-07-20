use std::collections::HashMap;
use std::sync::Mutex;

use prometheus::Registry;
use sysinfo::{Networks, System};

use crate::metrics::Metrics;

pub struct AppState {
    pub(crate) registry: Registry,
    pub(crate) metrics: Metrics,
    pub(crate) system: Mutex<System>,
    pub(crate) networks: Mutex<Networks>,
}

impl AppState {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let registry = Registry::new();
        let metrics = Metrics::new(&registry)?;

        Ok(Self {
            registry,
            metrics,
            system: Mutex::new(System::new_all()),
            networks: Mutex::new(Networks::new_with_refreshed_list()),
        })
    }
}
