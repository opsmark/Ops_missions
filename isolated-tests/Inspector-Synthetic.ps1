# Disposable public Windows fixture, derived through literal-only path/target substitutions from a private inspector.
# Not evidence of the original machine state, file custody, or production deployment.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[A-Za-z0-9-]{1,63}$')]
    [string]$ExpectedComputerName
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Join-Path $env:RUNNER_TEMP 'reader-fixture'
$names = @('example-a.txt', 'example-b.tmp', 'example-c')
$computer = [Environment]::MachineName
if (-not [string]::Equals($computer, $ExpectedComputerName, [StringComparison]::OrdinalIgnoreCase)) {
    throw "HOST_MISMATCH: expected '$ExpectedComputerName', observed '$computer'; no file inspection performed."
}

function File-Record([string]$path, [string]$name) {
    $entry = [ordered]@{ name=$name; type='unknown'; exists=$false; size_bytes=$null;
        updated_utc=$null; sha256=$null; hash_state='NOT_RUN'; children=$null;
        children_truncated=$false; error_code=$null }
    try {
        $present = Test-Path -LiteralPath $path -ErrorAction Stop
        if (-not $present) {
            $entry.type='missing'; $entry.hash_state='NOT_FOUND'
            return $entry
        }
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    } catch {
        $entry.hash_state='METADATA_UNREADABLE'; $entry.error_code=$_.Exception.GetType().Name
        return $entry
    }
    $entry.exists=$true
    $entry.updated_utc=$item.LastWriteTimeUtc.ToString('o')
    # Do not follow a reparse point to unrelated data outside the authorized evidence root.
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        $entry.type='other'; $entry.hash_state='UNSUPPORTED_TYPE'
        $entry.error_code='REPARSE_POINT_NOT_FOLLOWED'
        return $entry
    }
    if ($item.PSIsContainer) {
        $entry.type='directory'
        $entry.hash_state='DIRECTORY_NOT_HASHED'
        try {
            $items = @(Get-ChildItem -LiteralPath $path -Force -ErrorAction Stop | Select-Object -First 51)
            $entry.children_truncated=($items.Count -gt 50)
            $entry.children=@($items | Select-Object -First 50 | ForEach-Object {
                [ordered]@{ name=$_.Name; type=$(if ($_.PSIsContainer) {'directory'} else {'file'});
                    size_bytes=$(if ($_.PSIsContainer) {$null} else {[int64]$_.Length}) }
            })
        } catch {
            $entry.error_code=$_.Exception.GetType().Name
            $entry.children=@()
        }
        return $entry
    }
    if (-not ($item -is [System.IO.FileInfo])) {
        $entry.type='other'; $entry.hash_state='UNSUPPORTED_TYPE'
        return $entry
    }
    $entry.type='file'; $entry.size_bytes=[int64]$item.Length
    if ($item.Length -gt 16777216) {
        $entry.hash_state='SKIPPED_ABOVE_16MIB'; return $entry
    }
    try {
        $h = Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop
        $entry.sha256=$h.Hash.ToLowerInvariant(); $entry.hash_state='OK'
        $after = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if ($after.Length -ne $item.Length -or $after.LastWriteTimeUtc.Ticks -ne $item.LastWriteTimeUtc.Ticks) {
            $entry.sha256=$null; $entry.hash_state='CHANGED_DURING_HASH'
        }
    } catch {
        # An exception after a successful digest but before metadata readback must not
        # accidentally emit a stale 'sha256' next to a failed hash state.
        $entry.sha256=$null
        $entry.hash_state='HASH_FAILED_OR_LOCKED'
        $entry.error_code=$_.Exception.GetType().Name
    }
    return $entry
}

$scriptHash=$null
if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath -PathType Leaf)) {
    try {$scriptHash=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()} catch {}
}
$rootExists = Test-Path -LiteralPath $root -PathType Container
if ($rootExists) {
    $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction Stop
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'ROOT_REPARSE_POINT_NOT_INSPECTED'
    }
}
$targets = @()
foreach ($name in $names) {
    $targets += (File-Record -path (Join-Path $root $name) -name $name)
}
$found = @($targets | Where-Object {$_.exists}).Count
$status = if (-not $rootExists) {'ROOT_UNAVAILABLE'} elseif ($found -eq 0) {'NO_ORIGINAL_TARGETS_FOUND'} else {'TARGET_METADATA_COLLECTED'}
$receipt=[ordered]@{
    schema='synthetic.file-reader.native-readonly/1'
    generated_utc=[DateTime]::UtcNow.ToString('o')
    computer_name=$computer
    expected_computer_name=$ExpectedComputerName
    powershell_version=$PSVersionTable.PSVersion.ToString()
    script_sha256=$scriptHash
    root=$root
    root_exists=[bool]$rootExists
    status=$status
    target_count=$targets.Count
    targets=$targets
    file_holder='UNDETERMINED'
    installed_reader_source='UNDETERMINED'
    no_side_effects_claim='NO_TARGET_WRITES_OR_SERVICE_CONTROL; TRANSIENT_READS_AND_HASHES_ONLY'
    evidence_limit='Metadata and read hash attempt only. Empty or locked files do not prove destruction or file-handle owner.'
}
$receipt | ConvertTo-Json -Depth 8 -Compress