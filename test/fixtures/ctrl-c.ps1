param([string]$Node, [string]$Script)
$ErrorActionPreference = 'Stop'
$readyPrefix = 'ready '
$pollMilliseconds = 50
$maxPolls = 200
$exitTimeoutMilliseconds = 10000
$ctrlCEvent = 0
$allConsoleProcesses = 0

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ConsoleControl {
    [DllImport("kernel32.dll")] public static extern bool FreeConsole();
    [DllImport("kernel32.dll")] public static extern bool AllocConsole();
    [DllImport("kernel32.dll")] public static extern bool GenerateConsoleCtrlEvent(uint ctrlEvent, uint processGroupId);
    [DllImport("kernel32.dll")] public static extern bool SetConsoleCtrlHandler(IntPtr handler, bool add);
}
'@

[ConsoleControl]::FreeConsole() | Out-Null
[ConsoleControl]::AllocConsole() | Out-Null
[ConsoleControl]::SetConsoleCtrlHandler([IntPtr]::Zero, $false) | Out-Null
$out = [IO.Path]::GetTempFileName()
$err = [IO.Path]::GetTempFileName()
$arguments = @($Script) + $args | ForEach-Object { '"' + $_ + '"' }
$process = Start-Process $Node -ArgumentList $arguments -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
$null = $process.Handle
$polls = 0
while (@(Get-Content $out | Where-Object { $_.StartsWith($readyPrefix) }).Count -lt $args.Count -and $polls -lt $maxPolls) {
    Start-Sleep -Milliseconds $pollMilliseconds
    $polls++
}
[ConsoleControl]::SetConsoleCtrlHandler([IntPtr]::Zero, $true) | Out-Null
[ConsoleControl]::GenerateConsoleCtrlEvent($ctrlCEvent, $allConsoleProcesses) | Out-Null
if (-not $process.WaitForExit($exitTimeoutMilliseconds)) { taskkill /T /F /PID $process.Id | Out-Null }
@{ code = [BitConverter]::ToUInt32([BitConverter]::GetBytes($process.ExitCode), 0); stdout = [IO.File]::ReadAllText($out); stderr = [IO.File]::ReadAllText($err) } | ConvertTo-Json -Compress
Remove-Item $out, $err
