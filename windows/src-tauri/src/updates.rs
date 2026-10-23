use crate::{deepseek, models::AppError};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::{
    path::{Path, PathBuf},
    time::Duration,
};
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Update {
    pub version: String,
    pub name: String,
    pub url: String,
    pub checksum_url: String,
}
pub fn select_release(root: &Value, current: &str) -> Result<Option<Update>, AppError> {
    let invalid = || AppError::new("invalid_update");
    if root["draft"].as_bool() != Some(false) || root["prerelease"].as_bool() != Some(false) {
        return Ok(None);
    }
    let version = root["tag_name"]
        .as_str()
        .and_then(|s| s.strip_prefix('v'))
        .ok_or_else(invalid)?;
    let parsed = semver::Version::parse(version).map_err(|_| invalid())?;
    if !parsed.pre.is_empty()
        || !parsed.build.is_empty()
        || parsed <= semver::Version::parse(current).map_err(|_| invalid())?
    {
        return Ok(None);
    }
    let name = format!("QuotaNest-{version}-windows-x64-setup.exe");
    let assets = root["assets"].as_array().ok_or_else(invalid)?;
    let find = |name: &str, max: u64| -> Result<Option<String>, AppError> {
        let items = assets
            .iter()
            .filter(|a| a["name"] == name)
            .collect::<Vec<_>>();
        if items.is_empty() {
            return Ok(None);
        }
        if items.len() != 1 || items[0]["size"].as_u64().is_none_or(|v| v == 0 || v > max) {
            return Err(invalid());
        }
        let expected =
            format!("https://github.com/bloodkilory/QuotaNest/releases/download/v{version}/{name}");
        if items[0]["browser_download_url"].as_str() != Some(&expected) {
            return Err(invalid());
        }
        Ok(Some(expected))
    };
    let Some(url) = find(&name, 134217728)? else {
        return Ok(None);
    };
    let checksum_url = find("SHA256SUMS.txt", 65536)?.ok_or_else(invalid)?;
    Ok(Some(Update {
        version: version.into(),
        name,
        url,
        checksum_url,
    }))
}
fn client() -> Result<reqwest::Client, AppError> {
    reqwest::Client::builder()
        .user_agent("QuotaNest-Windows")
        .timeout(Duration::from_secs(90))
        .redirect(reqwest::redirect::Policy::custom(|attempt| {
            let allowed = attempt.url().scheme() == "https"
                && matches!(
                    attempt.url().host_str(),
                    Some(
                        "github.com"
                            | "release-assets.githubusercontent.com"
                            | "objects.githubusercontent.com"
                    )
                );
            if allowed && attempt.previous().len() < 5 {
                attempt.follow()
            } else {
                attempt.stop()
            }
        }))
        .build()
        .map_err(|_| AppError::new("network"))
}
async fn download(client: &reqwest::Client, url: &str, limit: usize) -> Result<Vec<u8>, AppError> {
    let response = client
        .get(url)
        .send()
        .await
        .map_err(|_| AppError::new("network"))?;
    if !response.status().is_success() {
        return Err(AppError::new("update_download"));
    }
    deepseek::bounded(response, limit).await
}
pub async fn check() -> Result<Option<Update>, AppError> {
    let client = client()?;
    let data = download(
        &client,
        "https://api.github.com/repos/bloodkilory/QuotaNest/releases/latest",
        1048576,
    )
    .await?;
    let root: Value = serde_json::from_slice(&data).map_err(|_| AppError::new("invalid_update"))?;
    select_release(&root, env!("CARGO_PKG_VERSION"))
}
pub fn verify(bytes: &[u8], manifest: &str, name: &str) -> Result<(), AppError> {
    let expected = manifest
        .lines()
        .filter_map(|line| line.split_once("  "))
        .filter(|(_, file)| *file == name)
        .map(|(digest, _)| digest)
        .collect::<Vec<_>>();
    let actual = format!("{:x}", Sha256::digest(bytes));
    if expected.len() != 1 || expected[0].len() != 64 || expected[0] != actual {
        return Err(AppError::new("checksum_mismatch"));
    }
    Ok(())
}
pub async fn stage(update: &Update, directory: &Path) -> Result<PathBuf, AppError> {
    // Re-check server metadata at installation time; never accept frontend URLs.
    let current = check()
        .await?
        .filter(|u| u.version == update.version && u.url == update.url)
        .ok_or_else(|| AppError::new("invalid_update"))?;
    let client = client()?;
    let manifest = download(&client, &current.checksum_url, 65536).await?;
    let bytes = download(&client, &current.url, 134217728).await?;
    verify(
        &bytes,
        std::str::from_utf8(&manifest).map_err(|_| AppError::new("invalid_update"))?,
        &current.name,
    )?;
    tokio::fs::create_dir_all(directory)
        .await
        .map_err(|_| AppError::new("preferences_write"))?;
    let path = directory.join(format!("{}-{}", crate::models::now(), current.name));
    use tokio::io::AsyncWriteExt;
    let mut file = tokio::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&path)
        .await
        .map_err(|_| AppError::new("update_download"))?;
    file.write_all(&bytes)
        .await
        .map_err(|_| AppError::new("update_download"))?;
    file.sync_all()
        .await
        .map_err(|_| AppError::new("update_download"))?;
    Ok(path)
}
#[test]
fn checksum_rejects_wrong_missing_and_duplicate_entries() {
    let name = "QuotaNest-1.9.0-windows-x64-setup.exe";
    let bytes = b"synthetic installer";
    let manifest = format!("{:x}  {name}\n", Sha256::digest(bytes));
    let mac_entry = format!(
        "{:x}  QuotaNest-1.9.0.dmg\n",
        Sha256::digest(b"synthetic dmg")
    );
    assert!(verify(bytes, &manifest, name).is_ok());
    assert!(verify(bytes, &(mac_entry.clone() + &manifest), name).is_ok());
    assert!(verify(bytes, &(manifest.clone() + &mac_entry), name).is_ok());
    assert!(verify(bytes, &mac_entry, name).is_err());
    assert!(verify(b"tampered", &manifest, name).is_err());
    assert!(verify(bytes, &(manifest.clone() + &manifest), name).is_err());
}
