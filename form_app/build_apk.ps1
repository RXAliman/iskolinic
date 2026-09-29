# Get version from pubspec.yaml
$pubspec = Get-Content "pubspec.yaml" -Raw
$versionLine = $pubspec -split "`n" | Where-Object { $_ -match "^version: " }
if ($versionLine -match "version: ([^+\s]+)") {
    $version = $Matches[1]
} else {
    $version = "unknown"
}

Write-Host "Building IskoLinic Form App v$version..." -ForegroundColor Cyan

# Run flutter build
flutter build apk --release

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed!" -ForegroundColor Red
    exit $LASTEXITCODE
}

# Create dist directory if it doesn't exist
if (!(Test-Path "dist")) {
    New-Item -ItemType Directory -Path "dist" | Out-Null
}

# Define output path
$sourceApk = "build/app/outputs/flutter-apk/app-release.apk"
$destApk = "dist/IskoLinic-Form-App-$version.apk"

# Move and rename
Copy-Item $sourceApk $destApk -Force

Write-Host "Build successful! APK available at: $destApk" -ForegroundColor Green
