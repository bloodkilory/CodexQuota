#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc Sources/QuotaModels.swift Tests/main.swift -o .build/model-tests
.build/model-tests
swiftc -swift-version 5 Sources/QuotaModels.swift Sources/CodexClient.swift Tests/Protocol/main.swift -o .build/protocol-tests
.build/protocol-tests
swiftc Sources/QuotaModels.swift Sources/ProviderState.swift Sources/ProviderPayload.swift Tests/Providers/main.swift -o .build/provider-tests
.build/provider-tests
swiftc -swift-version 5 Sources/QuotaModels.swift Sources/CodexClient.swift Sources/BoundedCommand.swift Tests/Command/main.swift -o .build/command-tests
.build/command-tests

swiftc Sources/QuotaModels.swift Sources/ProviderState.swift Sources/ProviderMark.swift Sources/CapsuleView.swift Tests/Capsule/main.swift -o .build/capsule-tests
.build/capsule-tests


swiftc Sources/QuotaModels.swift Sources/CodexClient.swift Sources/KimiPayload.swift Sources/KimiQuotaClient.swift Tests/Kimi/main.swift -o .build/kimi-tests
.build/kimi-tests
swiftc Sources/QuotaModels.swift Sources/CodexClient.swift Sources/ProviderPayload.swift Sources/ChinaLoginPayload.swift Sources/ChinaLoginClients.swift Tests/ChinaLogin/main.swift -o .build/china-login-tests
.build/china-login-tests
swiftc Sources/QuotaModels.swift Sources/CodexClient.swift Sources/BoundedCommand.swift Sources/QoderPayload.swift Sources/QoderQuotaClient.swift Tests/Qoder/main.swift -o .build/qoder-tests
.build/qoder-tests
swiftc Sources/QuotaModels.swift Sources/CodexClient.swift Sources/ProviderPayload.swift Sources/ChinaLoginPayload.swift Sources/ChinaLoginClients.swift Sources/CodeBuddyPayload.swift Sources/CodeBuddyQuotaClient.swift Tests/CodeBuddy/main.swift -o .build/codebuddy-tests
.build/codebuddy-tests
swiftc -swift-version 5 Sources/UpdateModels.swift Sources/ReleaseUpdateClient.swift Sources/UpdateHelperContract.swift Sources/UpdateReplacement.swift Sources/UpdateInstaller.swift Sources/UpdatePrivilegeLauncher.swift Sources/LoginItemManager.swift Sources/CodexClient.swift Sources/QuotaModels.swift Tests/Updates/main.swift -o .build/update-tests
.build/update-tests
swiftc -swift-version 5 Sources/UpdateModels.swift Sources/UpdateHelperContract.swift Sources/UpdateReplacement.swift Helpers/Update/main.swift -o .build/update-helper-tests
if .build/update-helper-tests --request /unapproved/request.json; then
    echo 'FAIL helper accepted invalid request'; exit 1
fi
# Optional offline official-WASM fixture test; never downloads or reads user credentials.
if [[ -n "${QODER_TEST_BUNDLE:-}" ]]; then
    node Tests/Qoder/helper.cjs "$QODER_TEST_BUNDLE"
fi
