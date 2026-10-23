use quotanest_windows::{claude, models};
use serde_json::json;
use std::fs;
#[test]
fn official_login_is_read_only_and_api_keys_are_not_oauth() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join(".credentials.json");
    let data = json!({"claudeAiOauth":{"accessToken":"synthetic-oauth","expiresAt":(models::now()+3600)*1000,"scopes":["user:profile"],"subscriptionType":"max"}}).to_string();
    fs::write(&path, &data).unwrap();
    let credential = claude::read_credentials(dir.path()).ok().unwrap();
    assert_eq!(credential.plan.as_deref(), Some("max"));
    assert_eq!(fs::read_to_string(&path).unwrap(), data);
    fs::write(
        &path,
        json!({"apiKey":"not-subscription","env":{"ANTHROPIC_AUTH_TOKEN":"proxy"}}).to_string(),
    )
    .unwrap();
    assert_eq!(
        claude::read_credentials(dir.path()).err().unwrap().code,
        "claude_login_missing"
    );
}
#[test]
fn expired_or_profileless_login_has_actionable_errors_and_rotation_changes_identity() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join(".credentials.json");
    let write = |token: &str, expiry: u64, scopes: serde_json::Value| {
        fs::write(
            &path,
            json!({"claudeAiOauth":{"accessToken":token,"expiresAt":expiry,"scopes":scopes}})
                .to_string(),
        )
        .unwrap()
    };
    write("synthetic", 1, json!(["user:profile"]));
    assert_eq!(
        claude::read_credentials(dir.path()).err().unwrap().code,
        "claude_login_expired"
    );
    write(
        "synthetic",
        (models::now() + 3600) * 1000,
        json!(["user:inference"]),
    );
    assert_eq!(
        claude::read_credentials(dir.path()).err().unwrap().code,
        "claude_scope_missing"
    );
    write(
        "synthetic-a",
        (models::now() + 3600) * 1000,
        json!(["user:profile"]),
    );
    let first = claude::read_credentials(dir.path())
        .ok()
        .unwrap()
        .generation;
    write(
        "synthetic-b",
        (models::now() + 3600) * 1000,
        json!(["user:profile"]),
    );
    assert_ne!(
        first,
        claude::read_credentials(dir.path())
            .ok()
            .unwrap()
            .generation
    );
}
#[test]
fn claude_preserves_distinct_groups_and_iso_reset_times_without_inventing_zero() {
    let quota=models::parse_claude(&json!({"five_hour":{"utilization":24,"resets_at":"2026-10-23T10:00:00.000Z"},"seven_day":{"utilization":61},"seven_day_sonnet":{"utilization":7},"seven_day_opus":{"utilization":100}})).unwrap();
    assert_eq!(quota.windows.len(), 4);
    assert_eq!(quota.windows[0].remaining, Some(76.0));
    assert_eq!(quota.windows[0].minutes, Some(300));
    assert!(quota.windows[0].resets_at.unwrap() > 0.0);
    assert_eq!(quota.windows[2].label.as_deref(), Some("sonnet"));
    assert_eq!(quota.windows[3].remaining, Some(0.0));
    assert!(models::parse_claude(
        &json!({"five_hour":{"utilization":null},"seven_day":{"utilization":true}})
    )
    .is_err());
}
#[test]
fn claude_is_selectable_without_cc_switch_or_prior_login() {
    use quotanest_windows::service::{Preferences, Service};
    let dir = tempfile::tempdir().unwrap();
    let mut service = Service::new(Preferences::defaults(dir.path()));
    assert!(service.select("claude").is_ok());
}
#[test]
fn official_period_uses_tightest_group_and_display_choice_is_saved_per_source() {
    use quotanest_windows::service::{Data, Preferences, Service};
    let dir = tempfile::tempdir().unwrap();
    let mut service = Service::new(Preferences::defaults(dir.path()));
    service.select("claude").unwrap();
    let request = service.begin().unwrap();
    service.finish(request,Ok(Data::Quota(models::parse_claude(&json!({"five_hour":{"utilization":18},"seven_day":{"utilization":39},"seven_day_opus":{"utilization":80}})).unwrap())));
    assert_eq!(service.display_amount(), "82%");
    service.select_display("10080").unwrap();
    assert_eq!(service.display_amount(), "20%");
    service.select("codex").unwrap();
    assert_eq!(service.display_amount(), "—");
    service.select("claude").unwrap();
    assert_eq!(
        service.state.preferences.display.get("claude").unwrap(),
        "10080"
    );
}
#[test]
fn cc_switch_directory_changes_do_not_clear_official_cooldown() {
    use quotanest_windows::service::{Preferences, Service};
    let dir = tempfile::tempdir().unwrap();
    let mut service = Service::new(Preferences::defaults(dir.path()));
    service.select("claude").unwrap();
    service.validate_credential("official");
    let request = service.begin().unwrap();
    service.finish(
        request,
        Err(models::AppError {
            code: "rate_limited".into(),
            retry_at: Some(models::now() + 3600),
        }),
    );
    service.set_directory("new CC Switch folder".into());
    assert!(service.validate_credential("official").is_some());
    assert_eq!(service.state.preferences.source, "claude");
}
#[test]
fn missing_primary_duration_uses_first_explicit_period_in_tray() {
    use quotanest_windows::service::{Data, Preferences, Service};
    let dir = tempfile::tempdir().unwrap();
    let mut service = Service::new(Preferences::defaults(dir.path()));
    let request = service.begin().unwrap();
    service.finish(request,Ok(Data::Quota(models::parse_codex(&json!({"rateLimits":{"primary":{"usedPercent":20},"secondary":{"usedPercent":50,"windowDurationMins":10080}}})).unwrap())));
    assert_eq!(service.display_amount(), "50%");
}
