use crate::{
    cc_switch::Connection,
    models::{now, AppError, Quota, QuotaWindow, Wallet},
};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, path::Path};
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Preferences {
    pub source: String,
    pub language: String,
    pub directory: String,
    pub autostart: bool,
    #[serde(default)]
    pub display: BTreeMap<String, String>,
    #[serde(default)]
    pub model: BTreeMap<String, String>,
}
impl Preferences {
    pub fn defaults(home: &Path) -> Self {
        Self {
            source: "codex".into(),
            language: "system".into(),
            directory: home.join(".cc-switch").to_string_lossy().into(),
            autostart: false,
            display: BTreeMap::new(),
            model: BTreeMap::new(),
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
    cooldown: Option<AppError>,
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
            cooldown: None,
        }
    }
    pub fn snapshot(&self) -> Snapshot {
        self.state.clone()
    }
    pub fn select(&mut self, source: &str) -> Result<(), AppError> {
        if source != "codex"
            && source != "claude"
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
        self.cooldown = None;
        Ok(())
    }
    pub fn set_directory(&mut self, directory: String) {
        if self.state.preferences.directory != directory
            && self.state.preferences.source.starts_with("api:")
        {
            self.epoch += 1;
            self.state.reading = Reading::default();
            self.credential_generation = None;
            self.cooldown = None;
        }
        self.state.preferences.directory = directory;
    }
    pub fn selected_model(&self) -> Option<&str> {
        let saved = self
            .state
            .preferences
            .model
            .get(&self.state.preferences.source)?;
        match &self.state.reading.data {
            Some(Data::Quota(q))
                if !saved.is_empty()
                    && q.windows.iter().any(|w| w.label.as_ref() == Some(saved)) =>
            {
                Some(saved)
            }
            _ => None,
        }
    }
    fn model_windows(&self) -> Vec<&QuotaWindow> {
        let selected = self.selected_model();
        match &self.state.reading.data {
            Some(Data::Quota(q)) => q
                .windows
                .iter()
                .filter(|w| match selected {
                    Some(model) => w.label.as_deref() == Some(model),
                    None => {
                        w.remaining.is_some()
                            && (self.state.preferences.source != "codex"
                                || w.label.is_none()
                                || w.label.as_deref() == Some("codex"))
                    }
                })
                .collect(),
            _ => vec![],
        }
    }
    pub fn select_model(&mut self, value: &str) -> Result<(), AppError> {
        if !value.is_empty()
            && !matches!(&self.state.reading.data, Some(Data::Quota(q)) if q.windows.iter().any(|w| w.label.as_deref() == Some(value)))
        {
            return Err(AppError::new("invalid_quota"));
        }
        self.state
            .preferences
            .model
            .insert(self.state.preferences.source.clone(), value.into());
        Ok(())
    }
    pub fn display_window(&self) -> Option<&QuotaWindow> {
        let windows = self.model_windows();
        let minutes = self
            .state
            .preferences
            .display
            .get(&self.state.preferences.source)
            .and_then(|s| s.parse::<u64>().ok())
            .filter(|m| windows.iter().any(|w| w.minutes == Some(*m)))
            .or_else(|| windows.iter().filter_map(|w| w.minutes).min());
        let matching = windows
            .into_iter()
            .filter(|w| w.minutes == minutes)
            .collect::<Vec<_>>();
        matching
            .iter()
            .copied()
            .filter(|w| w.remaining.is_some())
            .min_by(|a, b| a.remaining.unwrap().total_cmp(&b.remaining.unwrap()))
            .or_else(|| matching.first().copied())
    }
    pub fn select_display(&mut self, value: &str) -> Result<(), AppError> {
        let valid = match &self.state.reading.data {
            Some(Data::Quota(_)) => self
                .model_windows()
                .iter()
                .any(|w| w.minutes.is_some_and(|m| m.to_string() == value)),
            Some(Data::Balance(wallets)) => wallets.iter().any(|w| w.currency == value),
            None => false,
        };
        if !valid {
            return Err(AppError::new("invalid_quota"));
        }
        self.state
            .preferences
            .display
            .insert(self.state.preferences.source.clone(), value.into());
        Ok(())
    }
    pub fn display_amount(&self) -> String {
        let choice = self
            .state
            .preferences
            .display
            .get(&self.state.preferences.source);
        match &self.state.reading.data {
            Some(Data::Quota(_)) => self
                .display_window()
                .and_then(|w| w.remaining)
                .map(|n| format!("{n:.0}%")),
            Some(Data::Balance(wallets)) => choice
                .and_then(|c| wallets.iter().find(|w| &w.currency == c))
                .or_else(|| wallets.first())
                .map(|w| format!("{} {}", w.currency, w.total)),
            None => None,
        }
        .unwrap_or_else(|| "—".into())
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
    pub fn record_rate_limit(&mut self, request: &Request, error: &AppError) {
        if self.current(request) && error.code == "rate_limited" {
            self.cooldown = Some(error.clone());
        }
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
                self.cooldown = None;
            }
            Err(error) => {
                self.record_rate_limit(&request, &error);
                self.state.reading.error = Some(error);
            }
        }
        true
    }
    pub fn credentials_changed(&mut self) {
        self.state.reading.data = None;
        self.state.reading.updated = None;
        self.credential_generation = None;
        self.cooldown = None;
        self.state.reading.error = None;
    }
    pub fn validate_credential(&mut self, generation: &str) -> Option<AppError> {
        if self.credential_generation.as_deref() != Some(generation) {
            self.credentials_changed();
            self.credential_generation = Some(generation.into());
        }
        self.cooldown
            .as_ref()
            .filter(|e| e.retry_at.is_some_and(|t| t > now()))
            .cloned()
    }
    pub fn current(&self, r: &Request) -> bool {
        self.epoch == r.epoch && self.state.preferences.source == r.source
    }
}
