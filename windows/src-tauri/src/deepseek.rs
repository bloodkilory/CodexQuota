use crate::{
    cc_switch::Credential,
    models::{self, AppError, Wallet},
};
use reqwest::{Client, Response};
use std::time::{Duration, UNIX_EPOCH};
pub fn client() -> Result<Client, AppError> {
    Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(15))
        .connect_timeout(Duration::from_secs(10))
        .user_agent("QuotaNest-Windows")
        .build()
        .map_err(|_| AppError::new("network"))
}
pub async fn bounded(mut response: Response, limit: usize) -> Result<Vec<u8>, AppError> {
    if response.content_length().is_some_and(|n| n > limit as u64) {
        return Err(AppError::new("response_too_large"));
    }
    let mut data = Vec::new();
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|_| AppError::new("network"))?
    {
        if chunk.len() > limit - data.len() {
            return Err(AppError::new("response_too_large"));
        }
        data.extend_from_slice(&chunk);
    }
    Ok(data)
}
pub fn status_error(status: u16, retry_after: Option<&str>) -> AppError {
    let code = match status {
        401 => "unauthorized",
        403 => "forbidden",
        429 => "rate_limited",
        300..=399 => "redirect_refused",
        500..=599 => "server",
        _ => "http_error",
    };
    let retry_at = if status == 429 {
        Some(
            retry_after
                .and_then(|s| {
                    s.parse::<u64>()
                        .ok()
                        .map(|n| models::now().saturating_add(n))
                        .or_else(|| {
                            httpdate::parse_http_date(s)
                                .ok()
                                .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                                .map(|v| v.as_secs())
                        })
                })
                .unwrap_or_else(|| models::now() + 60),
        )
    } else {
        None
    };
    AppError {
        code: code.into(),
        retry_at,
    }
}
pub async fn fetch(credential: &Credential) -> Result<Vec<Wallet>, AppError> {
    let client = client()?;
    tokio::time::timeout(Duration::from_secs(30), async {
        for attempt in 0..2 {
            let result = async {
                let response = client
                    .get("https://api.deepseek.com/user/balance")
                    .bearer_auth(&credential.token)
                    .send()
                    .await
                    .map_err(|_| AppError::new("network"))?;
                if response.status().as_u16() != 200 {
                    return Err(status_error(
                        response.status().as_u16(),
                        response
                            .headers()
                            .get("retry-after")
                            .and_then(|s| s.to_str().ok()),
                    ));
                }
                let data = bounded(response, 1048576).await?;
                let value =
                    serde_json::from_slice(&data).map_err(|_| AppError::new("invalid_balance"))?;
                models::parse_balance(&value)
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
#[test]
fn retry_after_does_not_turn_auth_failure_into_retry() {
    assert_eq!(status_error(401, None).retry_at, None);
    assert_eq!(status_error(302, None).code, "redirect_refused");
    assert!(status_error(429, Some("120")).retry_at.unwrap() >= models::now() + 119);
    assert_eq!(
        status_error(429, Some("Wed, 21 Oct 2037 07:28:00 GMT")).retry_at,
        Some(
            httpdate::parse_http_date("Wed, 21 Oct 2037 07:28:00 GMT")
                .unwrap()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs()
        )
    );
}
