#Requires -Version 5.1

<#
.SYNOPSIS
Runs ONTAP health checks against one or more clusters and saves per-cluster reports.
.EXAMPLE
.\ONTAPHealthCheck.ps1 cluster1 cluster2
.EXAMPLE
.\ONTAPHealthCheck.ps1 -Clusters 'cluster1,cluster2 192.0.2.10'
.EXAMPLE
.\ONTAPHealthCheck.ps1 -ClusterFile .\clusters.txt
.EXAMPLE
.\ONTAPHealthCheck.ps1 cluster1 cluster2 -KeepAllOutputFiles
.EXAMPLE
.\ONTAPHealthCheck.ps1 cluster1 -OpenReport
.PARAMETER KeepAllOutputFiles
Retains per-cluster JSON after successful HTML generation. Defaults to false.
JSON is always retained if HTML generation fails. No summary CSV is created.
.PARAMETER OpenReport
Opens the generated HTML report using the system's default application.
.NOTES
Version: 0.2
Updated: 2026-10-30
Adds SIMBOX platform notices, platform-aware General check skips, and clearer
report evidence boundaries. Version 0.1 was the initial release.
See README.md, Release History, for release details.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [Alias('Target')][string[]]$Clusters,
    [string]$ClusterFile,
    [System.Management.Automation.PSCredential]$Credential,
    [string]$OutputDirectory,
    [ValidateRange(1, 65535)][int]$Port = 22,
    [string]$KnownHostsPath,
    [switch]$AcceptNewHostKey,
    [switch]$NonInteractive,
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 60,
    [string]$SshExecutable = 'ssh',
    [switch]$PassThru,
    [switch]$KeepAllOutputFiles,
    [switch]$OpenReport,
    [Parameter(ValueFromRemainingArguments = $true, DontShow = $true)]
    [string[]]$AdditionalClusters
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$requiredRuntimeFiles = @(
    'ReportAssets\New-OntapHealthReport.ps1',
    'Modules\ONTAP.HealthCheck.psm1',
    'Modules\ONTAP.CheckDescriptions.psd1',
    'ReportAssets\ONTAP_Health_Report.template.html',
    'ReportAssets\NA_logo_violet_white_rgb.png'
) | ForEach-Object { Join-Path $PSScriptRoot $_ }
$missingRuntimeFiles = @($requiredRuntimeFiles | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($missingRuntimeFiles.Count -gt 0) {
    throw "Required runtime file(s) are missing: $($missingRuntimeFiles -join ', '). Copy the complete runtime layout described in README.md before running the collection."
}
$inputs = @($Clusters) + @($AdditionalClusters)
if (-not [string]::IsNullOrWhiteSpace($ClusterFile)) {
    $inputs += @(Get-Content -LiteralPath $ClusterFile -ErrorAction Stop)
}
if (($inputs -join '').Trim().Length -eq 0) {
    if ($NonInteractive) { throw 'Specify -Clusters or a nonempty -ClusterFile when using -NonInteractive.' }
    $inputs = @(Read-Host 'Cluster names or IP addresses (commas or spaces)')
}
$targets = New-Object 'System.Collections.Generic.List[string]'
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $inputs) {
    foreach ($target in ([regex]::Split([string]$entry, '[,\s]+'))) {
        if ([string]::IsNullOrWhiteSpace($target)) { continue }
        if ($target -notmatch '^[a-zA-Z0-9:][a-zA-Z0-9.:%_-]*$') {
            throw "Invalid cluster target '$target'. Use bare hostnames, FQDNs or IP addresses, not URLs or user@host values."
        }
        if ($target.Contains(':')) {
            $ipAddress = $null
            if (-not [Net.IPAddress]::TryParse($target, [ref]$ipAddress)) {
                throw "Invalid cluster target '$target'. Use bare IPv6 addresses; specify the SSH port using -Port."
            }
        }
        if ($seen.Add($target)) { $targets.Add($target) }
    }
}
if ($targets.Count -eq 0) { throw 'No cluster targets were supplied.' }
$perClusterCredentials = $false
if ($null -eq $Credential) {
    if ($NonInteractive) { throw 'Specify -Credential when using -NonInteractive.' }
    if ($targets.Count -gt 1) {
        do {
            $answer = ([string](Read-Host 'Use the same username and password for all clusters? [Y/n]')).Trim()
            if ($answer -notmatch '^(?i:y|yes|n|no)?$') { Write-Host 'Enter Y or N.' }
        } while ($answer -notmatch '^(?i:y|yes|n|no)?$')
        $perClusterCredentials = $answer -match '^(?i:n|no)$'
    }
    if (-not $perClusterCredentials) {
        $credentialMessage = if ($targets.Count -gt 1) { 'ONTAP SSH credentials (used for all listed clusters)' } else { "ONTAP SSH credentials for $($targets[0])" }
        $Credential = Get-Credential -Message $credentialMessage
        if ($null -eq $Credential) { throw 'Credential entry was cancelled.' }
    }
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $runName = [datetime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $OutputDirectory = Join-Path $PSScriptRoot (Join-Path 'Reports' $runName)
}
$OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) { throw "Output directory already exists: $OutputDirectory. Specify a new directory to avoid overwriting reports." }
$null = New-Item -ItemType Directory -Path $OutputDirectory -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Modules\ONTAP.HealthCheck.psm1') -Force -ErrorAction Stop
$connection = @{
    Credential = $Credential
    Port = $Port
    NonInteractive = $true
    TimeoutSeconds = $TimeoutSeconds
    SshExecutable = $SshExecutable
    AcceptNewHostKey = $AcceptNewHostKey
}
if (-not [string]::IsNullOrWhiteSpace($KnownHostsPath)) { $connection.KnownHostsPath = $KnownHostsPath }
$results = @()
$summary = @()
for ($index = 0; $index -lt $targets.Count; $index++) {
    $target = $targets[$index]
    if ($perClusterCredentials) {
        $connection.Credential = Get-Credential -Message "ONTAP SSH credentials for $target"
        if ($null -eq $connection.Credential) { throw "Credential entry was cancelled for $target." }
    }
    Write-Host ('[{0}/{1}] Collecting {2}' -f ($index + 1), $targets.Count, $target)
    $report = $null
    $failure = $null
    $startedAt = [datetimeoffset]::Now.ToString('o')
    try { $report = ONTAP.HealthCheck\Invoke-OntapHealthCheck @connection -Target $target }
    catch { $failure = $_.Exception.Message }
    finally { if ($perClusterCredentials) { $connection.Credential = $null } }
    $checks = @()
    if ($null -ne $report) { $checks = @($report.Checks) }
    $errors = @($checks | Where-Object Status -eq 'Error').Count
    $skipped = @($checks | Where-Object Status -eq 'Skipped').Count
    $sessionError = if ($null -ne $report) { $report.SessionError } else { $null }
    $status = if ($null -ne $failure) { 'Failed' } elseif ($errors -gt 0 -or $skipped -gt 0 -or $null -ne $sessionError) { 'Partial' } else { 'Complete' }
    $fileName = '{0:D3}-{1}.json' -f ($index + 1), ($target -replace '[^a-zA-Z0-9._-]', '_')
    $reportPath = Join-Path $OutputDirectory $fileName
    $result = [pscustomobject]@{
        Target = $target
        CollectionStatus = $status
        StartedAt = $startedAt
        FinishedAt = [datetimeoffset]::Now.ToString('o')
        Error = $failure
        SessionError = $sessionError
        Report = $report
    }
    ConvertTo-Json -InputObject $result -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8 -ErrorAction Stop
    $results += $result
    $summary += [pscustomobject]@{
        Target = $target
        CollectionStatus = $status
        TotalHealthChecks = @($checks | Where-Object Status -eq 'Collected').Count
        Passed = @($checks | Where-Object { $_.Status -eq 'Collected' -and $_.Health -in @('NoFindings', 'Successful') }).Count
        Errors = $errors
        Skipped = $skipped
        ReviewRequired = @($checks | Where-Object Health -eq 'ReviewRequired').Count
        ReportPath = $reportPath
    }
    if ($null -ne $failure) { Write-Warning "Collection failed for ${target}: $failure" }
}
Write-Host ($summary | Format-Table Target, CollectionStatus, TotalHealthChecks, Passed, ReviewRequired, Errors, Skipped -AutoSize | Out-String)
Write-Host "Reports: $OutputDirectory"
Write-Host 'Complete describes collection, not overall cluster health. Review the saved responses.'
$htmlGenerated = $false
try {
    Write-Host 'Generating consolidated HTML report...'
    $htmlPath = Join-Path $OutputDirectory 'ONTAP-Health-Report.html'
    & (Join-Path $PSScriptRoot 'ReportAssets\New-OntapHealthReport.ps1') -ReportPath @($summary.ReportPath) -OutputPath $htmlPath
    if (-not (Test-Path -LiteralPath $htmlPath -PathType Leaf) -or (Get-Item -LiteralPath $htmlPath).Length -eq 0) {
        throw 'The HTML generator did not create a nonempty report.'
    }
    $htmlGenerated = $true
}
catch {
    Write-Warning "HTML report generation failed: $($_.Exception.Message) JSON results have been retained in $OutputDirectory."
}
if ($htmlGenerated -and -not $KeepAllOutputFiles) {
    foreach ($jsonPath in $summary.ReportPath) {
        try { Remove-Item -LiteralPath $jsonPath -ErrorAction Stop }
        catch { Write-Warning "HTML report was created, but JSON cleanup failed for '${jsonPath}': $($_.Exception.Message)" }
    }
}
if ($htmlGenerated -and $OpenReport) {
    try { Start-Process -FilePath $htmlPath -ErrorAction Stop | Out-Null }
    catch { Write-Warning "HTML report was generated but could not be opened automatically: $($_.Exception.Message) Open it manually at $htmlPath." }
}
if ($PassThru) { $results }