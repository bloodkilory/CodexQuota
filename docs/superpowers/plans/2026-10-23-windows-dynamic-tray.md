# Windows dynamic tray + hover usage

User explicitly requests implementation and screenshots: centered quota number, hollow progress ring, platform brand color for both, hover for quota details, click for settings/update. No floating desktop capsule. Preserve Mac.

1. Pure Rust anti-aliased icon renderer (embedded OFL Inter digits); quota remaining ring and centered 0–100. Codex teal, Claude terracotta, DeepSeek blue. Unknown dash and stale marker; API wallet symbol + empty track, no invented percentage. Unit tests for colors, ring coverage and states.
2. Separate nonfocusable, initially hidden hover WebView anchored to tray rect, monitor work area clamped. 250ms entry delay, 350ms dismissal, moving into hover card preserves it. All native UI calls outside service/controller mutexes. Main opens controls/settings on tray click, hides on blur/close, remains keyboard accessible. No service/routing changes.
3. Windows beta.3. Local Rust/frontend tests and Mac regression; Windows real native tray mouse hover/click tests, monitor-clamped card screenshots and installer/update/uninstall. Download test screenshots and show them in conversation. Keep feature branch, no main merge or formal Release.
