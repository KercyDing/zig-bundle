$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$v1 = Join-Path $root 'examples/zig-out/bundle/nsis/HelloBundle_0.1.0_x86_64-setup.exe'
$v2 = Join-Path $root 'examples/zig-out/bundle/nsis/HelloBundle_0.2.0_x86_64-setup.exe'

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

function Invoke-Setup([string] $Path, [string] $Directory) {
    Assert-True (Test-Path -LiteralPath $Path) "missing installer: $Path"
    $process = Start-Process -FilePath $Path -ArgumentList "/S /D=$Directory" -Wait -PassThru -NoNewWindow
    Assert-True ($process.ExitCode -eq 0) "installer failed with exit code $($process.ExitCode): $Path"
}

function Wait-For([scriptblock] $Condition, [string] $Description, [int] $TimeoutSeconds = 30) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (& $Condition) {
            return
        }
        Start-Sleep -Milliseconds 100
    }
    throw "timed out waiting for $Description"
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

# Fresh install.
Invoke-Setup $v1 $installDir

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
Invoke-Setup $v2 $installDir
$registry = Get-ItemProperty -LiteralPath $registryKey
Assert-True ($registry.DisplayVersion -eq '0.2.0') "unexpected DisplayVersion after upgrade: $($registry.DisplayVersion)"
Assert-True (Test-Path -LiteralPath $installedExe) 'installed executable disappeared after upgrade'

# Reinstall the same version.
Invoke-Setup $v2 $installDir

# Uninstall and verify cleanup.
Invoke-Installer $uninstaller @('/S')
Wait-For { -not (Test-Path -LiteralPath $installDir) } 'install directory removal'
Wait-For { -not (Test-Path -LiteralPath $registryKey) } 'uninstall registry key removal'
Wait-For { -not (Test-Path -LiteralPath $startMenuShortcut) } 'start menu shortcut removal'
Wait-For { -not (Test-Path -LiteralPath $desktopShortcut) } 'desktop shortcut removal'

# Install again after uninstall.
Invoke-Setup $v2 $installDir
$registry = Get-ItemProperty -LiteralPath $registryKey
Assert-True ($registry.DisplayVersion -eq '0.2.0') 'reinstall after uninstall failed'
Invoke-Installer (Join-Path $installDir 'uninstall.exe') @('/S')
Wait-For { -not (Test-Path -LiteralPath $installDir) } 'install directory removal after second uninstall'

Write-Host 'Windows installer smoke test passed'
