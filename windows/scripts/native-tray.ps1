param([string]$Mode='Prepare',[double]$X=0,[double]$Y=0,[double]$W=0,[double]$H=0,[string]$Name='windows-tray')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;using System.Runtime.InteropServices;using System.Diagnostics;using System.Security.Principal;
public static class TrayPointer {
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr token,int kind,IntPtr data,int size,out int needed);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
 public static string Integrity(int pid) {
  using(var p=Process.GetProcessById(pid)) { IntPtr token=IntPtr.Zero,data=IntPtr.Zero;
   try { if(!OpenProcessToken(p.Handle,8,out token))return "token-error";
    int size;GetTokenInformation(token,25,IntPtr.Zero,0,out size);data=Marshal.AllocHGlobal(size);
    if(!GetTokenInformation(token,25,data,size,out size))return "integrity-error";
    return new SecurityIdentifier(Marshal.ReadIntPtr(data)).Value;
   } finally {if(data!=IntPtr.Zero)Marshal.FreeHGlobal(data);if(token!=IntPtr.Zero)CloseHandle(token);}
  }
 }
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags,uint dx,uint dy,uint data,UIntPtr extra);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr window,System.Text.StringBuilder text,int count);
}
'@
$out=Join-Path $PSScriptRoot '../e2e-results'
if($Mode -eq 'Prepare') {
 $root=[System.Windows.Automation.AutomationElement]::RootElement
 $condition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button)
 $buttons=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condition)
 $icon=@($buttons | Where-Object {$_.Current.Name -like 'QuotaNest*'}) | Select-Object -First 1
 if(-not $icon) {
  $overflow=@($buttons | Where-Object {$_.Current.AutomationId -eq 'SystemTray.OverflowButton' -or $_.Current.Name -match 'Show hidden icons|Hidden icon menu|显示隐藏'}) | Select-Object -First 1
  if(-not $overflow) { $buttons | ForEach-Object {$_.Current.Name+' '+$_.Current.AutomationId} | Out-File "$out/taskbar-elements.log";throw 'Tray overflow button not found' }
  $rect=$overflow.Current.BoundingRectangle
  [TrayPointer]::SetCursorPos([int]($rect.X+$rect.Width/2),[int]($rect.Y+$rect.Height/2)) | Out-Null
  [TrayPointer]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[TrayPointer]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
  Start-Sleep -Milliseconds 400
  $buttons=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condition)
  $icon=@($buttons | Where-Object {$_.Current.Name -like 'QuotaNest*'}) | Select-Object -First 1
 }
 if(-not $icon){throw 'QuotaNest native tray icon not found'}
 $rect=$icon.Current.BoundingRectangle
 @{x=$rect.X;y=$rect.Y;w=$rect.Width;h=$rect.Height;name=$icon.Current.Name} | ConvertTo-Json | Set-Content "$out/native-tray-rect.json" -Encoding utf8
} elseif($Mode -eq 'Move' -or $Mode -eq 'Click') {
 $screen=[System.Windows.Forms.SystemInformation]::VirtualScreen
 $px=[uint32][Math]::Round(($X-$screen.Left)*65535/($screen.Width-1))
 $py=[uint32][Math]::Round(($Y-$screen.Top)*65535/($screen.Height-1))
 [TrayPointer]::mouse_event(0xC001,$px,$py,0,[UIntPtr]::Zero)
 if($Mode -eq 'Click'){[TrayPointer]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[TrayPointer]::mouse_event(4,0,0,0,[UIntPtr]::Zero)}
 Start-Sleep -Milliseconds 800
 $hit=[System.Windows.Automation.AutomationElement]::FromPoint([System.Windows.Point]::new($X,$Y))
 $hit.Current | Select-Object Name,AutomationId,ProcessId,IsOffscreen,NativeWindowHandle,BoundingRectangle | ConvertTo-Json -Depth 4 | Set-Content "$out/native-hit.json" -Encoding utf8
 Get-Process QuotaNest,explorer,node,powershell -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{Name=$_.ProcessName;Id=$_.Id;Session=$_.SessionId;Integrity=[TrayPointer]::Integrity($_.Id)} } | ConvertTo-Json | Set-Content "$out/native-tokens.json" -Encoding utf8
} elseif($Mode -eq 'Capture') {
 $screen=[System.Windows.Forms.SystemInformation]::VirtualScreen
 if($W -le 0){$X=$screen.Left;$Y=$screen.Top;$W=$screen.Width;$H=$screen.Height}
 $left=[Math]::Max($screen.Left,[int]$X);$top=[Math]::Max($screen.Top,[int]$Y)
 $width=[Math]::Min([int]$W,$screen.Right-$left);$height=[Math]::Min([int]$H,$screen.Bottom-$top)
 $bitmap=[System.Drawing.Bitmap]::new($width,$height);$graphics=[System.Drawing.Graphics]::FromImage($bitmap)
 $graphics.CopyFromScreen($left,$top,0,0,[System.Drawing.Size]::new($width,$height))
 $bitmap.Save((Join-Path (Resolve-Path $out) "$Name.png"));$graphics.Dispose();$bitmap.Dispose()
 $title=[System.Text.StringBuilder]::new(256);[TrayPointer]::GetWindowText([TrayPointer]::GetForegroundWindow(),$title,256) | Out-Null
 @{foreground=$title.ToString()} | ConvertTo-Json | Set-Content "$out/native-focus.json" -Encoding utf8
}
