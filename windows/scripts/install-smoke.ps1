$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/..").Path
$installer = @(Get-ChildItem "$root/dist-artifacts/*-setup.exe")[0].FullName
$target = Join-Path $env:RUNNER_TEMP 'QuotaNest Smoke Install'
$process = Start-Process -FilePath $installer -ArgumentList "/S /D=$target" -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Installer exited $($process.ExitCode)" }
$exe = Join-Path $target 'QuotaNest.exe'
if (-not (Test-Path $exe)) { throw 'Installed app missing' }
# Exercise NSIS update mode with real per-user preferences and Run registration.
$preferencesDir = Join-Path $env:APPDATA 'app.quotanest.windows'
New-Item -ItemType Directory -Path $preferencesDir -Force | Out-Null
$preferencesFile = Join-Path $preferencesDir 'preferences.json'
$preferences = @{source='codex'; language='zh'; directory=(Join-Path $env:USERPROFILE '.cc-switch'); autostart=$true} | ConvertTo-Json
[IO.File]::WriteAllText($preferencesFile, $preferences, [Text.UTF8Encoding]::new($false))
$beforeHash = (Get-FileHash $preferencesFile -Algorithm SHA256).Hash
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
New-Item -Path $runKey -Force | Out-Null
$runValue = '"' + $exe + '" --background'
New-ItemProperty -Path $runKey -Name QuotaNest -Value $runValue -PropertyType String -Force | Out-Null
$process = Start-Process -FilePath $installer -ArgumentList "/S /UPDATE /D=$target" -Wait -PassThru
if ($process.ExitCode -ne 0) { throw 'Update installer failed' }
if ((Get-FileHash $preferencesFile -Algorithm SHA256).Hash -ne $beforeHash) { throw 'Update changed saved preferences' }
if ((Get-ItemPropertyValue -Path $runKey -Name QuotaNest) -ne $runValue) { throw 'Update lost launch-at-sign-in registration' }
Write-Host 'PASS NSIS update preserves preferences and current-user autostart'
# Run the actual installed binary in fixture mode through WebView2.
$env:QUOTANEST_TEST_EXE = $exe
npm run e2e
if ($LASTEXITCODE -ne 0) { throw 'Installed GUI smoke failed' }
Get-Process QuotaNest -ErrorAction SilentlyContinue | Stop-Process -Force
$uninstaller = Get-ChildItem $target -Filter '*uninstall*.exe' | Select-Object -First 1
if (-not $uninstaller) { throw 'Uninstaller missing' }
$process = Start-Process -FilePath $uninstaller.FullName -ArgumentList '/S' -Wait -PassThru
if ($process.ExitCode -ne 0) { throw 'Uninstaller failed' }
# NSIS may spawn a temporary uninstaller and return before its cleanup completes.
for ($i=0; $i -lt 30 -and (Test-Path $exe); $i++) { Start-Sleep -Seconds 1 }
if (Test-Path $exe) { throw 'Installed executable remained after uninstall' }
Write-Host 'PASS installer, installed WebView2 app, uninstaller'
