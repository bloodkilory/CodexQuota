use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::str::FromStr;
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppError {
    pub code: String,
    pub retry_at: Option<u64>,
}
impl AppError {
    pub fn new(code: &str) -> Self {
        Self {
            code: code.into(),
            retry_at: None,
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Wallet {
    pub currency: String,
    pub total: String,
    pub granted: String,
    pub topped_up: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaWindow {
    pub remaining: Option<f64>,
    pub minutes: Option<u64>,
    pub resets_at: Option<f64>,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Quota {
    pub plan: Option<String>,
    pub windows: Vec<QuotaWindow>,
}
pub fn parse_balance(root: &Value) -> Result<Vec<Wallet>, AppError> {
    let invalid = || AppError::new("invalid_balance");
    root["is_available"].as_bool().ok_or_else(invalid)?;
    let values = root["balance_infos"].as_array().ok_or_else(invalid)?;
    if values.is_empty() || values.len() > 2 {
        return Err(invalid());
    }
    let mut currencies = std::collections::HashSet::new();
    values
        .iter()
        .map(|v| {
            let currency = v["currency"]
                .as_str()
                .filter(|s| ["CNY", "USD"].contains(s))
                .ok_or_else(invalid)?;
            if !currencies.insert(currency) {
                return Err(invalid());
            }
            let amount = |key: &str| -> Result<String, AppError> {
                let s = v[key]
                    .as_str()
                    .filter(|s| !s.is_empty() && s.len() <= 38)
                    .ok_or_else(invalid)?;
                let digits = s.strip_prefix('-').unwrap_or(s);
                let mut parts = digits.split('.');
                let whole = parts.next().unwrap_or("");
                let fraction = parts.next();
                if whole.is_empty()
                    || !whole.bytes().all(|c| c.is_ascii_digit())
                    || parts.next().is_some()
                    || fraction
                        .is_some_and(|f| f.is_empty() || !f.bytes().all(|c| c.is_ascii_digit()))
                {
                    return Err(invalid());
                }
                let value = Decimal::from_str(s).map_err(|_| invalid())?;
                Ok(format!("{:.2}", value.round_dp(2)))
            };
            Ok(Wallet {
                currency: currency.into(),
                total: amount("total_balance")?,
                granted: amount("granted_balance")?,
                topped_up: amount("topped_up_balance")?,
            })
        })
        .collect()
}
pub fn parse_codex(root: &Value) -> Result<Quota, AppError> {
    let map = root["rateLimitsByLimitId"].as_object();
    let bucket = map
        .and_then(|m| m.get("codex"))
        .or_else(|| root.get("rateLimits"))
        .filter(|v| v.is_object())
        .ok_or_else(|| AppError::new("invalid_quota"))?;
    let windows = ["primary", "secondary"]
        .iter()
        .filter_map(|key| bucket.get(key).filter(|v| v.is_object()))
        .map(|v| QuotaWindow {
            remaining: v["usedPercent"]
                .as_f64()
                .filter(|n| n.is_finite())
                .map(|n| (100.0 - n).clamp(0.0, 100.0)),
            minutes: v["windowDurationMins"].as_u64(),
            resets_at: v["resetsAt"].as_f64().filter(|v| v.is_finite()),
        })
        .collect::<Vec<_>>();
    if windows.is_empty() {
        return Err(AppError::new("invalid_quota"));
    }
    Ok(Quota {
        plan: bucket["planType"].as_str().map(str::to_owned),
        windows,
    })
}
pub fn now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

impl std::fmt::Display for AppError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.code)
    }
}
impl std::error::Error for AppError {}
