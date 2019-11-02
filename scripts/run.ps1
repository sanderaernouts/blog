param (
    [Parameter(Mandatory=$true)]
    [string]
    $Command
)
Invoke-Expression -Command ". $PSScriptRoot\common.ps1"

Start-JekyllContainer $Command