[CmdletBinding()]
param(
    [string]$ApiBaseUrl = 'https://yatra-canvas.onrender.com',
    [switch]$SkipValidation
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$apiUri = $null
if (-not [Uri]::TryCreate($ApiBaseUrl, [UriKind]::Absolute, [ref]$apiUri) -or
    $apiUri.Scheme -notin @('http', 'https') -or $apiUri.Host -eq '' -or
    $apiUri.UserInfo -ne '' -or $apiUri.Query -ne '' -or $apiUri.Fragment -ne '' -or
    $apiUri.AbsolutePath -ne '/') {
    throw 'ApiBaseUrl must be an HTTP(S) origin with no credentials, path, query or fragment.'
}
if ($apiUri.Scheme -ne 'https') {
    throw 'This release script requires HTTPS. Use flutter run --debug with API_BASE_URL for local HTTP development.'
}
$ApiBaseUrl = $apiUri.GetLeftPart([UriPartial]::Authority)
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCommand) { throw 'Flutter was not found on PATH. Install/configure the Flutter SDK first.' }

function Invoke-FlutterStep([string[]]$FlutterArguments) {
    & $flutterCommand.Source @FlutterArguments
    if ($LASTEXITCODE -ne 0) { throw "Flutter step failed (exit $LASTEXITCODE): $($FlutterArguments -join ' ')" }
}

Push-Location -LiteralPath $projectRoot
try {
    if (-not (Test-Path -LiteralPath 'pubspec.yaml')) { throw 'Flutter project root is missing pubspec.yaml.' }
    Invoke-FlutterStep @('pub', 'get')
    if (-not $SkipValidation) {
        Invoke-FlutterStep @('analyze')
        Invoke-FlutterStep @('test')
    }
    $apkPath = Join-Path $projectRoot 'build/app/outputs/flutter-apk/app-regular-release.apk'
    if (Test-Path -LiteralPath $apkPath) {
        $archiveName = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $archiveRoot = Join-Path $projectRoot "build/releases/archive/$archiveName"
        New-Item -ItemType Directory -Path $archiveRoot | Out-Null
        foreach ($previousPath in @($apkPath, "$apkPath.sha1", "$apkPath.build.json")) {
            if (Test-Path -LiteralPath $previousPath) { Copy-Item -LiteralPath $previousPath -Destination $archiveRoot }
        }
        Write-Host "Previous APK preserved in: $archiveRoot"
        $previousHash = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash
    } else { $previousHash = $null }
    $buildStarted = Get-Date
    Invoke-FlutterStep @('build', 'apk', '--flavor', 'regular', '--release', "--dart-define=API_BASE_URL=$ApiBaseUrl")
    if (-not (Test-Path -LiteralPath $apkPath)) { throw 'Flutter exited without the expected regular release APK.' }
    $apkFile = Get-Item -LiteralPath $apkPath
    $apkHash = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash
    if ($apkFile.LastWriteTime -lt $buildStarted -and $apkHash -eq $previousHash) {
        throw 'The output is an unchanged older APK. Check the Flutter build output.'
    }
    [ordered]@{
        builtAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        apiBaseUrl = $ApiBaseUrl
        flavor = 'regular'
        applicationId = 'com.yatracanvas.yatra_canvas'
        bytes = $apkFile.Length
        sha256 = $apkHash
        signing = 'development debug key (internal testing only)'
    } | ConvertTo-Json | Set-Content -LiteralPath "$apkPath.build.json" -Encoding utf8
    Write-Host "APK: $apkPath"
    Write-Host ('Size: {0:N2} MiB ({1} bytes)' -f ($apkFile.Length / 1MB), $apkFile.Length)
    Write-Host "Backend: $ApiBaseUrl"
    Write-Host 'Signing: development debug key, for internal testing only.'
    Write-Host 'Install with tools/install_android_release.ps1, or copy the APK to your phone and open it in Files.'
    Write-Host 'Allow installation from that source when Android asks. Wi-Fi/mobile data reaches Render directly.'
} finally { Pop-Location }
