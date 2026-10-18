[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RustDeskPath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Fa-f0-9]{64}$')]
    [string]$ExpectedSha256,

    [Parameter(Mandatory = $true)]
    [long]$ExpectedBytes,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Arm64', 'X64')]
    [string]$ExpectedArchitecture,

    [Parameter(Mandatory = $true)]
    [string]$ReceiptDirectory,

    [ValidateRange(5, 60)]
    [int]$TimeoutSeconds = 20,

    [switch]$RedactId,

    [switch]$AllowElevatedHostedValidation
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
if ($ExpectedBytes -lt 1) { throw 'ExpectedBytes must be greater than zero.' }

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-PeMachine([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $reader = New-Object IO.BinaryReader($stream)
        $stream.Position = 0x3c
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 0 -or $peOffset -gt ($stream.Length - 6)) {
            throw 'Invalid PE header offset.'
        }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw 'Invalid PE signature.'
        }
        return $reader.ReadUInt16()
    }
    finally {
        $stream.Dispose()
    }
}

function Get-MatchingProcessIds([string]$ExactPath) {
    $ids = New-Object 'System.Collections.Generic.List[int]'
    foreach ($proc in @(Get-Process -ErrorAction SilentlyContinue)) {
        try {
            if ($proc.Path -and ([IO.Path]::GetFullPath($proc.Path) -eq $ExactPath)) {
                $ids.Add([int]$proc.Id)
            }
        }
        catch {
            # Process exited or path was inaccessible. It cannot be treated as a match.
        }
        finally {
            $proc.Dispose()
        }
    }
    return @($ids | Sort-Object -Unique)
}

function Get-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$fullPath = [IO.Path]::GetFullPath($RustDeskPath)
if (-not [IO.Path]::IsPathRooted($RustDeskPath)) {
    throw 'RustDeskPath must be an absolute path.'
}
if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    throw "RustDesk executable not found: $fullPath"
}

$allowedNames = @('rustdesk-1.5.0-aarch64.exe', 'rustdesk-1.5.0-x86_64.exe')
$fileName = [IO.Path]::GetFileName($fullPath)
if ($allowedNames -notcontains $fileName) {
    throw "Unexpected RustDesk executable name: $fileName"
}

$elevated = Get-IsElevated
if ($elevated) {
    $hostedValidationAllowed = $AllowElevatedHostedValidation -and ($env:GITHUB_ACTIONS -eq 'true')
    if (-not $hostedValidationAllowed) {
        throw 'Run this identity read as the ordinary signed-in user, not elevated.'
    }
}

$osArchitecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
if ($osArchitecture -ne $ExpectedArchitecture) {
    throw "OS architecture mismatch: expected $ExpectedArchitecture, observed $osArchitecture."
}

$expectedPeMachine = if ($ExpectedArchitecture -eq 'Arm64') { 0xAA64 } else { 0x8664 }
$file = Get-Item -LiteralPath $fullPath
if ([long]$file.Length -ne $ExpectedBytes) {
    throw "RustDesk byte count mismatch: expected $ExpectedBytes, observed $($file.Length)."
}
$actualSha = Get-Sha256 $fullPath
if ($actualSha -ne $ExpectedSha256.ToLowerInvariant()) {
    throw "RustDesk SHA256 mismatch: $actualSha"
}
$peMachine = Get-PeMachine $fullPath
if ($peMachine -ne $expectedPeMachine) {
    throw ('RustDesk PE architecture mismatch: expected 0x{0:X4}, observed 0x{1:X4}.' -f $expectedPeMachine, $peMachine)
}

$signature = Get-AuthenticodeSignature -LiteralPath $fullPath
$versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($fullPath)
$beforePids = @(Get-MatchingProcessIds $fullPath)

$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = $fullPath
$psi.Arguments = '--get-id'
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$process = New-Object Diagnostics.Process
$process.StartInfo = $psi

$startedUtc = [DateTime]::UtcNow
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$rootPid = $null
$exitCode = $null
$stdout = ''
$stderr = ''
$newPids = @()

