# Qoder and CodeBuddy source evidence (2026-10-12)

## Qoder experimental integration

Reviewed official npm distribution `@qoder-ai/qodercli@1.1.68`, downloaded directly from https://registry.npmjs.org/@qoder-ai/qodercli/-/qodercli-1.1.68.tgz . No installation scripts or CLI entry point were executed.

Official references:

- https://docs.qoder.com/cli/installation identifies the official npm package.
- https://docs.qoder.com/cli/authentication documents browser login and automatic token refresh.
- https://docs.qoder.com/cli/usage documents interactive `/usage` and plan/add-on/organization credits.

Static source `bundle/qodercli.js` defines `account.getQuotaUsage` as GET `/api/v2/quota/usage` with bearer authentication. Global production base is `https://openapi.qoder.sh`; CN builds use `https://openapi.qoder.com.cn`. This implementation supports only the reviewed global npm build, rejects an unknown build marker or WASM hash, and never forwards credentials to a configurable host.

Account quota schema accepts `user_quota`/`userQuota`, `add_on_quota`/`addOnQuota`, `org_resource_package`/`orgResourcePackage`/`shared_quota`/`sharedQuota`. Each has numeric `used` and `total`; the organization resource uses `cap` or `total` and `available`. The app calculates usage from these values. It deliberately does not infer a 30-day period or interpret the unverified units of `expires_at` as a reset time. The official plan endpoint `/api/v2/user/plan` has `plan_tier_name`, `start_date`, `end_date`, but is not needed by this implementation.

The default browser login cache is `~/.qoder/.auth/user`; its machine identifier is `~/.qoder/.auth/machine_id`. Source calls `credential_storage_decrypt(encrypted, machineId.slice(0,16))` on its embedded official WASM. The helper extracts that blob as data, verifies SHA-256 `6419471effa631519def7797d76d7ede38b9fcfa9a83c2148c8ef5d43355b43d` (298606 bytes), and invokes the matching exported wasm-bindgen ABI. No CLI JavaScript is evaluated. Unsupported WASM imports fail closed. Cryptography is supplied exclusively by that official WASM; no guessed cipher is implemented or bundled.

The resulting JSON must have `login_method: "browser"`, no `personal_access_token`, and an unexpired numeric `expire_time` (seconds, confirmed by auth source). Bearer is `security_oauth_token`, falling back to `access_token`, as in the official source. API keys, PATs, job tokens, environment overrides, custom servers, custom config directories, native-only CLI distributions, and CN CLI builds are unsupported. Expired login requires refreshing in the official client. The helper writes no credential files and never refreshes credentials.

The runtime requires Node.js and a compatible official npm CLI installation. The build must copy `Helpers/qoder-usage.cjs` into app `Contents/Resources/`. The helper performs one fixed HTTPS GET, does not follow redirects, bounds input/response sizes, exits after 25 seconds, and emits sanitized error identifiers only. It never launches an agent, loads workspace configuration, or calls a model. The app clears inherited Node injection variables by passing a minimal subprocess environment.

### Verification

- Synthetic credential encrypted with the official WASM and decoded by the independent helper.
- Rejects PAT login, expired login, header control characters, invalid keys, unknown bundle format.
- Payload tests cover plan/add-on/org percentages, no invented reset duration, malformed/boolean/negative/zero-total values.
- No user credentials inspected; no live account or quota query tested. Treat as experimental.

Run `node Tests/Qoder/helper.cjs /path/to/official/package/bundle/qodercli.js` with the reviewed npm package. Swift payload tests: `swiftc Sources/QuotaModels.swift Sources/CodexClient.swift Sources/BoundedCommand.swift Sources/QoderPayload.swift Sources/QoderQuotaClient.swift Tests/Qoder/main.swift -o /tmp/qoder-payload-tests && /tmp/qoder-payload-tests`.

## CodeBuddy follow-up evidence

The initial CLI-only investigation did not identify account quota requests. Subsequent inspection of the official VS Code extension and account web application found a supported login-reuse query path. CodeBuddy has now been implemented separately; see [CodeBuddy source evidence](codebuddy.md) for the authoritative endpoints, schema, credential storage, limitations, and validation. CLI per-session credit usage remains unsuitable as account quota.
