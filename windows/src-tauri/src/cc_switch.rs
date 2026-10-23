use crate::models::AppError;
use rusqlite::{Connection as Database, OpenFlags};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::{path::Path, time::Duration};
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Connection {
    pub id: String,
    pub name: String,
    pub harness: String,
    pub origin: String,
    pub supported: bool,
}
// Intentionally neither serializable nor Debug: tokens never cross IPC or enter logs.
pub struct Credential {
    pub token: String,
    pub generation: String,
}
fn error(e: rusqlite::Error) -> AppError {
    let busy = matches!(&e,rusqlite::Error::SqliteFailure(v,_) if matches!(v.code,rusqlite::ErrorCode::DatabaseBusy|rusqlite::ErrorCode::DatabaseLocked));
    AppError::new(if busy {
        "source_busy"
    } else {
        "invalid_source"
    })
}
fn open(directory: &Path) -> Result<Database, AppError> {
    let path = directory.join("cc-switch.db");
    if !path.is_file() {
        return Err(AppError::new("source_missing"));
    }
    let db = Database::open_with_flags(
        path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )
    .map_err(error)?;
    db.busy_timeout(Duration::from_millis(200)).map_err(error)?;
    let version: u32 = db
        .query_row("PRAGMA user_version", [], |r| r.get(0))
        .map_err(error)?;
    if !(18..=20).contains(&version) {
        return Err(AppError::new("incompatible_source"));
    }
    Ok(db)
}
fn endpoint(config: &Value, harness: &str) -> String {
    if harness == "claude" {
        return config["env"]["ANTHROPIC_BASE_URL"]
            .as_str()
            .unwrap_or("")
            .into();
    }
    let Some(raw) = config["config"].as_str() else {
        return String::new();
    };
    let Ok(value) = raw.parse::<toml::Value>() else {
        return String::new();
    };
    let provider = value
        .get("model_provider")
        .and_then(toml::Value::as_str)
        .unwrap_or("");
    value
        .get("model_providers")
        .and_then(|v| v.get(provider))
        .and_then(|v| v.get("base_url"))
        .and_then(toml::Value::as_str)
        .unwrap_or("")
        .into()
}
fn origin(endpoint: &str) -> (String, bool) {
    let Ok(url) = url::Url::parse(endpoint) else {
        return (String::new(), false);
    };
    if !url.username().is_empty() || url.password().is_some() {
        return (String::new(), false);
    }
    let supported = url.scheme() == "https"
        && url.host_str() == Some("api.deepseek.com")
        && url.query().is_none()
        && url.fragment().is_none()
        && endpoint
            .strip_prefix("https://")
            .and_then(|v| v.split('/').next())
            == Some("api.deepseek.com");
    (url.origin().ascii_serialization(), supported)
}
pub fn discover(directory: &Path) -> Result<Vec<Connection>, AppError> {
    let db = open(directory)?;
    let mut query=db.prepare("SELECT id,app_type,name,json_object('env',json_object('ANTHROPIC_BASE_URL',json_extract(settings_config,'$.env.ANTHROPIC_BASE_URL')),'config',json_extract(settings_config,'$.config')) FROM providers WHERE app_type IN ('claude','codex') AND length(settings_config)<=1048576 ORDER BY app_type,name LIMIT 501").map_err(error)?;
    let rows = query
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
            ))
        })
        .map_err(error)?;
    let mut out = Vec::new();
    for row in rows {
        let (id, harness, name, raw) = row.map_err(error)?;
        if out.len() >= 500 {
            return Err(AppError::new("invalid_source"));
        }
        let config: Value =
            serde_json::from_str(&raw).map_err(|_| AppError::new("invalid_source"))?;
        let (origin, supported) = origin(&endpoint(&config, &harness));
        let name = name.chars().filter(|c| !c.is_control()).take(80).collect();
        out.push(Connection {
            id: format!("{harness}|{id}"),
            name,
            harness,
            origin,
            supported,
        });
    }
    Ok(out)
}
pub fn resolve(directory: &Path, id: &str) -> Result<Credential, AppError> {
    let (harness, key) = id
        .split_once('|')
        .filter(|(h, _)| ["claude", "codex"].contains(h))
        .ok_or_else(|| AppError::new("invalid_source"))?;
    let db = open(directory)?;
    let raw:String=db.query_row("SELECT settings_config FROM providers WHERE app_type=?1 AND id=?2 AND length(settings_config)<=1048576",[harness,key],|row|row.get(0)).map_err(error)?;
    let config: Value = serde_json::from_str(&raw).map_err(|_| AppError::new("invalid_source"))?;
    if !origin(&endpoint(&config, harness)).1 {
        return Err(AppError::new("unsupported_source"));
    }
    let token = if harness == "claude" {
        config["env"]
            .get("ANTHROPIC_AUTH_TOKEN")
            .or_else(|| config["env"].get("ANTHROPIC_API_KEY"))
    } else {
        config["auth"].get("OPENAI_API_KEY")
    };
    let token = token
        .and_then(Value::as_str)
        .filter(|s| {
            !s.is_empty()
                && s.len() <= 16384
                && !["PROXY_MANAGED", "CC_SWITCH_PROXY_MANAGED"].contains(s)
                && !s.chars().any(|c| c.is_whitespace() || c.is_control())
        })
        .ok_or_else(|| AppError::new("credentials_missing"))?
        .to_owned();
    let generation = format!("{:x}", Sha256::digest(format!("{id}\0{token}").as_bytes()));
    Ok(Credential { token, generation })
}
