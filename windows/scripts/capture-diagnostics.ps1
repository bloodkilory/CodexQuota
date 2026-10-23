$ErrorActionPreference = 'Continue'
$out = Join-Path $PSScriptRoot '../e2e-results'
New-Item -ItemType Directory -Path $out -Force | Out-Null
Get-Process QuotaNest,msedgewebview2 -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,MainWindowTitle,Responding | ConvertTo-Json | Out-File "$out/processes.json"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bitmap = New-Object System.Drawing.Bitmap $bounds.Width,$bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($bounds.Left,$bounds.Top,0,0,$bounds.Size)
$bitmap.Save((Join-Path (Resolve-Path $out) 'desktop-diagnostic.png'))
$graphics.Dispose()
$bitmap.Dispose()
