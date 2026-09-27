param([string]$Node)
$ErrorActionPreference = 'Stop'
$standardInput = -10
$standardOutput = -11
$standardError = -12
$ctrlCEvent = 0
$allConsoleProcesses = 0

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ConsoleControl {
    [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int handle);
    [DllImport("kernel32.dll")] public static extern bool SetStdHandle(int handle, IntPtr value);
    [DllImport("kernel32.dll")] public static extern bool FreeConsole();
    [DllImport("kernel32.dll")] public static extern bool AllocConsole();
    [DllImport("kernel32.dll")] public static extern bool GenerateConsoleCtrlEvent(uint ctrlEvent, uint processGroupId);
    [DllImport("kernel32.dll")] public static extern bool SetConsoleCtrlHandler(IntPtr handler, bool add);
}
'@

$handles = $standardInput, $standardOutput, $standardError | ForEach-Object { @{ id = $_; value = [ConsoleControl]::GetStdHandle($_) } }
[ConsoleControl]::FreeConsole() | Out-Null
[ConsoleControl]::AllocConsole() | Out-Null
$handles | ForEach-Object { [ConsoleControl]::SetStdHandle($_.id, $_.value) | Out-Null }
[ConsoleControl]::SetConsoleCtrlHandler([IntPtr]::Zero, $false) | Out-Null
$process = Start-Process $Node -ArgumentList ($args | ForEach-Object { '"' + $_ + '"' }) -NoNewWindow -PassThru
$null = $process.Handle
$null = [Console]::In.ReadLine()
[ConsoleControl]::SetConsoleCtrlHandler([IntPtr]::Zero, $true) | Out-Null
[ConsoleControl]::GenerateConsoleCtrlEvent($ctrlCEvent, $allConsoleProcesses) | Out-Null
$process.WaitForExit()
exit $process.ExitCode
