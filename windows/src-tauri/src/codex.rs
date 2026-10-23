use crate::models::{self, AppError, Quota};
use serde_json::{json, Value};
use std::{
    path::{Path, PathBuf},
    process::Stdio,
    time::Duration,
};
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    process::Command,
};
pub fn executable(home: &Path) -> Result<PathBuf, AppError> {
    let mut directories =
        std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default()).collect::<Vec<_>>();
    if let Some(appdata) = std::env::var_os("APPDATA") {
        directories.push(PathBuf::from(appdata).join("npm"));
    }
    find_executable(home, &directories, cfg!(windows)).ok_or_else(|| AppError::new("codex_missing"))
}
async fn response<R: tokio::io::AsyncBufRead + Unpin>(
    reader: &mut R,
    id: u64,
) -> Result<Value, AppError> {
    let mut total = 0;
    loop {
        let mut line = Vec::new();
        loop {
            let buffer = reader
                .fill_buf()
                .await
                .map_err(|_| AppError::new("protocol"))?;
            if buffer.is_empty() {
                return Err(AppError::new("protocol"));
            }
            let size = buffer
                .iter()
                .position(|b| *b == b'\n')
                .map(|n| n + 1)
                .unwrap_or(buffer.len());
            if total + size > 1048576 {
                return Err(AppError::new("response_too_large"));
            }
            line.extend_from_slice(&buffer[..size]);
            reader.consume(size);
            total += size;
            if line.last() == Some(&b'\n') {
                break;
            }
        }
        let value: Value = serde_json::from_slice(&line).map_err(|_| AppError::new("protocol"))?;
        if value["id"].as_u64() != Some(id) {
            continue;
        }
        if let Some(error) = value.get("error") {
            let message = error["message"].as_str().unwrap_or("").to_lowercase();
            let code = if message.contains("401")
                || message.contains("unauthorized")
                || message.contains("not logged")
            {
                "unauthorized"
            } else if message.contains("429") {
                "rate_limited"
            } else if [-32600, -32602].contains(&error["code"].as_i64().unwrap_or(0)) {
                "old_protocol"
            } else {
                "protocol"
            };
            return Err(AppError::new(code));
        }
        return value
            .get("result")
            .cloned()
            .ok_or_else(|| AppError::new("protocol"));
    }
}
pub async fn fetch_path(path: &Path) -> Result<Quota, AppError> {
    let mut command = Command::new(path);
    command
        .arg("app-server")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .kill_on_drop(true);
    #[cfg(windows)]
    command.creation_flags(0x08000000); // CREATE_NO_WINDOW; execute .exe directly, never cmd.exe.
    let mut child = command
        .spawn()
        .map_err(|_| AppError::new("codex_missing"))?;
    let result=tokio::time::timeout(Duration::from_secs(30),async {
        let mut stdin=child.stdin.take().ok_or_else(||AppError::new("protocol"))?;
        let mut reader=BufReader::new(child.stdout.take().ok_or_else(||AppError::new("protocol"))?);
        async fn send<W:tokio::io::AsyncWrite+Unpin>(stdin:&mut W,value:Value)->Result<(),AppError> {
            stdin.write_all(format!("{value}\n").as_bytes()).await.map_err(|_|AppError::new("protocol"))
        }
        send(&mut stdin,json!({"id":1,"method":"initialize","params":{"clientInfo":{"name":"quotanest_windows","version":env!("CARGO_PKG_VERSION")}}})).await?;
        response(&mut reader,1).await?;
        send(&mut stdin,json!({"method":"initialized"})).await?;
        send(&mut stdin,json!({"id":2,"method":"account/rateLimits/read","params":{"excludeResetCreditDetails":true}})).await?;
        let value=match response(&mut reader,2).await {
            Err(e) if e.code=="old_protocol"=>{
                send(&mut stdin,json!({"id":3,"method":"account/rateLimits/read","params":null})).await?; response(&mut reader,3).await?
            }, other=>other?
        };
        models::parse_codex(&value)
    }).await.unwrap_or_else(|_|Err(AppError::new("network")));
    let _ = child.kill().await;
    let _ = child.wait().await;
    result
}
pub async fn fetch(home: &Path) -> Result<Quota, AppError> {
    fetch_path(&executable(home)?).await
}
#[tokio::test]
async fn rpc_frames_are_bounded_and_notification_not_used_as_result() {
    let mut reader =
        BufReader::new(&b"{\"method\":\"notice\"}\n{\"id\":2,\"result\":{\"ok\":true}}\n"[..]);
    assert_eq!(response(&mut reader, 2).await.unwrap()["ok"], true);
    let data = vec![b'x'; 1048577];
    let mut reader = BufReader::new(data.as_slice());
    assert_eq!(
        response(&mut reader, 2).await.unwrap_err().code,
        "response_too_large"
    );
}

pub fn find_executable(home: &Path, directories: &[PathBuf], windows: bool) -> Option<PathBuf> {
    let name = if windows { "codex.exe" } else { "codex" };
    let mut candidates = vec![
        home.join(".local/bin").join(name),
        home.join(".cargo/bin").join(name),
    ];
    for directory in directories {
        candidates.push(directory.join(name));
        if windows {
            for base in [
                "node_modules/@openai/codex-win32-x64/vendor",
                "node_modules/@openai/codex/node_modules/@openai/codex-win32-x64/vendor",
                "node_modules/@openai/codex/vendor",
            ] {
                candidates.push(
                    directory
                        .join(base)
                        .join("x86_64-pc-windows-msvc/bin/codex.exe"),
                );
            }
            candidates.push(
                directory.join(
                    "node_modules/@openai/codex/vendor/x86_64-pc-windows-msvc/codex/codex.exe",
                ),
            );
        }
    }
    candidates.into_iter().find(|p| p.is_file())
}
