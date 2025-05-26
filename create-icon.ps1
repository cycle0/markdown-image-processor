# Create proper ICO file from JPG
Add-Type -AssemblyName System.Drawing

# Load the JPG image
$jpgPath = "icon.jpg"
$icoPath = "app.ico"

if (Test-Path $jpgPath) {
    Write-Host "Loading image: $jpgPath"
    $img = [System.Drawing.Image]::FromFile((Resolve-Path $jpgPath))
    
    # Create a 32x32 bitmap
    $bitmap = New-Object System.Drawing.Bitmap(32, 32)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.DrawImage($img, 0, 0, 32, 32)
    
    # Convert to icon
    $icon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
    
    # Save as ICO file
    $fileStream = [System.IO.FileStream]::new($icoPath, [System.IO.FileMode]::Create)
    $icon.Save($fileStream)
    $fileStream.Close()
    
    # Cleanup
    $graphics.Dispose()
    $bitmap.Dispose()
    $img.Dispose()
    $icon.Dispose()
    
    Write-Host "Created icon: $icoPath"
} else {
    Write-Host "JPG file not found: $jpgPath"
} 