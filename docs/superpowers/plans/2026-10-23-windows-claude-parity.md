# Windows Claude and feature parity — implementation

User requests Claude official quota first, Mac parity audit, then a tested new beta. Continue isolated feat/windows-beta; preserve Mac and do not merge main/publish formal Release.

1. Read native Windows Claude Code OAuth from CLAUDE_CONFIG_DIR (absolute) or USERPROFILE/.claude/.credentials.json. Never invoke helper, API key, refresh token, WSL, or change client files. Fixed Anthropic usage URL/header, bounded response/30s total/one transient retry, Retry-After and credential-generation invalidation. Tests cover credential/parser/transport and service transitions.
2. One selector with Codex, Claude subscription and saved DeepSeek connections. Preserve grouped Claude windows, let users choose the tray quota period/currency, persist selections. Keep unknown/stale semantics; clear on changed official credentials. Review Mac features in a bilingual parity table; don't present unported clients as supported.
3. Bump Windows to 1.9.0-beta.2. Run backend/frontend/static checks, unchanged Mac regression, Windows CI real installer/update/GUI/uninstall. Extend native smoke to Claude and unavailable login, quota-period/currency selection. Deliver Actions installer+checksum and evidence. Real Windows accounts remain beta acceptance, never claim synthetic tests prove real accounts.
