use crate::{
    deepseek,
    models::{self, AppError, Quota},
};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::{
    io::Read,
    path::{Path, PathBuf},
    time::Duration,
};
// Deliberately not Debug/Serialize: official OAuth never crosses IPC or logs.
pub struct Credential {
    token: String,
    pub generation: String,
    pub plan: Option<String>,
}
pub fn directory(home: &Path) -> Result<PathBuf, AppError> {
    match std::env::var_os("CLAUDE_CONFIG_DIR") {
        Some(path) if !path.is_empty() => {
            let path = PathBuf::from(path);
            if !path.is_absolute() {
                return Err(AppError::new("claude_config_invalid"));
            }
            Ok(path)
        }
        _ => Ok(home.join(".claude")),
    }
}
pub fn read_credentials(directory: &Path) -> Result<Credential, AppError> {
    let path = directory.join(".credentials.json");
    if std::fs::metadata(&path).is_ok_and(|m| !m.is_file()) {
        return Err(AppError::new("claude_login_unreadable"));
    }
    let file = std::fs::File::open(path).map_err(|e| {
        AppError::new(if e.kind() == std::io::ErrorKind::NotFound {
            "claude_login_missing"
        } else {
            "claude_login_unreadable"
        })
    })?;
    let mut data = Vec::new();
    file.take(1048577)
        .read_to_end(&mut data)
        .map_err(|_| AppError::new("claude_login_unreadable"))?;
    if data.len() > 1048576 {
        return Err(AppError::new("claude_login_unreadable"));
    }
    let root: Value =
        serde_json::from_slice(&data).map_err(|_| AppError::new("claude_login_unreadable"))?;
    let oauth = &root["claudeAiOauth"];
    let token = oauth["accessToken"]
        .as_str()
        .filter(|s| !s.is_empty() && s.len() <= 16384 && !s.bytes().any(|b| b.is_ascii_control()))
        .ok_or_else(|| AppError::new("claude_login_missing"))?;
    if let Some(expiry) = oauth.get("expiresAt") {
        let expiry = expiry
            .as_f64()
            .filter(|n| n.is_finite())
            .ok_or_else(|| AppError::new("claude_login_unreadable"))?;
        if expiry / 1000.0 <= models::now() as f64 {
            return Err(AppError::new("claude_login_expired"));
        }
    }
    if let Some(scopes) = oauth.get("scopes") {
        if !scopes
            .as_array()
            .is_some_and(|s| s.iter().any(|v| v.as_str() == Some("user:profile")))
        {
            return Err(AppError::new("claude_scope_missing"));
        }
    }
    Ok(Credential {
        token: token.into(),
        generation: format!("{:x}", Sha256::digest(token.as_bytes())),
        plan: oauth["subscriptionType"].as_str().map(str::to_owned),
    })
}
pub async fn fetch(credential: &Credential) -> Result<Quota, AppError> {
    fetch_url(credential, "https://api.anthropic.com/api/oauth/usage").await
}
async fn fetch_url(credential: &Credential, endpoint: &str) -> Result<Quota, AppError> {
    let client = deepseek::client()?;
    tokio::time::timeout(Duration::from_secs(30), async {
        for attempt in 0..2 {
            let result = async {
                let response = client
                    .get(endpoint)
                    .bearer_auth(&credential.token)
                    .header("anthropic-beta", "oauth-2025-04-20")
                    .header("Accept", "application/json")
                    .send()
                    .await
                    .map_err(|_| AppError::new("network"))?;
                if response.status().as_u16() != 200 {
                    return Err(deepseek::status_error(
                        response.status().as_u16(),
                        response
                            .headers()
                            .get("retry-after")
                            .and_then(|v| v.to_str().ok()),
                    ));
                }
                let data = deepseek::bounded(response, 1048576).await?;
                let root =
                    serde_json::from_slice(&data).map_err(|_| AppError::new("invalid_quota"))?;
                let mut quota = models::parse_claude(&root)?;
                quota.plan = credential.plan.clone();
                Ok(quota)
            }
            .await;
            match result {
                Err(ref e) if attempt == 0 && ["network", "server"].contains(&e.code.as_str()) => {
                    tokio::time::sleep(Duration::from_secs(1)).await
                }
                other => return other,
            }
        }
        Err(AppError::new("network"))
    })
    .await
    .unwrap_or_else(|_| Err(AppError::new("network")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::{
        io::{AsyncReadExt, AsyncWriteExt},
        net::TcpListener,
    };
    async fn serve(replies: Vec<(u16, &str, &str)>) -> (String, tokio::task::JoinHandle<()>) {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}/api/oauth/usage", listener.local_addr().unwrap());
        let replies = replies
            .into_iter()
            .map(|(s, h, b)| (s, h.to_owned(), b.to_owned()))
            .collect::<Vec<_>>();
        let task = tokio::spawn(async move {
            for (status, headers, body) in replies {
                let (mut socket, _) = listener.accept().await.unwrap();
                let mut request = vec![0; 16384];
                let n = socket.read(&mut request).await.unwrap();
                let request = String::from_utf8_lossy(&request[..n]).to_lowercase();
                assert!(request.starts_with("get /api/oauth/usage "));
                assert!(request.contains("authorization: bearer synthetic-oauth"));
                assert!(request.contains("anthropic-beta: oauth-2025-04-20"));
                socket.write_all(format!("HTTP/1.1 {status} Test\r\nContent-Length: {}\r\nConnection: close\r\n{headers}\r\n{body}",body.len()).as_bytes()).await.unwrap();
            }
        });
        (url, task)
    }
    fn credential() -> Credential {
        Credential {
            token: "synthetic-oauth".into(),
            generation: "fixture".into(),
            plan: Some("max".into()),
        }
    }
    #[tokio::test]
    async fn official_headers_and_one_transient_retry_keep_plan() {
        let (url, task) = serve(vec![
            (503, "", ""),
            (200, "", r#"{"five_hour":{"utilization":18}}"#),
        ])
        .await;
        let quota = fetch_url(&credential(), &url).await.unwrap();
        assert_eq!(quota.plan.as_deref(), Some("max"));
        assert_eq!(quota.windows[0].remaining, Some(82.0));
        task.await.unwrap();
    }
    #[tokio::test]
    async fn authentication_redirect_and_rate_limit_do_not_retry() {
        for (status, headers, code) in [
            (401, "", "unauthorized"),
            (403, "", "forbidden"),
            (
                302,
                "Location: http://127.0.0.1:1/leak\r\n",
                "redirect_refused",
            ),
            (429, "Retry-After: 600\r\n", "rate_limited"),
        ] {
            let (url, task) = serve(vec![(status, headers, "")]).await;
            let error = fetch_url(&credential(), &url).await.unwrap_err();
            assert_eq!(error.code, code);
            if status == 429 {
                assert!(error.retry_at.unwrap() >= models::now() + 599);
            }
            task.await.unwrap();
        }
    }
}
