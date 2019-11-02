Invoke-Expression -Command ". $PSScriptRoot\common.ps1"

Invoke-Expression -Command "$PSScriptRoot\build.ps1"

Write-Host ""
Write-Host "====== Serving site ====="
Start-JekyllContainer("jekyll serve --incremental --livereload --unpublished --drafts --future")