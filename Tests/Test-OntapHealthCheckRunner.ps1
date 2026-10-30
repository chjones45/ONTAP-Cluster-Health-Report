#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$runnerSource = Join-Path $PSScriptRoot '..\ONTAPHealthCheck.ps1'
$modulePath = Join-Path $PSScriptRoot '..\Modules\ONTAP.HealthCheck.psm1'
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('ontap-runner-tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testDirectory
$runner = Join-Path $testDirectory 'ONTAPHealthCheck.ps1'
Copy-Item -LiteralPath $runnerSource -Destination $runner
$null = New-Item -ItemType Directory -Path (Join-Path $testDirectory 'ReportAssets') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\ReportAssets\New-OntapHealthReport.ps1') -Destination (Join-Path $testDirectory 'ReportAssets')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\ReportAssets\ONTAP_Health_Report.template.html') -Destination (Join-Path $testDirectory 'ReportAssets')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\ReportAssets\NA_logo_violet_white_rgb.png') -Destination (Join-Path $testDirectory 'ReportAssets')
$null = New-Item -ItemType Directory -Path (Join-Path $testDirectory 'Modules')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\Modules\ONTAP.CheckDescriptions.psd1') -Destination (Join-Path $testDirectory 'Modules')
$fixtureModulePath = Join-Path $testDirectory 'Modules\ONTAP.HealthCheck.psm1'
$credential = New-Object System.Management.Automation.PSCredential('test', (ConvertTo-SecureString 'test' -AsPlainText -Force))

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$global:ontapTestOpenedReportPaths = @()
$global:ontapTestFailReportOpen = $false
function global:Start-Process {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$FilePath)
    $global:ontapTestOpenedReportPaths += $FilePath
    if ($global:ontapTestFailReportOpen) { throw 'Simulated HTML file association failure.' }
}

