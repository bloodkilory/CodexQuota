#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc Sources/QuotaModels.swift Tests/main.swift -o .build/model-tests
.build/model-tests
swiftc -swift-version 5 Sources/QuotaModels.swift Sources/CodexClient.swift Tests/Protocol/main.swift -o .build/protocol-tests
.build/protocol-tests
swiftc Sources/QuotaModels.swift Sources/ProviderPayload.swift Tests/Providers/main.swift -o .build/provider-tests
.build/provider-tests
swiftc -swift-version 5 Sources/QuotaModels.swift Sources/CodexClient.swift Sources/BoundedCommand.swift Tests/Command/main.swift -o .build/command-tests
.build/command-tests

swiftc Sources/QuotaModels.swift Sources/ProviderState.swift Sources/ProviderMark.swift Sources/CapsuleView.swift Tests/Capsule/main.swift -o .build/capsule-tests
.build/capsule-tests
