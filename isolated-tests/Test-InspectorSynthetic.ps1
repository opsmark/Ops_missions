# Synthetic-only public Windows test; no private files or credentials.
$ErrorActionPreference = 'Stop'
$targetScript = Join-Path $PSScriptRoot 'Inspector-Synthetic.ps1'
$root = Join-Path $env:RUNNER_TEMP 'reader-fixture'
$tokens = $null
$errorsFound = $null
[System.Management.Automation.Language.Parser]::ParseFile($targetScript,[ref]$tokens,[ref]$errorsFound) | Out-Null
if ($errorsFound.Count -gt 0) {
  throw ('Windows PowerShell 5.1 syntax: '+(($errorsFound | ForEach-Object {$_.Message}) -join ' | '))
}
function Assert-Yes([bool]$condition,[string]$reason) {
  if (-not $condition) { throw ('WINDOWS_SYNTHETIC_FAIL: ' + $reason) }
}
function Read-Receipt([string]$expectedName) {
  $stdout = & powershell.exe -NoProfile -NonInteractive -File $targetScript -ExpectedComputerName $expectedName
  Assert-Yes ($LASTEXITCODE -eq 0) 'inspector nonzero exit'
  return ($stdout | Out-String | ConvertFrom-Json)
}
if (Test-Path -LiteralPath $root) { throw 'Synthetic test root unexpectedly exists; refuse to overwrite' }
try {
  New-Item -Path $root -ItemType Directory -ErrorAction Stop | Out-Null
  $a = Join-Path $root 'example-a.txt'
  $b = Join-Path $root 'example-b.tmp'
  $c = Join-Path $root 'example-c'
  Set-Content -LiteralPath $a -Value 'synthetic source alpha' -Encoding UTF8 -ErrorAction Stop
  Set-Content -LiteralPath $b -Value 'synthetic source beta' -Encoding UTF8 -ErrorAction Stop
  New-Item -Path $c -ItemType Directory -ErrorAction Stop | Out-Null
  Set-Content -LiteralPath (Join-Path $c 'child.txt') -Value 'synthetic child' -Encoding UTF8 -ErrorAction Stop
  $lock = [System.IO.File]::Open($b,[System.IO.FileMode]::Open,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
  try { $locked = Read-Receipt $env:COMPUTERNAME } finally { $lock.Dispose() }
  Assert-Yes ($locked.schema -eq 'synthetic.file-reader.native-readonly/1') 'schema'
  Assert-Yes ($locked.status -eq 'TARGET_METADATA_COLLECTED') 'root positive status'
  Assert-Yes ($locked.root_exists -eq $true) 'root present'
  Assert-Yes ($locked.target_count -eq 3) 'count'
  Assert-Yes ($locked.targets[0].hash_state -eq 'OK') 'readable first file'
  Assert-Yes ($locked.targets[0].sha256 -eq (Get-FileHash -LiteralPath $a -Algorithm SHA256).Hash.ToLowerInvariant()) 'first hash'
  Assert-Yes ($locked.targets[1].hash_state -eq 'HASH_FAILED_OR_LOCKED') 'locked file fail-closed'
  Assert-Yes ($null -eq $locked.targets[1].sha256) 'locked file must not preserve hash'
  Assert-Yes ($locked.targets[2].type -eq 'directory') 'folder classification'
  Assert-Yes ($locked.targets[2].children.Count -eq 1) 'folder bounded contents'
  Assert-Yes ($locked.file_holder -eq 'UNDETERMINED') 'no holder invention'
  $unlocked = Read-Receipt $env:COMPUTERNAME
  Assert-Yes ($unlocked.targets[1].hash_state -eq 'OK') 'unlocked file readable'
  Assert-Yes ($unlocked.targets[1].sha256.Length -eq 64) 'unlocked file digest'
  Write-Output ('WIN_INSPECTOR_SYNTHETIC_LOCKED_UNRELEASED_OK: WindowsPS=' + $locked.powershell_version)
} finally {
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop }
}
$missing = Read-Receipt $env:COMPUTERNAME
Assert-Yes ($missing.status -eq 'ROOT_UNAVAILABLE') 'missing root status'
Assert-Yes ($missing.root_exists -eq $false) 'missing root truth'
Assert-Yes (@($missing.targets | Where-Object {$_.exists}).Count -eq 0) 'missing children'
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
  $negative = & powershell.exe -NoProfile -NonInteractive -File $targetScript -ExpectedComputerName 'WRONG-HOST-IDENTITY' 2>&1
  $badExit = $LASTEXITCODE
} finally { $ErrorActionPreference = $previousPreference }
Assert-Yes ($badExit -ne 0) 'wrong host accepted'
Assert-Yes ((($negative | Out-String) -match 'HOST_MISMATCH')) 'wrong host failed without proper classification'
Write-Output 'WIN_INSPECTOR_SYNTHETIC_PASS: lock, release, root missing, mismatched host, SHA, directory, Windows PowerShell 5.1 parsing'