try {
    if (-not $process.Start()) {
        throw 'RustDesk --get-id process did not start.'
    }
    $rootPid = [int]$process.Id
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch {}
        throw "RustDesk --get-id exceeded the $TimeoutSeconds second limit."
    }

    # Required after asynchronous reads so all redirected output is flushed.
    $process.WaitForExit()
    $exitCode = [int]$process.ExitCode
    $stdout = [string]$stdoutTask.Result
    $stderr = [string]$stderrTask.Result

    if ($exitCode -ne 0) {
        throw "RustDesk --get-id exited with code $exitCode."
    }

    $candidateIds = @(
        ($stdout -split "`r?`n") |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^[A-Za-z0-9][A-Za-z0-9_-]{4,63}$' } |
            Sort-Object -Unique
    )
    if ($candidateIds.Count -ne 1) {
        throw "RustDesk --get-id did not return exactly one valid ID token (count=$($candidateIds.Count))."
    }
    $remoteId = [string]$candidateIds[0]
}
finally {
    $stopwatch.Stop()
    Start-Sleep -Milliseconds 300
    $afterPids = @(Get-MatchingProcessIds $fullPath)
    $newPids = @($afterPids | Where-Object { $beforePids -notcontains $_ })

    # Remove only new same-binary processes created by this bounded query.
    foreach ($pidToStop in $newPids) {
        try {
            Stop-Process -Id $pidToStop -Force -ErrorAction Stop
        }
        catch {
            throw "Unable to remove query-created RustDesk process $pidToStop."
        }
    }
    $remainingPids = @(Get-MatchingProcessIds $fullPath)
    $unexpected = @($remainingPids | Where-Object { $beforePids -notcontains $_ })
    if ($unexpected.Count -gt 0) {
        throw "Query-created RustDesk process residue remains: $($unexpected -join ',')."
    }
    $process.Dispose()
}

$idBytes = [Text.Encoding]::UTF8.GetBytes($remoteId)
$idHash = [BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($idBytes)).Replace('-', '').ToLowerInvariant()

New-Item -ItemType Directory -Force -Path $ReceiptDirectory | Out-Null
$receipt = [ordered]@{
    schema = 'ops.rustdesk.identity-read/1'
    marker = 'OPS_RUSTDESK_IDENTITY_READ_V1'
    status = 'IDENTITY_READ'
    observed_utc = [DateTime]::UtcNow.ToString('o')
    started_utc = $startedUtc.ToString('o')
    duration_ms = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
    host = $env:COMPUTERNAME
    user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    elevated = [bool]$elevated
    os_architecture = $osArchitecture
    executable = $fullPath
    file_name = $fileName
    bytes = [long]$file.Length
    sha256 = $actualSha
    pe_machine = ('0x{0:X4}' -f $peMachine)
    authenticode_status = [string]$signature.Status
    signer_subject = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { $null }
    product_name = [string]$versionInfo.ProductName
    product_version = [string]$versionInfo.ProductVersion
    file_version = [string]$versionInfo.FileVersion
    command = '--get-id'
    exit_code = $exitCode
    stdout_bytes = [Text.Encoding]::UTF8.GetByteCount($stdout)
    stderr_bytes = [Text.Encoding]::UTF8.GetByteCount($stderr)
    preexisting_same_binary_pids = @($beforePids)
    query_root_pid = $rootPid
    query_created_same_binary_pids = @($newPids)
    query_process_residue = $false
    remote_id_redacted = [bool]$RedactId
    remote_id = if ($RedactId) { $null } else { $remoteId }
    remote_id_length = $remoteId.Length
    remote_id_sha256 = $idHash
    password_read = $false
    password_changed = $false
    settings_changed = $false
    service_changed = $false
    firewall_changed = $false
    network_listener_created = $false
}

$receiptPath = Join-Path ([IO.Path]::GetFullPath($ReceiptDirectory)) (
    'rustdesk-identity-' + $env:COMPUTERNAME + '-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '.json'
)
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
$receipt | ConvertTo-Json -Depth 8
Write-Host "Receipt: $receiptPath"
