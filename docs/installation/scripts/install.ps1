# ObjectBox Windows Installation Script
# https://github.com/objectbox/objectbox-c/releases

$cLibVersion = "5.1.0"
$url = "https://github.com/objectbox/objectbox-c/releases/download/v$cLibVersion/objectbox-windows-x64.zip"
$destZip = "objectbox.zip"
$destDll = "lib/objectbox.dll"

Write-Host "Installing ObjectBox native library for Windows (v$cLibVersion)..."

if (-not (Test-Path "lib")) {
    New-Item -ItemType Directory -Force -Path "lib"
}

Invoke-WebRequest -Uri $url -OutFile $destZip
Expand-Archive -Path $destZip -DestinationPath "temp_obx" -Force
Move-Item -Path "temp_obx/lib/objectbox.dll" -Destination $destDll -Force
Remove-Item -Path $destZip -Force
Remove-Item -Path "temp_obx" -Recurse -Force

Write-Host "Success: ObjectBox native library installed in $destDll"
