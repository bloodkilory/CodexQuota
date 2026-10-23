$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/..").Path
$installer = @(Get-ChildItem "$root/dist-artifacts/*-setup.exe")[0].FullName
$target = Join-Path $env:RUNNER_TEMP 'QuotaNest Smoke Install'
$process = Start-Process -FilePath $installer -ArgumentList "/S /D=$target" -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Installer exited $($process.ExitCode)" }
$exe = Join-Path $target 'QuotaNest.exe'
if (-not (Test-Path $exe)) { throw 'Installed app missing' }
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
