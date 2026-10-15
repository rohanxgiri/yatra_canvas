[CmdletBinding()]
param(
    [string]$DeviceId,
    [string]$ApkPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build/app/outputs/flutter-apk/app-regular-release.apk')
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ApkPath -PathType Leaf)) { throw 'Release APK is missing. Run tools/build_android_release.ps1 first.' }
$ApkPath = (Resolve-Path -LiteralPath $ApkPath).Path
if ((Split-Path -Leaf $ApkPath) -ne 'app-regular-release.apk') { throw 'Choose app-regular-release.apk, not an admin or debug APK.' }
$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
$adbPath = if ($adbCommand) { $adbCommand.Source } else { $null }
if (-not $adbPath) {
    foreach ($sdkRoot in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android/sdk'))) {
        if ($sdkRoot) {
            $candidate = Join-Path $sdkRoot 'platform-tools/adb.exe'
            if (Test-Path -LiteralPath $candidate) { $adbPath = $candidate; break }
        }
    }
}
if (-not $adbPath) { throw 'ADB was not found. Install Android SDK Platform Tools, or transfer the APK through Files.' }
$deviceLines = & $adbPath devices -l
if ($LASTEXITCODE -ne 0) { throw 'ADB could not list devices.' }
$devices = @($deviceLines | Where-Object { $_ -match '^\S+\s+device\b' } | ForEach-Object { ($_ -split '\s+')[0] })
if ($DeviceId) {
    if ($DeviceId -notin $devices) { throw 'Target device is unavailable or unauthorized. Unlock it and accept USB debugging.' }
} elseif ($devices.Count -eq 1) { $DeviceId = $devices[0] }
elseif ($devices.Count -eq 0) { throw 'No authorized Android device is connected. Enable USB debugging or transfer the APK normally.' }
else { throw "Multiple Android devices are connected. Supply -DeviceId with one of: $($devices -join ', ')" }
Write-Host "Installing regular release APK on $DeviceId. Existing app data will be retained."
$installOutput = & $adbPath -s $DeviceId install -r $ApkPath 2>&1
$installExit = $LASTEXITCODE
$installOutput | Write-Host
if ($installExit -ne 0 -or -not ($installOutput -match '^Success\s*$')) {
    throw 'APK installation failed. Check storage, version and signing compatibility. No uninstall or data clear was attempted.'
}
& $adbPath -s $DeviceId shell am start -W -n 'com.yatracanvas.yatra_canvas/.MainActivity'
if ($LASTEXITCODE -ne 0) { throw 'APK installed, but ADB could not start MainActivity. Open YatraCanvas on the phone.' }
Write-Host 'Installed. Disconnect USB and test Render access using Wi-Fi, then mobile data. Prepared Jaipur also works offline.'
