use quotanest_windows::{cc_switch, models, updates};
use serde_json::json;
use std::fs;

fn store() -> (tempfile::TempDir, rusqlite::Connection) {
    let dir = tempfile::tempdir().unwrap();
    let db = rusqlite::Connection::open(dir.path().join("cc-switch.db")).unwrap();
    db.execute_batch("PRAGMA user_version=20; CREATE TABLE providers(id TEXT, app_type TEXT, name TEXT, settings_config TEXT, is_current INTEGER);").unwrap();
    (dir, db)
}
fn insert(db: &rusqlite::Connection, endpoint: &str, token: &str) {
    db.execute(
        "INSERT INTO providers VALUES ('demo','claude','DeepSeek',?1,1)",
        [json!({"env":{"ANTHROPIC_BASE_URL":endpoint,"ANTHROPIC_AUTH_TOKEN":token}}).to_string()],
    )
    .unwrap();
}
#[test]
fn discovery_is_metadata_only_and_database_is_unchanged() {
    let (dir, db) = store();
    insert(
        &db,
        "https://api.deepseek.com/anthropic",
        "synthetic-secret",
    );
    drop(db);
    let before = fs::read(dir.path().join("cc-switch.db")).unwrap();
    let list = cc_switch::discover(dir.path()).unwrap();
    assert!(list[0].supported);
    assert_eq!(list[0].id, "claude|demo");
    assert!(!serde_json::to_string(&list)
        .unwrap()
        .contains("synthetic-secret"));
    let credential = cc_switch::resolve(dir.path(), "claude|demo").unwrap();
    assert!(!credential.generation.is_empty());
    assert_eq!(before, fs::read(dir.path().join("cc-switch.db")).unwrap());
}
#[test]
fn third_party_query_credentials_and_unknown_schema_are_rejected() {
    for endpoint in [
        "http://api.deepseek.com",
        "https://api.deepseek.com.evil.test",
        "https://user@api.deepseek.com",
        "https://api.deepseek.com?key=private",
        "https://api.deepseek.com:443",
    ] {
        let (dir, db) = store();
        insert(&db, endpoint, "fake");
        assert!(
            !cc_switch::discover(dir.path()).unwrap()[0].supported,
            "{endpoint}"
        );
        assert!(cc_switch::resolve(dir.path(), "claude|demo").is_err());
    }
    let (dir, db) = store();
    db.execute_batch("PRAGMA user_version=99").unwrap();
    assert_eq!(
        cc_switch::discover(dir.path()).unwrap_err().code,
        "incompatible_source"
    );
}
#[test]
fn credentials_change_generation_and_placeholders_are_not_keys() {
    let (dir, db) = store();
    insert(&db, "https://api.deepseek.com", "one");
    let first = cc_switch::resolve(dir.path(), "claude|demo")
        .unwrap()
        .generation;
    db.execute("UPDATE providers SET settings_config=?1",[json!({"env":{"ANTHROPIC_BASE_URL":"https://api.deepseek.com","ANTHROPIC_API_KEY":"two"}}).to_string()]).unwrap();
    assert_ne!(
        first,
        cc_switch::resolve(dir.path(), "claude|demo")
            .unwrap()
            .generation
    );
    db.execute("UPDATE providers SET settings_config=?1",[json!({"env":{"ANTHROPIC_BASE_URL":"https://api.deepseek.com","ANTHROPIC_AUTH_TOKEN":"CC_SWITCH_PROXY_MANAGED"}}).to_string()]).unwrap();
    assert!(cc_switch::resolve(dir.path(), "claude|demo").is_err());
}
#[test]
fn balance_keeps_decimal_total_and_distinct_currencies() {
    let value=models::parse_balance(&json!({"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"0.30","granted_balance":"0.10","topped_up_balance":"0.20"}]})).unwrap();
    assert_eq!(value[0].total, "0.30");
    assert_eq!(value[0].granted, "0.10");
    assert!(models::parse_balance(&json!({"is_available":true,"balance_infos":[]})).is_err());
    assert!(models::parse_balance(&json!({"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":0,"granted_balance":"NaN","topped_up_balance":"0"}]})).is_err());
}
#[test]
fn codex_uses_primary_bucket_and_unknown_does_not_become_zero() {
    let reading=models::parse_codex(&json!({"rateLimitsByLimitId":{"codex":{"planType":"Plus","primary":{"usedPercent":24,"windowDurationMins":300}},"other":{"primary":{"usedPercent":99}}}})).unwrap();
    assert_eq!(reading.windows[0].remaining, Some(76.0));
    assert!(models::parse_codex(&json!({"rateLimits":{"primary":{}}}))
        .unwrap()
        .windows[0]
        .remaining
        .is_none());
    assert!(models::parse_codex(&json!({})).is_err());
}
#[test]
fn release_never_selects_beta_mac_or_external_installer() {
    let release = json!({"tag_name":"v1.9.0","draft":false,"prerelease":false,"assets":[{"name":"QuotaNest-1.9.0-windows-x64-setup.exe","browser_download_url":"https://github.com/bloodkilory/QuotaNest/releases/download/v1.9.0/QuotaNest-1.9.0-windows-x64-setup.exe","size":1000},{"name":"SHA256SUMS.txt","browser_download_url":"https://github.com/bloodkilory/QuotaNest/releases/download/v1.9.0/SHA256SUMS.txt","size":96}]});
    assert!(updates::select_release(&release, "1.9.0-beta.1")
        .unwrap()
        .is_some());
    let mut beta = release.clone();
    beta["prerelease"] = json!(true);
    assert!(updates::select_release(&beta, "1.8.0").unwrap().is_none());
    let mut bad = release.clone();
    bad["assets"][0]["browser_download_url"] = json!("https://evil.test/a.exe");
    assert!(updates::select_release(&bad, "1.8.0").is_err());
    assert!(updates::select_release(&release, "2.0.0")
        .unwrap()
        .is_none());
}
#[test]
fn switching_source_and_generation_rejects_late_results() {
    use quotanest_windows::service::{Data, Preferences, Service};
    let (dir, _) = store();
    let prefs = Preferences::defaults(dir.path());
    let mut service = Service::new(prefs);
    let old = service.begin().unwrap();
    service.select("codex").unwrap();
    assert!(!service.finish(old, Ok(Data::Quota(models::Quota::default()))));
    assert!(service.snapshot().reading.data.is_none());
}
#[test]
fn a_transient_error_retains_values_but_changed_credentials_clear_them() {
    use quotanest_windows::service::{Data, Preferences, Service};
    let (dir, _) = store();
    let mut service = Service::new(Preferences::defaults(dir.path()));
    let first = service.begin().unwrap();
    assert!(service.finish(first, Ok(Data::Quota(models::Quota::default()))));
    let second = service.begin().unwrap();
    service.finish(second, Err(models::AppError::new("network")));
    assert!(service.snapshot().reading.data.is_some());
    service.credentials_changed();
    assert!(service.snapshot().reading.data.is_none());
}

#[test]
fn executable_discovery_handles_current_npm_packages_and_never_runs_cmd_shims() {
    let dir = tempfile::tempdir().unwrap();
    let prefix = dir.path().join("custom npm prefix with spaces");
    fs::create_dir_all(&prefix).unwrap();
    fs::write(prefix.join("codex.cmd"), "must never run").unwrap();
    assert!(quotanest_windows::codex::find_executable(
        dir.path(),
        std::slice::from_ref(&prefix),
        true
    )
    .is_none());
    for layout in ["node_modules/@openai/codex-win32-x64/vendor/x86_64-pc-windows-msvc/bin/codex.exe","node_modules/@openai/codex/node_modules/@openai/codex-win32-x64/vendor/x86_64-pc-windows-msvc/bin/codex.exe","node_modules/@openai/codex/vendor/x86_64-pc-windows-msvc/bin/codex.exe"] {
        let file=prefix.join(layout);fs::create_dir_all(file.parent().unwrap()).unwrap();fs::write(&file,"synthetic native binary").unwrap();
        assert_eq!(quotanest_windows::codex::find_executable(dir.path(),std::slice::from_ref(&prefix),true),Some(file.clone()));fs::remove_file(file).unwrap();
    }
}

#[test]
fn legacy_main_quota_wins_over_other_model_limits() {
    let reading=models::parse_codex(&json!({"rateLimits":{"primary":{"usedPercent":10}},"rateLimitsByLimitId":{"codex-spark":{"primary":{"usedPercent":99}}}})).unwrap();
    assert_eq!(reading.windows[0].remaining, Some(90.0));
    assert!(models::parse_codex(
        &json!({"rateLimitsByLimitId":{"other-model":{"primary":{"usedPercent":99}}}})
    )
    .is_err());
}
#[test]
fn changed_credentials_clear_previous_rate_limit_and_allow_local_validation() {
    use quotanest_windows::service::{Preferences, Service};
    let (dir, _) = store();
    let mut service = Service::new(Preferences::defaults(dir.path()));
    let request = service.begin().unwrap();
    service.finish(
        request,
        Err(models::AppError {
            code: "rate_limited".into(),
            retry_at: Some(models::now() + 3600),
        }),
    );
    service.credentials_changed();
    assert!(service.snapshot().reading.error.is_none());
    assert!(service.begin().is_some());
}
#[test]
fn unchanged_credential_keeps_cooldown_but_new_credential_does_not() {
    use quotanest_windows::service::{Preferences, Service};
    let (dir, _) = store();
    let mut service = Service::new(Preferences::defaults(dir.path()));
    assert!(service.validate_credential("old-generation").is_none());
    let request = service.begin().unwrap();
    service.finish(
        request,
        Err(models::AppError {
            code: "rate_limited".into(),
            retry_at: Some(models::now() + 3600),
        }),
    );
    assert!(service.begin().is_some()); // local validation must still run during cooldown
    assert!(service.validate_credential("old-generation").is_some());
    assert!(service.validate_credential("new-generation").is_none());
    assert!(service.snapshot().reading.error.is_none());
}
