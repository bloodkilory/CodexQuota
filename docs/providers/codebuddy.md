# CodeBuddy — experimental official-login adapter

Not tested with an authenticated account. Synthetic quota, SQLite selection, decryption and token-validation tests pass. The supported login is the mainland personal account in Tencent's official VS Code CodeBuddy extension, using the default macOS VS Code profile only.

## Sources and observed contracts

- [Official extension listing](https://marketplace.visualstudio.com/items?itemName=Tencent-Cloud.coding-copilot) and [official VSIX download](https://marketplace.visualstudio.com/_apis/public/gallery/publishers/Tencent-Cloud/vsextensions/coding-copilot/latest/vspackage), inspected version `4.12.39997873`, decompressed VSIX SHA-256 `8d5dd93a77dfa40ead5afd5aa7a0c7e180d7c1e3424e5060b60065a0693371c7`. Its `product.json` sets authentication ID `Tencent-Cloud.coding-copilot`. `out/extension/index.js` derives `<authentication.id>.new.accessToken` and stores JSON through SecretStorage. The JSON contains `auth.accessToken` and `auth.domain`; legacy top-level aliases are deliberately not used.
- VS Code's [ExtensionSecrets](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/api/common/extHostSecrets.ts), [key construction](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/api/browser/mainThreadSecretState.ts), [storage prefix](https://github.com/microsoft/vscode/blob/main/src/vs/platform/secrets/common/secrets.ts), and [encryption service](https://github.com/microsoft/vscode/blob/main/src/vs/platform/encryption/electron-main/encryptionMainService.ts) establish the normalized extension ID, exact secret key, and serialized encrypted Buffer format.
- [Chromium macOS encryption](https://github.com/chromium/chromium/blob/134.0.6998.89/components/os_crypt/sync/os_crypt_mac.mm) specifies `v10`, PBKDF2-HMAC-SHA1 with `saltysalt` and 1003 iterations, AES-128-CBC, and a fixed 16-space IV. The implementation decrypts the entire ciphertext and parses complete JSON. It does not discard the first plaintext block or use regex to salvage partial secrets.
- [Official usage page](https://www.codebuddy.cn/profile/plans-usage), inspected [user-center bundle](https://assets.workbuddy.cn/web/usercenter/f44571e76d8fdb634ca833a69c93174b1cd1508f/assets/index-DwvrNUFn.js) and [request/config bundle](https://assets.workbuddy.cn/web/usercenter/f44571e76d8fdb634ca833a69c93174b1cd1508f/assets/config-BcwEa1F4.js) establish POST `/billing/meter/get-user-resource`, Bearer authentication, product `p_tcaca`, valid/used-up statuses 0/3, and the raw response `data.Response.Data.Accounts` with `TotalCount`. Capacity types are total=1, cycle=2, slice=4. Current cycle precision fields take precedence; slice accounts use `SlicePeriodUsageDetails` for the requested day.

## Implementation boundaries

Reads exactly one SQL key in `~/Library/Application Support/Code/User/globalStorage/state.vscdb` through SQLite's read-only mode. It does not enumerate secret rows, launch CLI tools, read browser cookies, inspect API keys, or access refresh-token chunks. The exact CodeBuddy row must exist before requesting `Code Safe Storage` / `Code Key` from macOS Keychain. Background access disallows interaction; an explicit “授权 CodeBuddy 登录读取” button may allow the normal OS authorization dialog. No credentials are persisted or logged.

The adapter accepts only a well-formed official `auth` object with a mainland domain and an unexpired JWT. The JWT expiry is a local preflight check, not signature verification; the official HTTPS endpoint authenticates the token. Non-personal account types and international login domains are unsupported.

Requests use the fixed `https://www.codebuddy.cn` endpoint and existing bounded ephemeral transport with redirects disabled. The query requests active and exhausted packages, 200 rows, current validity, and the current Shanghai day for slice allowances. It omits the optional package-code filter to request all packages for the product; this combination has not been live-verified. More than one page, ambiguous slices, missing precision fields, and malformed quota data fail visibly. No check-ins, rewards, purchases or other account mutations occur.

All current package totals, including exhausted packages, remain in the denominator. Future cycle/slice credits are not counted. The displayed aggregate has a “当前积分” label and no invented fixed window or shared reset time. It is a credit aggregate, not an estimate of remaining model calls.

## Verification

```sh
swiftc Sources/QuotaModels.swift Sources/CodexClient.swift Sources/ProviderPayload.swift Sources/ChinaLoginPayload.swift Sources/ChinaLoginClients.swift Sources/CodeBuddyPayload.swift Sources/CodeBuddyQuotaClient.swift Tests/CodeBuddy/main.swift -o /tmp/quotanest-codebuddy-tests
/tmp/quotanest-codebuddy-tests
```

Tests cover exhausted denominator accounting, cycle precedence, slice selection, incomplete pages, errors, expired/non-mainland credentials, exact SQLite selection, and a separately generated OpenSSL decryption fixture. No actual login, Keychain item or authenticated endpoint was accessed.
