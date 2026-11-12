$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$installer = Join-Path $root 'examples/zig-out/bundle/nsis/HelloBundle_0.2.0_x86_64-setup.exe'
$installDir = Join-Path $env:ProgramFiles 'HelloBundle Test'
$registryKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\com.example.hellobundle'
$startMenuShortcut = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\HelloBundle.lnk'
$desktopShortcut = Join-Path $env:PUBLIC 'Desktop\HelloBundle.lnk'

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw "assertion failed: $Message"
    }
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
Assert-True (Test-Path -LiteralPath $installer) "missing installer: $installer"

$process = Start-Process -FilePath $installer -ArgumentList "/S /D=$installDir" -Wait -PassThru -NoNewWindow
Assert-True ($process.ExitCode -eq 0) "installer failed with exit code $($process.ExitCode)"

$installedExe = Join-Path $installDir 'hello-bundle.exe'
$uninstaller = Join-Path $installDir 'uninstall.exe'
Assert-True (Test-Path -LiteralPath $installedExe) 'installed executable is missing'
Assert-True (Test-Path -LiteralPath $uninstaller) 'uninstaller is missing'
Assert-True (Test-Path -LiteralPath $startMenuShortcut) 'start menu shortcut is missing'
Assert-True (Test-Path -LiteralPath $desktopShortcut) 'desktop shortcut is missing'

$registry = Get-ItemProperty -LiteralPath $registryKey
Assert-True ($registry.DisplayVersion -eq '0.2.0') "unexpected DisplayVersion: $($registry.DisplayVersion)"
Assert-True ($registry.InstallLocation -eq $installDir) "unexpected InstallLocation: $($registry.InstallLocation)"

$process = Start-Process -FilePath $uninstaller -ArgumentList '/S' -Wait -PassThru -NoNewWindow
Assert-True ($process.ExitCode -eq 0) "uninstaller failed with exit code $($process.ExitCode)"

$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $deadline) {
    if (-not (Test-Path -LiteralPath $installDir) -and
        -not (Test-Path -LiteralPath $registryKey) -and
        -not (Test-Path -LiteralPath $startMenuShortcut) -and
        -not (Test-Path -LiteralPath $desktopShortcut)) {
        Write-Host 'Windows all-users installer test passed'
        exit 0
    }
    Start-Sleep -Milliseconds 100
}

throw 'all-users uninstall did not clean up in time'
