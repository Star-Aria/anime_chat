$ErrorActionPreference = 'Stop'

Write-Host 'Running safe checks that do not start Dart Analysis Server...'
Write-Host ''

Write-Host '1. Checking git diff whitespace'
git diff --check

Write-Host ''
Write-Host '2. Checking unresolved merge markers'
$markers = Get-ChildItem -Path 'lib' -Recurse -File |
  Select-String -Pattern '<<<<<<<|>>>>>>>'

if ($markers) {
  $markers | ForEach-Object {
    Write-Host "$($_.Path):$($_.LineNumber):$($_.Line)"
  }
  throw 'Unresolved merge markers found.'
}

Write-Host ''
Write-Host 'Safe checks passed.'