try {
    Import-Module $modulePath -Force
    $catalog = @(Get-OntapHealthCheckCommand)
    $supportedCatalog = @($catalog | Where-Object { $_.MinimumVersion -le [version]'9.16.1' })
    $topologyCommands = @('cluster ha show', 'network options switchless-cluster show')
    $expectedEmptyQueries = @($supportedCatalog | Where-Object { $_.Phase -eq 'Check' -and $_.Command -ne 'version -v' -and $_.Command -notin $topologyCommands }).Count
    $expectedStarts = @($supportedCatalog | Where-Object Phase -eq 'Start').Count
    $expectedResults = @($supportedCatalog | Where-Object Phase -eq 'Results').Count
    $expectedBuildChecks = @($supportedCatalog | Where-Object Command -eq 'version -v').Count
    $expectedSuccessful = $expectedResults + $expectedBuildChecks
    $expectedPassed = $expectedEmptyQueries + 2 + $expectedSuccessful
    $expectedStatus = if ($supportedCatalog.Count -eq $catalog.Count) { 'Complete' } else { 'Partial' }
    $transportDouble = @'
        $script:runnerTargets = @()
        $script:runnerUsers = @()
        $script:runnerClusterNames = @{
            cluster1 = 'Zulu Cluster'
            cluster2 = 'Alpha Cluster'
            'cluster3.example.com' = 'Mike Cluster'
            '192.0.2.10' = 'Bravo Cluster'
            '2001:db8::1' = 'Echo Cluster'
        }
        function script:Invoke-OntapSshCommand {
            param($Target, $Credential, $Port, $KnownHostsPath, $AcceptNewHostKey, $NonInteractive, $TimeoutSeconds, $SshExecutable, [string[]]$Command, [switch]$Advanced, [switch]$ContinueOnCommandError, $Session, [scriptblock]$SessionBody)
            if ($null -ne $SessionBody) {
                $sessionResult = & $SessionBody ([pscustomobject]@{ Broken = $false })
                if ($Target -eq 'session-failure.example.com') {
                    $sessionResult.SessionExitCode = 255
                    $sessionResult.SessionError = 'Simulated session shutdown failure.'
                }
                $sessionResult
                return
            }
            if ($null -eq $Credential -or -not $NonInteractive) { throw 'Credentials or unattended execution were not forwarded.' }
            if ($Command[0] -eq 'version') {
                $script:runnerTargets += $Target
                $script:runnerUsers += $Credential.UserName
                if ($Target -eq 'failed.example.com') { throw 'Simulated unreachable cluster.' }
                return [pscustomobject]@{ StdOut = 'NetApp Release 9.16.1P12' }
            }
            $status = 'Collected'
            $failure = $null
            if ($Target -eq 'partial.example.com' -and $Command[0] -eq 'storage errors show') {
                $status = 'Error'
                $failure = 'Simulated command authorization error.'
            }
            $response = 'There are no entries matching your query.'
            if ($Command[0] -eq 'cluster identity show') { $clusterName = $script:runnerClusterNames[$Target]; if (-not $clusterName) { $clusterName = 'test-cluster' }; $response = "Cluster UUID:`r`n12345678-1234-1234-1234-123456789abc`r`nCluster Name: $clusterName`r`n" }
            elseif ($Command[0] -eq 'system node show -fields node') { $response = "Node`r`n----------`r`nnode1`r`nnode2`r`n2 entries were displayed.`r`n" }
            elseif ($Command[0] -eq 'system node show -fields model') { $model = if ($Target -eq 'simulator.example.com') { 'SIMBOX' } else { 'AFF-A250' }; $response = "node model`r`n---- -----`r`nnode1 $model`r`nnode2 $model`r`n2 entries were displayed.`r`n" }
            elseif ($Target -eq 'simulator.example.com' -and $Command[0] -eq 'system controller environment show -status !ok') { $status = 'Error'; $response = 'Error: show failed: This command is not supported on this platform.'; $failure = $response }
            elseif ($Command[0] -eq 'storage aggregate show-spare-disks') { $response = "Original Owner: node1`r`nPool0 Spare Pool`r`n1.0.10 SSD solid-state 894GB 894GB zeroed`r`n" }
            elseif ($Command[0] -eq 'cluster ha show') { $response = 'High-Availability Configured: true' }
            elseif ($Command[0] -eq 'network options switchless-cluster show') { $response = 'Enable Switchless Cluster: true' }
            if ($Command[0] -eq 'version -v') { $response = 'NetApp Release 9.16.1P12: <1O>' }
            if ($Command[0] -like '*cluster-connectivity show*') {
                $response = "Node: node1`r`nPacket Loss: none`r`nNode: node2`r`nPacket Loss: none`r`n"
            }
            [pscustomobject]@{ StdOut = $response; StdErr = ''; ExitCode = 0; Status = $status; Error = $failure }
        }
'@
    $moduleSource = Get-Content -LiteralPath $modulePath -Raw
    $staleDouble = $transportDouble.Replace('NetApp Release 9.16.1P12', 'NetApp Release 8.3')
    @($moduleSource, $staleDouble) | Set-Content -LiteralPath $fixtureModulePath -Encoding UTF8
    Import-Module $fixtureModulePath -Force
    @($moduleSource, $transportDouble) | Set-Content -LiteralPath $fixtureModulePath -Encoding UTF8
    $inputFile = Join-Path $testDirectory 'clusters.txt'
    @('cluster3.example.com, 192.0.2.10', '', '2001:db8::1 cluster1', 'CLUSTER2') | Set-Content -LiteralPath $inputFile
    $output = Join-Path $testDirectory 'mixed'
    $reports = @(& $runner -Clusters 'cluster1,cluster2', "CLUSTER1`tcluster3.example.com" -ClusterFile $inputFile -Credential $credential -NonInteractive -OutputDirectory $output -PassThru -KeepAllOutputFiles -InformationVariable runnerMessages)
    $consoleSummary = @($runnerMessages | ForEach-Object { [string]$_.MessageData } | Where-Object { $_ -match 'CollectionStatus' }) -join "`n"
    Assert-Condition ($consoleSummary -match '\bPassed\b' -and $consoleSummary -notmatch '\bSuccessful\b') 'Console summary did not replace Successful with Passed.'
    Assert-Condition ($consoleSummary -match '\bTotalHealthChecks\b' -and $consoleSummary -notmatch '\bCollected\b') 'Console summary did not rename Collected to TotalHealthChecks.'
    Assert-Condition ($reports.Count -eq 5) 'Mixed file, comma and whitespace input or case-insensitive deduplication failed.'
    Assert-Condition ($reports[0].Report.Version -eq '9.16.1') 'Runner reused the stale in-memory module instead of reloading the current file.'
    Assert-Condition ($reports[0].StartedAt -match '[+-]\d{2}:\d{2}$' -and [datetimeoffset]::Parse($reports[0].StartedAt).Offset -eq [datetimeoffset]::Now.Offset) 'Wrapper timestamp did not preserve runner local time and offset.'
    Assert-Condition ($reports[0].PSObject.Properties.Name -notcontains 'StartedAtUtc') 'Wrapper kept misleading UTC field names.'
    Write-Host 'PASS: stale in-memory module replaced by the current module file'
    $simulatorOutput = Join-Path $testDirectory 'simulator'
    $simulatorReports = @(& $runner -Clusters 'simulator.example.com' -Credential $credential -NonInteractive -OutputDirectory $simulatorOutput -PassThru -KeepAllOutputFiles)
    $simulatorHtml = Get-Content -LiteralPath (Join-Path $simulatorOutput 'ONTAP-Health-Report.html') -Raw
    $simulatorEncoded = [regex]::Match($simulatorHtml, "atob\('(?<data>[A-Za-z0-9+/=]+)'\)").Groups['data'].Value
    $simulatorPayload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($simulatorEncoded)) | ConvertFrom-Json
    $simulatorReport = $simulatorPayload.Reports[0].Collection.Report
    Assert-Condition ($simulatorReport.Inventory.IsSimulator -and $simulatorReport.Inventory.PlatformNotice -match 'not a supported production-ready platform' -and $simulatorHtml.Contains('renderPlatformNotices()')) 'Generated report lost the SIMBOX warning.'
    $simulatorCheck = $simulatorReport.Checks | Where-Object Command -eq 'system controller environment show -status !ok'
    Assert-Condition ($simulatorCheck.Status -eq 'Skipped' -and $simulatorCheck.Health -eq 'NotApplicable' -and $simulatorCheck.StdOut -match 'not supported') 'Generated report lost the platform skip or raw evidence.'
    Assert-Condition ($simulatorHtml.Contains("checks.filter(check=>!(check.Status==='Skipped'&&check.Health==='NotApplicable')).map(check=>check.outcome)") -and $simulatorHtml.Contains("outcomes.has('review')||outcomes.has('skipped')?'review'") -and $simulatorHtml.Contains('Not-applicable skips do not raise severity; other skips require review.')) 'Severity roll-ups must exclude explicitly not-applicable skips while retaining review for unexpected skips.'
    Assert-Condition ($simulatorHtml.Contains('<meta name="application-version" content="0.3">')) 'Generated report is missing application version 0.3.'
    Write-Host 'PASS: generated SIMBOX report retains platform warning, skipped status and raw evidence'
    Assert-Condition (($reports.Target -join ',') -eq 'cluster1,cluster2,cluster3.example.com,192.0.2.10,2001:db8::1') 'Input order or address parsing changed.'
    Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $output 'summary.csv'))) 'The runner still creates a summary CSV.'
    $jsonPaths = @(Get-ChildItem -LiteralPath $output -Filter '*.json' | Sort-Object Name | Select-Object -ExpandProperty FullName)
    Assert-Condition ($jsonPaths.Count -eq $reports.Count) 'KeepAllOutputFiles did not retain every cluster JSON.'
    $htmlPath = Join-Path $output 'ONTAP-Health-Report.html'
    Assert-Condition (Test-Path -LiteralPath $htmlPath) 'Consolidated HTML was not generated automatically.'
    $html = Get-Content -LiteralPath $htmlPath -Raw
    $encoded = [regex]::Match($html, "atob\('(?<data>[A-Za-z0-9+/=]+)'\)").Groups['data'].Value
    $embedded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded)) | ConvertFrom-Json
    Assert-Condition ($embedded.Reports.Count -eq 5 -and -not $embedded.IsPreview -and -not $embedded.IncludeDemoClusters) 'Automatic HTML did not contain exactly the real collected clusters.'
    Assert-Condition ($embedded.CheckDescriptions.'network interface show -is-home false'.PassMessage -match 'home port') 'HTML is missing shared assessment guidance.'
    Assert-Condition (($embedded.Reports.Collection.Target -join ',') -eq ($reports.Target -join ',')) 'HTML was generated before all cluster reports were saved.'
    Assert-Condition ($embedded.Reports[0].Collection.Report.Inventory.NodeCount -eq 2 -and $embedded.Reports[0].Collection.Report.Inventory.ClusterName -eq 'Zulu Cluster' -and $embedded.Reports[0].Collection.Report.Inventory.ClusterUuid -eq '12345678-1234-1234-1234-123456789abc') 'HTML did not embed cluster identity and node inventory.'
    Assert-Condition (($embedded.Reports.Collection.Report.Inventory.ClusterName -join ',') -eq 'Zulu Cluster,Alpha Cluster,Mike Cluster,Bravo Cluster,Echo Cluster') 'Test collections did not retain the ONTAP cluster names distinct from their input targets.'
    Assert-Condition ($html.Contains('function selectedClusters(){return allClusters().filter(c=>state.clusters===null||state.clusters.has(c.id)).sort(compareClusters)}') -and $html.Contains('allClusters().sort(compareClusters).map(cluster=>[cluster.id,cluster.target')) 'Cluster filters and result groups are not sorted by the canonical cluster-name comparator.'
    Assert-Condition ($html.Contains('function compareClusters(a,b){return a.target.localeCompare(b.target,undefined,{sensitivity:''base''})||a.connectionTarget.localeCompare(b.connectionTarget,undefined,{sensitivity:''base''})||a.id.localeCompare(b.id)}') -and $html.Contains("['Target',cluster.connectionTarget]") ) 'Canonical cluster labels replaced the original connection target in collection details.'
    Assert-Condition ($embedded.Reports[0].Collection.Report.Inventory.SpareDiskInventoryOutput -match '1\.0\.10' -and $html -match 'Spare-disk inventory .*not assessed') 'HTML did not embed spare-disk output as explicitly unassessed evidence.'
    $informationMetricIndex = $html.IndexOf('id="metric-info"')
    $errorMetricIndex = $html.IndexOf('id="metric-errors"')
    Assert-Condition ($informationMetricIndex -ge 0 -and $informationMetricIndex -lt $errorMetricIndex -and $html.Contains('data-result="info"') -and $html.Contains('<span>Informational</span>') -and $html -match 'total=\{pass:0,findings:0,review:0,info:0,error:0,collected:0\}') 'Dashboard Information metric is missing, misplaced, or excluded from total aggregation.'
    $topResultsControlsIndex = $html.IndexOf('class="results-disclosure-controls"')
    $checkRowsIndex = $html.IndexOf('<div id="checkRows">')
    $bottomResultsControlsIndex = $html.IndexOf('class="results-disclosure-controls bottom"')
    Assert-Condition ($topResultsControlsIndex -ge 0 -and $topResultsControlsIndex -lt $checkRowsIndex -and $checkRowsIndex -lt $bottomResultsControlsIndex -and ([regex]::Matches($html, 'data-action="expand"').Count -eq 2) -and ([regex]::Matches($html, 'data-action="collapse"').Count -eq 2) -and $html.Contains('$(''checkRows'').querySelectorAll(''details'')')) 'Top/bottom Expand all and Collapse all controls are missing, misplaced, or not wired to Results details.'
    Assert-Condition ($html -match 'data:image/png;base64,' -and $html -notmatch '__REPORT_DATA_BASE64__|__LOGO_DATA_BASE64__') 'HTML is missing its embedded data or logo.'
    Assert-Condition (@(Get-ChildItem -LiteralPath $output -Filter '*.html').Count -eq 1) 'More than one consolidated report was generated for a run.'
    foreach ($jsonPath in $jsonPaths) {
        $saved = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
        Assert-Condition ($saved.CollectionStatus -eq $expectedStatus -and $saved.Report.Checks.Count -eq $catalog.Count) 'Per-cluster JSON did not retain the full report.'
        Assert-Condition ($saved.Report.Release -eq 'NetApp Release 9.16.1P12') 'JSON lost the full patch-level release.'
        $expectedSummaryRow = '(?m)^' + [regex]::Escape($saved.Target) + '\s+' + $expectedStatus + '\s+' + $supportedCatalog.Count + '\s+' + $expectedPassed + '\b'
        Assert-Condition ($consoleSummary -match $expectedSummaryRow) 'Console summary did not retain supported and passed check totals.'
        Assert-Condition ($saved.Report.Checks[-1].Health -eq 'Successful' -and $saved.Report.Checks[-1].StdOut -match 'Packet Loss: none') 'JSON did not preserve successful connectivity evidence.'
        Assert-Condition ((Get-Content -LiteralPath $jsonPath -Raw) -notmatch '"Credential"|"Password"') 'Report contains credential fields.'
    }
    Write-Host 'PASS: mixed input, deduplication, IPv6, retained JSON and console totals without CSV'

    $reports = @(& $runner cluster1 cluster2 -Credential $credential -NonInteractive -OutputDirectory (Join-Path $testDirectory 'spaces') -PassThru)
    Assert-Condition ($reports.Count -eq 2) 'Unquoted space-separated cluster arguments failed.'
    $defaultFiles = @(Get-ChildItem -LiteralPath (Join-Path $testDirectory 'spaces') -File)
    Assert-Condition ($defaultFiles.Count -eq 1 -and $defaultFiles[0].Name -eq 'ONTAP-Health-Report.html') 'Default output did not retain only the HTML report.'
    $reports = @(& $runner -Clusters cluster1 cluster2 -Credential $credential -NonInteractive -OutputDirectory (Join-Path $testDirectory 'named-spaces') -PassThru -KeepAllOutputFiles:$false)
    Assert-Condition ($reports.Count -eq 2) 'Named space-separated cluster arguments failed.'
    Assert-Condition (@(Get-ChildItem -LiteralPath (Join-Path $testDirectory 'named-spaces') -Filter '*.json').Count -eq 0) 'Explicit false kept JSON output.'
    $reports = @(& $runner -Clusters cluster1,cluster2 -Credential $credential -NonInteractive -OutputDirectory (Join-Path $testDirectory 'array') -PassThru)
    Assert-Condition ($reports.Count -eq 2) 'Native PowerShell array input failed.'
    $reports = @(& $runner -ClusterFile $inputFile -Credential $credential -NonInteractive -OutputDirectory (Join-Path $testDirectory 'file-only') -PassThru)
    Assert-Condition ($reports.Count -eq 5) 'File-only input failed.'
    Write-Host 'PASS: positional and named spaces, PowerShell arrays and file-only input'

    $reports = @(& $runner 'failed.example.com partial.example.com session-failure.example.com cluster1' -Credential $credential -NonInteractive -OutputDirectory (Join-Path $testDirectory 'failures') -PassThru -KeepAllOutputFiles:$true -WarningAction SilentlyContinue)
    Assert-Condition (($reports.CollectionStatus -join ',') -eq "Failed,Partial,Partial,$expectedStatus") 'One cluster failure prevented later collection or a partial result was hidden.'
    Assert-Condition ($reports[0].Error -match 'Simulated unreachable' -and $null -eq $reports[0].Report) 'Failed cluster did not retain its error.'
    Assert-Condition ($reports[2].SessionError -match 'shutdown failure' -and $reports[2].Report.Checks.Count -eq $catalog.Count) 'Session shutdown failure lost results or was not propagated.'
    $failureJsonPaths = @(Get-ChildItem -LiteralPath (Join-Path $testDirectory 'failures') -Filter '*.json' | Sort-Object Name | Select-Object -ExpandProperty FullName)
    Assert-Condition ($failureJsonPaths.Count -eq $reports.Count) 'Explicit true failed to retain JSON for partial or failed clusters.'
    $failureHtml = Get-Content -LiteralPath (Join-Path $testDirectory 'failures\ONTAP-Health-Report.html') -Raw
    $failureEncoded = [regex]::Match($failureHtml, "atob\('(?<data>[A-Za-z0-9+/=]+)'\)").Groups['data'].Value
    $failureEmbedded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($failureEncoded)) | ConvertFrom-Json
    Assert-Condition ($failureEmbedded.Reports.Count -eq $reports.Count -and $failureEmbedded.Reports[0].Collection.CollectionStatus -eq 'Failed') 'Failed or partial clusters were omitted from the consolidated HTML.'
    Write-Host 'PASS: failed and partial clusters do not block other clusters'

    $reportGenerator = Join-Path $testDirectory 'ReportAssets\New-OntapHealthReport.ps1'
    $crossFolderReports = @($jsonPaths[0], $failureJsonPaths[-1])
    $regeneratedPath = Join-Path $testDirectory 'regenerated.html'
    & $reportGenerator -ReportPath $crossFolderReports -OutputPath $regeneratedPath
    Assert-Condition (Test-Path -LiteralPath $regeneratedPath) 'Regeneration from reports in different directories failed.'
    $generatorFailure = $null
    try { & $reportGenerator -ReportPath $crossFolderReports -OutputPath $crossFolderReports[1] } catch { $generatorFailure = $_.Exception.Message }
    Assert-Condition ($generatorFailure -match 'must not overwrite') 'Generator could overwrite an input JSON report.'
    $generatorFailure = $null
    try { & $reportGenerator -ReportPath $crossFolderReports -OutputPath $regeneratedPath -IncludeDemoClusters } catch { $generatorFailure = $_.Exception.Message }
    Assert-Condition ($generatorFailure -match 'only allowed') 'Illustrative data could be included in a production report.'
    Write-Host 'PASS: one production HTML per run, cross-folder regeneration and source-data protection'

    $generatorSource = Get-Content -LiteralPath $reportGenerator -Raw
    try {
        Set-Content -LiteralPath $reportGenerator -Value "throw 'Simulated HTML rendering failure.'" -Encoding UTF8
        $renderFailureOutput = Join-Path $testDirectory 'render-failure'
        $preserved = @(& $runner cluster1 -Credential $credential -NonInteractive -OutputDirectory $renderFailureOutput -PassThru -WarningVariable renderWarnings -WarningAction SilentlyContinue)
        Assert-Condition ($preserved.Count -eq 1 -and $preserved[0].CollectionStatus -eq $expectedStatus) 'Rendering failure discarded completed collection results.'
        Assert-Condition (@(Get-ChildItem -LiteralPath $renderFailureOutput -Filter '*.json').Count -eq 1) 'Rendering failure deleted the JSON recovery data.'
        Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $renderFailureOutput 'summary.csv'))) 'Rendering failure created a summary CSV.'
        Assert-Condition (($renderWarnings -join ' ') -match 'HTML report generation failed') 'Rendering failure was not reported to the user.'
    }
    finally { Set-Content -LiteralPath $reportGenerator -Value $generatorSource -Encoding UTF8 }
    Write-Host 'PASS: HTML rendering failures preserve data and issue a clear warning'

    foreach ($case in @(
        @{ Name = 'missing-html'; Body = 'param([string[]]$ReportPath, [string]$OutputPath)' },
        @{ Name = 'empty-html'; Body = 'param([string[]]$ReportPath, [string]$OutputPath); [IO.File]::WriteAllText($OutputPath, [string]::Empty)' },
        @{ Name = 'partial-html'; Body = 'param([string[]]$ReportPath, [string]$OutputPath); [IO.File]::WriteAllText($OutputPath, ''<html>partial</html>''); throw ''Simulated rendering failure after partial output.''' }
    )) {
        try {
            Set-Content -LiteralPath $reportGenerator -Value $case.Body -Encoding UTF8
            $recoveryOutput = Join-Path $testDirectory $case.Name
            $recovery = @(& $runner 'failed.example.com cluster1' -Credential $credential -NonInteractive -OutputDirectory $recoveryOutput -PassThru -WarningVariable recoveryWarnings -WarningAction SilentlyContinue)
            Assert-Condition ($recovery.Count -eq 2) 'HTML output failure discarded in-memory cluster results.'
            Assert-Condition (@(Get-ChildItem -LiteralPath $recoveryOutput -Filter '*.json').Count -eq 2) "JSON was removed after unusable HTML: $($case.Name)"
            Assert-Condition (($recoveryWarnings -join ' ') -match 'JSON results have been retained') 'Recovery warning did not explain retained JSON.'
        }
        finally { Set-Content -LiteralPath $reportGenerator -Value $generatorSource -Encoding UTF8 }
    }
    $cleanupOutput = Join-Path $testDirectory 'default-partial'
    $cleanupReports = @(& $runner 'failed.example.com partial.example.com cluster1' -Credential $credential -NonInteractive -OutputDirectory $cleanupOutput -PassThru -WarningAction SilentlyContinue)
    Assert-Condition ($cleanupReports.Count -eq 3 -and (Test-Path -LiteralPath (Join-Path $cleanupOutput 'ONTAP-Health-Report.html'))) 'Default cleanup lost the consolidated report for failed/partial clusters.'
    Assert-Condition (@(Get-ChildItem -LiteralPath $cleanupOutput -File).Count -eq 1) 'Default cleanup retained JSON or created CSV for failed/partial clusters.'
    Write-Host 'PASS: default HTML-only output, explicit retention and safe recovery for missing, empty or partial HTML'
    Assert-Condition ($global:ontapTestOpenedReportPaths.Count -eq 0) 'The report opened without the opt-in switch.'
    $openOutput = Join-Path $testDirectory 'open-report'
    $openReports = @(& $runner cluster1 -Credential $credential -NonInteractive -OutputDirectory $openOutput -PassThru -OpenReport)
    $expectedOpenedPath = Join-Path $openOutput 'ONTAP-Health-Report.html'
    Assert-Condition ($openReports.Count -eq 1 -and $openReports[0].CollectionStatus -eq $expectedStatus -and $global:ontapTestOpenedReportPaths[-1] -eq $expectedOpenedPath -and (Test-Path -LiteralPath $expectedOpenedPath)) 'OpenReport did not open the completed HTML after generation.'
    Assert-Condition (@(Get-ChildItem -LiteralPath $openOutput -Filter '*.json').Count -eq 0) 'Opening the report changed default JSON cleanup.'
    $global:ontapTestFailReportOpen = $true
    $openFailureOutput = Join-Path $testDirectory 'open-report-failure'
    $openWarnings = @()
    $openFailureReports = @(& $runner cluster1 -Credential $credential -NonInteractive -OutputDirectory $openFailureOutput -PassThru -OpenReport -WarningVariable openWarnings -WarningAction SilentlyContinue)
    $openFailureHtml = Join-Path $openFailureOutput 'ONTAP-Health-Report.html'
    Assert-Condition ($openFailureReports.Count -eq 1 -and $openFailureReports[0].CollectionStatus -eq $expectedStatus -and (Test-Path -LiteralPath $openFailureHtml) -and @($openWarnings | Where-Object { $_ -match 'could not be opened automatically' }).Count -eq 1) 'An HTML launch failure affected collection or hid the generated report.'
    Assert-Condition (@(Get-ChildItem -LiteralPath $openFailureOutput -Filter '*.json').Count -eq 0) 'A launch failure incorrectly changed JSON cleanup after successful rendering.'
    $global:ontapTestFailReportOpen = $false
    Write-Host 'PASS: opt-in report opening and isolated launch failures'

    $module = Get-Module ONTAP.HealthCheck | Where-Object Path -eq $fixtureModulePath
    foreach ($case in @(
        @{ Clusters = 'https://cluster1'; Expected = 'Invalid cluster target' },
        @{ Clusters = 'admin@cluster1'; Expected = 'Invalid cluster target' },
        @{ Clusters = 'cluster1:22'; Expected = 'Invalid cluster target' },
        @{ Clusters = '[2001:db8::1]'; Expected = 'Invalid cluster target' },
        @{ Clusters = ', ,'; Expected = 'No cluster targets' },
        @{ ClusterFile = (Join-Path $testDirectory 'missing.txt'); Expected = 'Cannot find path' }
    )) {
        $expected = $case.Expected
        $arguments = @{} + $case
        $null = $arguments.Remove('Expected')
        $failure = $null
        $callsBefore = @(& $module { $script:runnerTargets }).Count
        try { & $runner @arguments -Credential $credential -NonInteractive -OutputDirectory (Join-Path $testDirectory 'invalid') } catch { $failure = $_.Exception.Message }
        Assert-Condition ($failure -match $expected) "Wrong input validation failure: $failure"
        $callsAfter = @(& $module { $script:runnerTargets }).Count
        Assert-Condition ($callsAfter -eq $callsBefore) 'Invalid input contacted a cluster.'
    }
    foreach ($arguments in @(@{ NonInteractive = $true }, @{ Clusters = 'cluster1'; NonInteractive = $true })) {
        $failure = $null
        try { & $runner @arguments } catch { $failure = $_.Exception.Message }
        Assert-Condition ($failure -match 'Specify -Clusters|Specify -Credential') 'Unattended execution attempted a prompt.'
    }
    $failure = $null
    try { & $runner cluster1 -Credential $credential -NonInteractive -OutputDirectory $output } catch { $failure = $_.Exception.Message }
    Assert-Condition ($failure -match 'already exists') 'Existing reports could be overwritten.'
    Write-Host "PASS: input validation, unattended prompts and overwrite protection ($($PSVersionTable.PSEdition))"

    $promptState = @{ ChoiceAnswers = $null; ChoiceMessages = @(); CredentialMessages = @(); CancelCredential = $false }
    Set-Item Function:Read-Host -Value ({
        param([string]$Prompt)
        $promptState.ChoiceMessages += $Prompt
        if ($promptState.ChoiceAnswers.Count -eq 0) { throw 'Unexpected interactive choice prompt.' }
        return $promptState.ChoiceAnswers.Dequeue()
    }.GetNewClosure())
    Set-Item Function:Get-Credential -Value ({
        param([string]$Message)
        $promptState.CredentialMessages += $Message
        if ($promptState.CancelCredential) { return $null }
        $userName = 'prompt-user-' + $promptState.CredentialMessages.Count
        return New-Object System.Management.Automation.PSCredential($userName, (ConvertTo-SecureString 'test-only' -AsPlainText -Force))
    }.GetNewClosure())
    foreach ($mode in @('shared', 'separate', 'single', 'cancel')) {
        $promptState.ChoiceAnswers = New-Object 'System.Collections.Generic.Queue[string]'
        $promptState.ChoiceMessages = @()
        $promptState.CredentialMessages = @()
        $promptState.CancelCredential = $mode -eq 'cancel'
        $promptTargets = @(if ($mode -eq 'single') { '192.0.2.10' } else { 'cluster1'; 'cluster2.example.com' })
        if ($mode -eq 'shared') { $promptState.ChoiceAnswers.Enqueue('Y') }
        elseif ($mode -eq 'separate') {
            $promptState.ChoiceAnswers.Enqueue('invalid')
            $promptState.ChoiceAnswers.Enqueue('N')
        }
        elseif ($mode -eq 'cancel') { $promptState.ChoiceAnswers.Enqueue('N') }
        $failure = $null
        try { $promptReports = @(& $runner -Clusters $promptTargets -OutputDirectory (Join-Path $testDirectory ('prompt-' + $mode)) -PassThru) }
        catch { $failure = $_.Exception.Message }
        if ($mode -eq 'cancel') {
            Assert-Condition ($failure -match 'cancelled for cluster1') 'Cancelled per-cluster credentials did not stop safely.'
            $users = @(& (Get-Module ONTAP.HealthCheck | Where-Object Path -eq $fixtureModulePath) { $script:runnerUsers })
            Assert-Condition ($users.Count -eq 0) 'A cluster was contacted after credential cancellation.'
        }
        else {
            Assert-Condition ($null -eq $failure -and $promptReports.Count -eq $promptTargets.Count) "Interactive credential mode failed: $mode / $failure"
            $users = @(& (Get-Module ONTAP.HealthCheck | Where-Object Path -eq $fixtureModulePath) { $script:runnerUsers })
            if ($mode -eq 'shared') {
                Assert-Condition ($promptState.CredentialMessages.Count -eq 1 -and $promptState.CredentialMessages[0] -match 'all listed clusters') 'Shared credentials were not requested once with the correct message.'
                Assert-Condition (($users -join ',') -eq 'prompt-user-1,prompt-user-1') 'Shared credentials were not reused.'
            }
            elseif ($mode -eq 'separate') {
                Assert-Condition ($promptState.ChoiceMessages.Count -eq 2) 'Invalid Y/N input was not retried.'
                Assert-Condition (($promptState.CredentialMessages -join ',') -eq 'ONTAP SSH credentials for cluster1,ONTAP SSH credentials for cluster2.example.com') 'Per-cluster prompts did not contain the supplied target names.'
                Assert-Condition (($users -join ',') -eq 'prompt-user-1,prompt-user-2') 'The wrong credential was supplied to a cluster.'
            }
            else {
                Assert-Condition ($promptState.ChoiceMessages.Count -eq 0 -and $promptState.CredentialMessages[0] -match '192.0.2.10') 'Single-cluster invocation asked an unnecessary reuse question or omitted its target.'
            }
        }
        Write-Host "PASS: interactive credential mode $mode (fake credentials only)"
    }
    $reportGenerator = Join-Path $testDirectory 'ReportAssets\New-OntapHealthReport.ps1'
    Remove-Item -LiteralPath $reportGenerator -Force
    $missingGeneratorOutput = Join-Path $testDirectory 'missing-report-generator-output'
    $failure = $null
    try { $null = & $runner -Clusters 'cluster1' -Credential $credential -NonInteractive -OutputDirectory $missingGeneratorOutput }
    catch { $failure = $_.Exception.Message }
    Assert-Condition ($failure -match 'Required runtime file\(s\) are missing:.*New-OntapHealthReport\.ps1' -and -not (Test-Path -LiteralPath $missingGeneratorOutput)) 'A missing report generator was not detected before collection.'
    Write-Host 'PASS: missing report generator is diagnosed before collection'
}
finally {
    Remove-Item Function:\global:Start-Process -ErrorAction SilentlyContinue
    Remove-Variable -Name ontapTestOpenedReportPaths, ontapTestFailReportOpen -Scope Global -ErrorAction SilentlyContinue
    Get-Module ONTAP.HealthCheck | Remove-Module -Force
    Import-Module $modulePath -Force
    Remove-Item -LiteralPath $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
}