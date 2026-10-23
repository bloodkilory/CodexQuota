param([string]$App,[string]$Node,[string]$Driver,[string]$Root)
$ErrorActionPreference='Stop'
Set-Location $Root
$code=1
try {
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 $principal=[Security.Principal.WindowsPrincipal]::new($identity)
 if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'GUI smoke must run with a filtered, non-admin token'}
 'PASS native GUI test runs without administrator privileges' | Out-File 'e2e-results/scheduled-e2e.log'
 $env:QUOTANEST_TEST_EXE=$App
 $env:PATH="$Driver;$env:PATH"
 & $Node tests/e2e.mjs *>> 'e2e-results/scheduled-e2e.log'
 $code=$LASTEXITCODE
} catch { $_ | Out-File 'e2e-results/scheduled-e2e.log' -Append }
finally { [IO.File]::WriteAllText((Join-Path $Root 'e2e-results/scheduled-exit.txt'),[string]$code) }
exit $code
