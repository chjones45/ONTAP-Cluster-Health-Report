#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string[]]$ReportPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [switch]$DesignPreview,
    [switch]$IncludeDemoClusters
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($IncludeDemoClusters -and -not $DesignPreview) { throw 'Illustrative clusters are only allowed with -DesignPreview.' }
$inputPaths = @()
$reports = @(foreach ($path in $ReportPath) {
    $resolved = (Resolve-Path -LiteralPath $path -ErrorAction Stop).ProviderPath
    $inputPaths += $resolved
    $result = Get-Content -LiteralPath $resolved -Raw | ConvertFrom-Json
    if ($result.PSObject.Properties.Name -notcontains 'Target' -or $result.PSObject.Properties.Name -notcontains 'Report') {
        throw "Not an ONTAP collection report: $path"
    }
    [pscustomobject]@{ Source = Split-Path -Leaf $resolved; Collection = $result }
})
if ($reports.Count -eq 0) { throw 'At least one saved report is required.' }
$payload = [pscustomobject]@{
    GeneratedAt = [datetimeoffset]::Now.ToString('o')
    IsPreview = [bool]$DesignPreview
    IncludeDemoClusters = [bool]$IncludeDemoClusters
    Reports = $reports
    CheckDescriptions = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot '..\Modules\ONTAP.CheckDescriptions.psd1')
}
$json = ConvertTo-Json -InputObject $payload -Depth 15 -Compress
$data = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
$logo = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'NA_logo_violet_white_rgb.png')))
$template = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ONTAP_Health_Report.template.html') -Raw
$html = $template.Replace('__REPORT_DATA_BASE64__', $data).Replace('__LOGO_DATA_BASE64__', $logo)
$output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if ($inputPaths -contains $output) {
    throw 'HTML output must not overwrite an input JSON report.'
}
[IO.File]::WriteAllText($output, $html, (New-Object Text.UTF8Encoding($false)))
Write-Host "HTML report: $output"