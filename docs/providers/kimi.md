# Kimi Code — experimental OAuth quota adapter

This integration has synthetic fixture coverage only. It has not been tested against a signed-in account.

## Official evidence

Current official Kimi Code source pinned at `cbd754049a114ee36d1b27675c82819e4963c692`:

- [OAuth toolkit](https://github.com/MoonshotAI/kimi-code/blob/cbd754049a114ee36d1b27675c82819e4963c692/packages/oauth/src/toolkit.ts): default home `~/.kimi-code`, credentials subdirectory, `oauth/kimi-code` resolves to storage name `kimi-code`.
- [File token storage](https://github.com/MoonshotAI/kimi-code/blob/cbd754049a114ee36d1b27675c82819e4963c692/packages/oauth/src/storage.ts) and [wire fields](https://github.com/MoonshotAI/kimi-code/blob/cbd754049a114ee36d1b27675c82819e4963c692/packages/oauth/src/types.ts): JSON access_token, expires_at (Unix seconds), plus other fields that this adapter does not use.
- [Usage transport and parser](https://github.com/MoonshotAI/kimi-code/blob/cbd754049a114ee36d1b27675c82819e4963c692/packages/oauth/src/managed-usage.ts): GET `https://api.kimi.com/coding/v1/usages`, `Authorization: Bearer <access_token>`, Accept application/json. Raw `usages` contains optional `limit_5h`, `limit_7d`, `limit_month_total`, `limit_month_code`, each with `used_ratio` (fraction) and optional ISO `reset_time`.
- [Official synthetic usage examples](https://github.com/MoonshotAI/kimi-code/blob/cbd754049a114ee36d1b27675c82819e4963c692/packages/oauth/test/managed-usage.test.ts).

Archived official Python CLI pinned at `9ab1286b8fe4e6bcd116949a27ce5e0ac3389c82`:

- [Home directory](https://github.com/MoonshotAI/kimi-cli/blob/9ab1286b8fe4e6bcd116949a27ce5e0ac3389c82/src/kimi_cli/share.py) and [OAuth file storage](https://github.com/MoonshotAI/kimi-cli/blob/9ab1286b8fe4e6bcd116949a27ce5e0ac3389c82/src/kimi_cli/auth/oauth.py): fallback `~/.kimi/credentials/kimi-code.json`.
- [Legacy usage parser](https://github.com/MoonshotAI/kimi-cli/blob/9ab1286b8fe4e6bcd116949a27ce5e0ac3389c82/src/kimi_cli/ui/shell/usage.py): `usage` weekly summary; `limits[]` with `detail.limit`, used or remaining, `window.duration`, `window.timeUnit`, and reset timestamp aliases.

## Boundaries

Only the default mainland-China OAuth slot is supported. Custom homes, custom hosts, global region login slots, historical keyring credentials, configured API keys, API-key environment variables, and booster-wallet balances are not read. The newer default file takes precedence; an expired or malformed new login does not silently fall back to an older account. Read size is capped at 64 KiB. Missing/invalid/expired login requires the user to open the official client and log in or refresh there. No OAuth refresh endpoint or inference endpoint is called. No official client subprocess is launched, because its usage toolkit refreshes tokens.

The quota request uses ephemeral URLSession state, refuses redirects, and caps retained response bytes at 1 MiB through a streaming delegate. Errors exclude server response bodies and credential values. Monthly windows have an explicit monthly label and no invented fixed duration. Unknown quota shapes fail visibly rather than presenting zero usage.

## Fixture verification

```sh
swiftc Sources/QuotaModels.swift Sources/CodexClient.swift Sources/KimiPayload.swift Sources/KimiQuotaClient.swift Tests/Kimi/main.swift -o /tmp/quotanest-kimi-tests
/tmp/quotanest-kimi-tests
```

Tests use a temporary fake home and synthetic tokens only; they cover new and legacy response shapes, monthly duration semantics, missing/expired/API-key-only/oversize credential files, and the legacy OAuth path. Network behavior has not been live-tested.
