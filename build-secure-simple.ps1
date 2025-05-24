Write-Host "=== Markdown Image Processor v0.1.0 - Security Build ===" -ForegroundColor Cyan
Write-Host "This version is optimized to reduce antivirus false positives" -ForegroundColor Yellow
Write-Host ""

# Check .NET SDK
Write-Host "Checking .NET SDK..." -ForegroundColor Yellow
$version = dotnet --version 2>$null
if (-not $version) {
    Write-Host "Error: .NET SDK not found" -ForegroundColor Red
    exit 1
}
Write-Host "Found .NET SDK version: $version" -ForegroundColor Green

# Check and create icon
Write-Host "Checking application icon..." -ForegroundColor Yellow
if (-not (Test-Path "app.ico")) {
    Write-Host "Creating icon from JPG..." -ForegroundColor Yellow
    powershell -ExecutionPolicy Bypass -File "create-icon.ps1"
}
if (Test-Path "app.ico") {
    Write-Host "Found application icon file" -ForegroundColor Green
} else {
    Write-Host "Warning: No icon file found" -ForegroundColor Yellow
}

# Check manifest
Write-Host "Checking application manifest..." -ForegroundColor Yellow
if (Test-Path "app.manifest") {
    Write-Host "Found application manifest file" -ForegroundColor Green
} else {
    Write-Host "Warning: No manifest file found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Starting security build..." -ForegroundColor Green

# Clean
Write-Host "Cleaning project..." -ForegroundColor Yellow
dotnet clean --configuration Release | Out-Null

# Restore packages
Write-Host "Restoring NuGet packages..." -ForegroundColor Yellow
dotnet restore | Out-Null

# Build with security optimizations
Write-Host "Building project (security optimized)..." -ForegroundColor Yellow
dotnet build --configuration Release --verbosity quiet
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed" -ForegroundColor Red
    exit 1
}
Write-Host "Build successful" -ForegroundColor Green

# Create release directory
$releaseDir = "secure-release"
if (Test-Path $releaseDir) { 
    try {
        Remove-Item $releaseDir -Recurse -Force -ErrorAction Stop
    } catch {
        Write-Host "Warning: Could not clean release directory" -ForegroundColor Yellow
    }
}
New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null

# Publish with security settings
Write-Host "Publishing application (security settings)..." -ForegroundColor Yellow
Write-Host "  Target platform: Windows x64" -ForegroundColor Gray
Write-Host "  Include icon: Yes" -ForegroundColor Gray
Write-Host "  Include manifest: Yes" -ForegroundColor Gray
Write-Host "  Version: v0.1.0" -ForegroundColor Gray
Write-Host "  Optimization: Reduce false positives" -ForegroundColor Gray

# Use specific publish settings to reduce false positives
dotnet publish --configuration Release --output ".\$releaseDir" --verbosity quiet -p:PublishReadyToRun=false -p:PublishTrimmed=false -p:DebugType=none -p:DebugSymbols=false

if ($LASTEXITCODE -ne 0) {
    Write-Host "Publish failed" -ForegroundColor Red
    exit 1
}

# Remove PDB files if any
Get-ChildItem ".\$releaseDir" -Filter "*.pdb" | Remove-Item -Force -ErrorAction SilentlyContinue

# Check result
$exePath = ".\$releaseDir\MarkdownImageProcessor.exe"
if (Test-Path $exePath) {
    $fileSize = [math]::Round((Get-Item $exePath).Length / 1KB, 2)
    $fileCount = (Get-ChildItem ".\$releaseDir" -File).Count
    
    Write-Host ""
    Write-Host "Build successful!" -ForegroundColor Green
    Write-Host "Output directory: .\$releaseDir\" -ForegroundColor Cyan
    Write-Host "EXE size: $fileSize KB" -ForegroundColor Gray
    Write-Host "File count: $fileCount" -ForegroundColor Gray
    
    # Check version info
    $versionInfo = (Get-Item $exePath).VersionInfo
    Write-Host ""
    Write-Host "Version Information:" -ForegroundColor Yellow
    Write-Host "  Product Name: $($versionInfo.ProductName)" -ForegroundColor Gray
    Write-Host "  File Version: $($versionInfo.FileVersion)" -ForegroundColor Gray
    Write-Host "  Product Version: $($versionInfo.ProductVersion)" -ForegroundColor Gray
    Write-Host "  Company Name: $($versionInfo.CompanyName)" -ForegroundColor Gray
    Write-Host "  Copyright: $($versionInfo.LegalCopyright)" -ForegroundColor Gray
    
    # Check icon
    try {
        Add-Type -AssemblyName System.Drawing
        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($exePath)
        if ($icon) {
            $iconSize = "$($icon.Width)x$($icon.Height)"
            Write-Host "  Application Icon: YES ($iconSize)" -ForegroundColor Gray
            $icon.Dispose()
        }
    } catch {
        Write-Host "  Application Icon: NO" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "Security Recommendations:" -ForegroundColor Yellow
    Write-Host "  1. On first run, choose 'Run anyway' or 'More info' -> 'Run anyway'" -ForegroundColor Gray
    Write-Host "  2. Add program to antivirus whitelist" -ForegroundColor Gray
    Write-Host "  3. Distribute from trusted sources" -ForegroundColor Gray
    Write-Host "  4. Consider code signing certificate (for commercial use)" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "Usage Instructions:" -ForegroundColor Yellow
    Write-Host "  1. Copy $releaseDir folder to target computer" -ForegroundColor Gray
    Write-Host "  2. Ensure .NET 6.0 runtime is installed on target" -ForegroundColor Gray
    Write-Host "  3. Double-click MarkdownImageProcessor.exe to run" -ForegroundColor Gray
    
    Write-Host ""
    $runNow = Read-Host "Run the program now for testing? (y/n)"
    if ($runNow -eq "y" -or $runNow -eq "Y" -or $runNow -eq "") {
        Write-Host "Starting program..." -ForegroundColor Green
        Start-Process -FilePath $exePath
    }
} else {
    Write-Host "Build failed: Output file not found" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Complete!" -ForegroundColor Green 