use crate::{
    cc_switch::Connection,
    models::{now, AppError, Quota, Wallet},
};
use serde::{Deserialize, Serialize};
use std::path::Path;
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Preferences {
    pub source: String,
    pub language: String,
    pub directory: String,
    pub autostart: bool,
}
impl Preferences {
    pub fn defaults(home: &Path) -> Self {
        Self {
            source: "codex".into(),
            language: "system".into(),
            directory: home.join(".cc-switch").to_string_lossy().into(),
            autostart: false,
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
pub enum Data {
    Quota(Quota),
    Balance(Vec<Wallet>),
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Reading {
    pub data: Option<Data>,
    pub updated: Option<u64>,
    pub error: Option<AppError>,
    pub refreshing: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub preferences: Preferences,
    pub connections: Vec<Connection>,
    pub reading: Reading,
    pub discovery_error: Option<AppError>,
    pub update: Option<crate::updates::Update>,
    pub update_status: String,
}
#[derive(Clone)]
pub struct Request {
    pub source: String,
    pub directory: String,
    epoch: u64,
}
pub struct Service {
    pub state: Snapshot,
    epoch: u64,
    pub credential_generation: Option<String>,
}
impl Service {
    pub fn new(preferences: Preferences) -> Self {
        Self {
            state: Snapshot {
                preferences,
                connections: vec![],
                reading: Reading::default(),
                discovery_error: None,
                update: None,
                update_status: "idle".into(),
            },
            epoch: 0,
            credential_generation: None,
        }
    }
    pub fn snapshot(&self) -> Snapshot {
        self.state.clone()
    }
    pub fn select(&mut self, source: &str) -> Result<(), AppError> {
        if source != "codex"
            && !self
                .state
                .connections
                .iter()
                .any(|c| c.supported && source == format!("api:{}", c.id))
        {
            return Err(AppError::new("unsupported_source"));
        }
        self.epoch += 1;
        self.state.preferences.source = source.into();
        self.state.reading = Reading::default();
        self.credential_generation = None;
        Ok(())
    }
    pub fn begin(&mut self) -> Option<Request> {
        if self.state.reading.refreshing {
            return None;
        }
        self.state.reading.refreshing = true;
        Some(Request {
            source: self.state.preferences.source.clone(),
            directory: self.state.preferences.directory.clone(),
            epoch: self.epoch,
        })
    }
    pub fn finish(&mut self, request: Request, result: Result<Data, AppError>) -> bool {
        if !self.current(&request) {
            return false;
        }
        self.state.reading.refreshing = false;
        match result {
            Ok(data) => {
                self.state.reading.data = Some(data);
                self.state.reading.updated = Some(now());
                self.state.reading.error = None;
            }
            Err(error) => self.state.reading.error = Some(error),
        }
        true
    }
    pub fn credentials_changed(&mut self) {
        self.state.reading.data = None;
        self.state.reading.updated = None;
        self.credential_generation = None;
        self.state.reading.error = None;
    }
    pub fn validate_credential(&mut self, generation: &str) -> Option<AppError> {
        if self.credential_generation.as_deref() != Some(generation) {
            self.credentials_changed();
            self.credential_generation = Some(generation.into());
        }
        self.state
            .reading
            .error
            .as_ref()
            .filter(|e| e.retry_at.is_some_and(|t| t > now()))
            .cloned()
    }
    pub fn current(&self, r: &Request) -> bool {
        self.epoch == r.epoch && self.state.preferences.source == r.source
    }
}
