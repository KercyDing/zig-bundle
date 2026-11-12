$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$v1 = Join-Path $root 'examples/zig-out/bundle/setup_exe/HelloBundle_0.1.0_x86_64-setup.exe'
$v2 = Join-Path $root 'examples/zig-out/bundle/setup_exe/HelloBundle_0.2.0_x86_64-setup.exe'

$installDir = Join-Path $env:RUNNER_TEMP 'HelloBundle Test Path'
$registryKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\com.example.hellobundle'
$startMenuShortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\HelloBundle.lnk'
$desktopShortcut = Join-Path $env:USERPROFILE 'Desktop\HelloBundle.lnk'

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw "assertion failed: $Message"
    }
}

function Invoke-Installer([string] $Path, [string[]] $Arguments) {
    Assert-True (Test-Path -LiteralPath $Path) "missing installer: $Path"
    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
    Assert-True ($process.ExitCode -eq 0) "installer failed with exit code $($process.ExitCode): $Path $Arguments"
}

function Clear-Installation {
    Remove-Item -LiteralPath $startMenuShortcut -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $desktopShortcut -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $registryKey) {
        Remove-Item -LiteralPath $registryKey -Recurse -Force
    }
    if (Test-Path -LiteralPath $installDir) {
        Remove-Item -LiteralPath $installDir -Recurse -Force
    }
}

Clear-Installation

$dirArgument = '"' + $installDir + '"'

# Fresh install.
Invoke-Installer $v1 @('--silent', '--dir', $dirArgument)

$installedExe = Join-Path $installDir 'hello-bundle.exe'
$uninstaller = Join-Path $installDir 'uninstall.exe'
Assert-True (Test-Path -LiteralPath $installedExe) 'installed executable is missing'
Assert-True (Test-Path -LiteralPath $uninstaller) 'uninstaller is missing'
Assert-True (Test-Path -LiteralPath $startMenuShortcut) 'start menu shortcut is missing'
Assert-True (Test-Path -LiteralPath $desktopShortcut) 'desktop shortcut is missing'

$registry = Get-ItemProperty -LiteralPath $registryKey
Assert-True ($registry.DisplayVersion -eq '0.1.0') "unexpected DisplayVersion: $($registry.DisplayVersion)"
Assert-True (Test-Path -LiteralPath $registry.InstallLocation) "InstallLocation does not exist: $($registry.InstallLocation)"

# Run the installed application with closed stdin.
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $installedExe
$startInfo.WorkingDirectory = $installDir
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$app = [System.Diagnostics.Process]::Start($startInfo)
$app.StandardInput.Close()
if (-not $app.WaitForExit(10000)) {
    $app.Kill()
    throw 'installed application did not exit within 10 seconds'
}
Assert-True ($app.ExitCode -eq 0) "installed application exited with $($app.ExitCode)"

# Upgrade in place.
Invoke-Installer $v2 @('--silent', '--dir', $dirArgument)
$registry = Get-ItemProperty -LiteralPath $registryKey
Assert-True ($registry.DisplayVersion -eq '0.2.0') "unexpected DisplayVersion after upgrade: $($registry.DisplayVersion)"
Assert-True (Test-Path -LiteralPath $installedExe) 'installed executable disappeared after upgrade'

# Reinstall the same version.
Invoke-Installer $v2 @('--silent', '--dir', $dirArgument)

# Uninstall and verify cleanup.
Invoke-Installer $uninstaller @('--silent')
Assert-True (-not (Test-Path -LiteralPath $installDir)) 'install directory remains after uninstall'
Assert-True (-not (Test-Path -LiteralPath $registryKey)) 'uninstall registry key remains'
Assert-True (-not (Test-Path -LiteralPath $startMenuShortcut)) 'start menu shortcut remains after uninstall'
Assert-True (-not (Test-Path -LiteralPath $desktopShortcut)) 'desktop shortcut remains after uninstall'

# Install again after uninstall.
Invoke-Installer $v2 @('--silent', '--dir', $dirArgument)
$registry = Get-ItemProperty -LiteralPath $registryKey
Assert-True ($registry.DisplayVersion -eq '0.2.0') 'reinstall after uninstall failed'
Invoke-Installer (Join-Path $installDir 'uninstall.exe') @('--silent')
Assert-True (-not (Test-Path -LiteralPath $installDir)) 'install directory remains after second uninstall'

Write-Host 'Windows installer smoke test passed'
