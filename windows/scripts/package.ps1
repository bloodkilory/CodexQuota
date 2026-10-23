$ErrorActionPreference = 'Stop'
$version = (Get-Content "$PSScriptRoot/../package.json" -Raw | ConvertFrom-Json).version
$root = (Resolve-Path "$PSScriptRoot/..").Path
$bundle = @(Get-ChildItem "$root/src-tauri/target/release/bundle/nsis/*-setup.exe")
if ($bundle.Count -ne 1) { throw 'Expected exactly one x64 NSIS installer' }
$out = "$root/dist-artifacts"
New-Item -ItemType Directory -Path $out -Force | Out-Null
$name = "QuotaNest-$version-windows-x64-setup.exe"
Copy-Item $bundle[0].FullName "$out/$name"
$digest = (Get-FileHash "$out/$name" -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$out/SHA256SUMS.txt", "$digest  $name`n", [Text.UTF8Encoding]::new($false))
Copy-Item "$PSScriptRoot/../../docs/windows/README.md" "$out/README.md"
Copy-Item "$PSScriptRoot/../../docs/windows/feature-parity.md" "$out/feature-parity.md"
Write-Host "Packaged $name with SHA-256: $digest"
