Invoke-Expression -Command ". $PSScriptRoot\common.ps1"

New-Item -Type Directory -Path vendor/bundle -ErrorAction SilentlyContinue | Out-Null

Write-Host "====== Updating bundles ====="
Start-JekyllContainer("bundle update")

Write-Host ""
Write-Host "====== Building Jekyll site ======"
Start-JekyllContainer("jekyll build --trace")
