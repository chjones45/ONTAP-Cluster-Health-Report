#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\Modules\ONTAP.HealthCheck.psm1'
Import-Module $modulePath -Force
$module = Get-Module ONTAP.HealthCheck

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

try {
    foreach ($lineEnding in @("`n", "`r`n", "`r`r`n", "`r")) {
        $response = $lineEnding + 'Last login time: 10/26/2026 17:41:48' + $lineEnding + $lineEnding + 'There are no entries matching your query.' + $lineEnding
        $recognized = & $module { param($response) Test-OntapEmptyResponse -Output $response } $response
        Assert-Condition $recognized 'Login banner parsing failed for a supported line-ending variant.'
        $unsafeResponse = $response + 'Warning: partial response'
        $recognized = & $module { param($response) Test-OntapEmptyResponse -Output $response } $unsafeResponse
        Assert-Condition (-not $recognized) 'Banner normalization hid additional output.'
    }
    Write-Host 'PASS: login banner line-ending normalization'
    $partitionedResponse = "`r`r`nLast login time: 10/26/2026 17:46:45`r`r`n`r`n`r`nThere are no entries matching your query.`r`n" + [char]7 + "`r`nInfo: This cluster has partitioned disks. To get a complete list of spare disk`r`n      capacity use `"storage aggregate show-spare-disks`".`r`n`r`n"
    $recognized = & $module { param($response) Test-OntapEmptyResponse -Output $response -AllowPartitionedDiskNote } $partitionedResponse
    Assert-Condition $recognized 'Known partitioned-disk response was not recognized.'
    $recognized = & $module { param($response) Test-OntapEmptyResponse -Output $response } $partitionedResponse
    Assert-Condition (-not $recognized) 'Informational disk note was eligible for NoFindings.'
    $partitionedPoolResponse = $partitionedResponse.TrimEnd() + "`r`n      This cluster has storage pools. To view available capacity in the storage`r`n      pools use `"storage pool show-available-capacity`".`r`n"
    $recognized = & $module { param($response) Test-OntapEmptyResponse -Output $response -AllowPartitionedDiskNote } $partitionedPoolResponse
    Assert-Condition $recognized 'Known partitioned-disk and storage-pool notices were not recognized together.'
    $recognized = & $module { param($response) Test-OntapEmptyResponse -Output $response } $partitionedPoolResponse
    Assert-Condition (-not $recognized) 'Informational partitioned-disk and pool notes were accepted without the opt-in disk-check context.'
    $storagePoolOnlyResponse = "There are no entries matching your query.`r`n`r`nInfo: This cluster has storage pools. To view available capacity in the storage`r`n      pools use `"storage pool show-available-capacity`".`r`n"
    $recognized = & $module { param($response) Test-OntapEmptyResponse -Output $response -AllowPartitionedDiskNote } $storagePoolOnlyResponse
    Assert-Condition $recognized 'Storage-pool-only capacity note was not recognized as informational for the disk check.'
    $recognized = & $module { param($response) Test-OntapEmptyResponse -Output $response } $storagePoolOnlyResponse
    Assert-Condition (-not $recognized) 'Storage-pool informational note was accepted without the opt-in disk-check context.'
    foreach ($extraText in @('Warning: partial response', 'Error: command failed', 'Info: another message')) {
        $recognized = & $module { param($response) Test-OntapEmptyResponse -Output $response -AllowPartitionedDiskNote } ($partitionedPoolResponse + $extraText)
        Assert-Condition (-not $recognized) 'Disk note recognition hid additional output.'
        $recognized = & $module { param($response) Test-OntapEmptyResponse -Output $response -AllowPartitionedDiskNote } ($storagePoolOnlyResponse + $extraText)
        Assert-Condition (-not $recognized) 'Storage-pool note recognition hid additional output.'
    }
    Write-Host 'PASS: exact partitioned-disk and storage-pool notes remain informational and preserve other messages'
    & $module {
        $script:testVersion = 'NetApp Release 9.16.1P12: Wed Mar 11 12:37:44 UTC 2026'
        $script:testFailure = ''
        $script:testDiskOutput = $null
        $script:testPoolOutput = $null
        $script:testVerboseVersion = 'NetApp Release 9.16.1P12: <1O>'
        $script:testCalls = @()
        $script:testNodeCount = 2
        $script:testSwitchCount = 0
        $script:testSwitchInventoryUnknown = $false
        $script:testHaConfigured = 'true'
        $script:testSwitchlessEnabled = 'true'
        function script:Invoke-OntapSshCommand {
            param($Target, [System.Management.Automation.PSCredential]$Credential, [switch]$NonInteractive, [string[]]$Command, [switch]$Advanced, [switch]$ContinueOnCommandError, $Session, [scriptblock]$SessionBody)
            if ($null -ne $SessionBody) {
                & $SessionBody ([pscustomobject]@{ Broken = $false })
                return
            }
            $script:testCalls += $Command
            if ($Command[0] -eq 'version') {
                return [pscustomobject]@{ StdOut = $script:testVersion }
            }
            if (-not $Advanced -or -not $ContinueOnCommandError) { throw 'Missing collector execution controls.' }
            $output = 'There are no entries matching your query.'
            if ($Command[0] -eq 'cluster identity show') { $output = "Cluster UUID:`r`n12345678-1234-1234-1234-123456789abc`r`nCluster Name: test-cluster`r`n" }
            elseif ($Command[0] -eq 'storage disk show -state !spare,!present -container-type !remote,!mediator' -and $null -ne $script:testDiskOutput) { $output = $script:testDiskOutput }
            elseif ($Command[0] -eq 'storage pool show -is-healthy false' -and $null -ne $script:testPoolOutput) { $output = $script:testPoolOutput }
            elseif ($Command[0] -eq 'system node show -fields node') {
                $nodeRows = @('Node', '----------')
                if ($null -ne $script:testNodeCount) { for ($nodeIndex = 1; $nodeIndex -le $script:testNodeCount; $nodeIndex++) { $nodeRows += "node$nodeIndex" } }
                $entryLabel = if ($script:testNodeCount -eq 1) { '1 entry was displayed.' } else { "$($script:testNodeCount) entries were displayed." }
                $output = ($nodeRows -join "`r`n") + "`r`n$entryLabel`r`n"
            }
            elseif ($Command[0] -eq 'system switch ethernet show -type cluster-network' -and $script:testSwitchInventoryUnknown) { $output = 'Unrecognized switch inventory response.' }
            elseif ($Command[0] -eq 'system switch ethernet show -type cluster-network' -and $script:testSwitchCount -gt 0) {
                $switchRows = @('Switch Type', '---------- ---------------')
                for ($switchIndex = 1; $switchIndex -le $script:testSwitchCount; $switchIndex++) { $switchRows += "switch$switchIndex cluster-network" }
                $entryLabel = if ($script:testSwitchCount -eq 1) { '1 entry was displayed.' } else { "$($script:testSwitchCount) entries were displayed." }
                $output = ($switchRows -join "`r`n") + "`r`n$entryLabel`r`n"
            }
            elseif ($Command[0] -eq 'storage aggregate show-spare-disks') { $output = "Original Owner: node1`r`nPool0 Spare Pool`r`n1.0.10 SSD solid-state 894GB 894GB zeroed`r`n" }
            elseif ($Command[0] -eq 'cluster ha show') { $output = "High-Availability Configured: $script:testHaConfigured" }
            elseif ($Command[0] -eq 'network options switchless-cluster show') { $output = "Enable Switchless Cluster: $script:testSwitchlessEnabled" }
            if ($Command[0] -eq 'version -v') { $output = $script:testVerboseVersion }
            $errorText = $null
            $exitCode = 0
            $status = 'Collected'
            if ($Command[0] -eq 'storage errors show') {
                switch ($script:testFailure) {
                    'cli' { $output = 'Error: command failed: not authorized'; $errorText = $output; $status = 'Error' }
                    'empty' { $output = ''; $errorText = 'No successful response'; $status = 'Error' }
                    'findings' { $output = 'node1 disk1 failed' }
                    'warning' { $output = "Warning: partial response`nThere are no entries matching your query." }
                    'transport' { $output = ''; $exitCode = 255; $errorText = 'Host key verification failed.'; $status = 'Error' }
                }
            }
            if ($script:testFailure -eq 'start' -and $Command[0] -like '*cluster-connectivity start*') {
                $status = 'Error'
                $errorText = 'Diagnostic start failed.'
            }
            $standardError = ''
            if ($Command[0] -like '*cluster-connectivity show*' -and $script:testFailure -like 'connectivity-*') {
                $output = "`r`r`nLast login time: 10/26/2026 20:49:14`r`r`nNode: node1`r`nPacket Loss: none`r`nNode: node2`r`nPacket Loss: none`r`n"
                switch ($script:testFailure) {
                    'connectivity-loss' { $output = $output -replace 'Packet Loss: none', 'Packet Loss: partial' }
                    'connectivity-unknown' { $output = $output -replace 'Packet Loss: none', 'Packet Loss: unknown' }
                    'connectivity-missing' { $output += 'Node: node3' }
                    'connectivity-empty' { $output = 'There are no entries matching your query.' }
                    'connectivity-warning' { $output += 'Warning: partial response' }
                    'connectivity-stderr' { $standardError = 'Connection closed unexpectedly.' }
                    'connectivity-pending' { $output += 'Test in progress' }
                }
            }
            [pscustomobject]@{ StdOut = $output; StdErr = $standardError; ExitCode = $exitCode; Status = $status; Error = $errorText }
        }
    }
    $parameters = @{
        Target = 'cluster.example.com'
        Credential = New-Object System.Management.Automation.PSCredential('test', (ConvertTo-SecureString 'test' -AsPlainText -Force))
        NonInteractive = $true
    }
    $catalog = @(Get-OntapHealthCheckCommand)
    $storagePoolDefinition = @($catalog | Where-Object Command -eq 'storage pool show -is-healthy false')
    Assert-Condition ($storagePoolDefinition.Count -eq 1 -and $storagePoolDefinition[0].Category -eq 'Storage' -and $storagePoolDefinition[0].Description -match 'SSD storage pools' -and $storagePoolDefinition[0].PassMessage -match 'does not establish' -and $storagePoolDefinition[0].DocumentationUrl -eq 'https://docs.netapp.com/us-en/ontap-cli/storage-pool-show.html') 'Storage-pool health check or ONTAP documentation metadata is missing.'
    $supportedCatalog = @($catalog | Where-Object { $_.MinimumVersion -le [version]'9.16.1' })
    $topologyCommands = @('cluster ha show', 'network options switchless-cluster show')
    $expectedEmptyQueries = @($supportedCatalog | Where-Object { $_.Phase -eq 'Check' -and $_.Command -ne 'version -v' -and $_.Command -notin $topologyCommands }).Count
    $expectedDiagnostics = @($supportedCatalog | Where-Object Diagnostic).Count
    Assert-Condition ($catalog.Count -gt 0) 'The command catalog is empty.'
    Assert-Condition (@($catalog | Where-Object { [string]::IsNullOrWhiteSpace($_.Description) }).Count -eq 0) 'Current checks are missing descriptions.'
    Assert-Condition (@($catalog | Where-Object { $_.Phase -eq 'Check' -and $_.Command -ne 'version -v' -and [string]::IsNullOrWhiteSpace($_.PassMessage) }).Count -eq 0) 'Current query checks are missing explicit pass interpretations.'
    Assert-Condition (@($catalog.Command | Select-Object -Unique).Count -eq $catalog.Count) 'Duplicate catalog commands.'
    $dataChecks = @($catalog | Where-Object Category -eq 'Data')
    $mediatorCommands = @('snapmirror mediator show -connection-status !connected', 'snapmirror mediator show -quorum-status !true')
    Assert-Condition (($dataChecks[-2..-1].Command -join "`n") -ceq ($mediatorCommands -join "`n")) 'Mediator checks must be the final two Data entries in the requested order.'
    foreach ($mediator in @($dataChecks | Where-Object { $_.Command -in $mediatorCommands })) {
        Assert-Condition ($mediator.MinimumVersion -eq [version]'9.9.1' -and -not $mediator.Diagnostic -and $mediator.PassMessage -match 'empty result') 'Mediator release support, read-only classification or deployment caveat is missing.'
    }
    $singleLink = @($catalog | Where-Object Command -eq 'system ha interconnect status show -link-status !"-",!up')
    Assert-Condition ($singleLink.Count -eq 1 -and $singleLink[0].PassMessage -match 'dash-valued records were excluded' -and [string]::IsNullOrWhiteSpace($singleLink[0].InterpretationQuestion)) 'Single-link HA check must use the confirmed comma-separated exclusions and resolved assessment.'
    Assert-Condition (@($catalog | Where-Object Command -like '*-link-status* -link-status*').Count -eq 0) 'Repeated link-status parameter was reintroduced.'
    $report = Invoke-OntapHealthCheck @parameters -InformationVariable progressMessages
    $messages = @($progressMessages | ForEach-Object { ([string]$_.MessageData).Trim() })
    $expectedMessages = @(
        'Starting cluster connectivity checks'
        $supportedCatalog | Where-Object Phase -eq 'Check' | Select-Object -ExpandProperty Category -Unique | ForEach-Object { "Performing Checks: $_" }
        'Collecting cluster connectivity results'
    )
    Assert-Condition (($messages -join "`n") -ceq ($expectedMessages -join "`n")) 'Progress must announce each category once in KB order, with separate connectivity phases.'
    Write-Host 'PASS: category progress is ordered, emitted once and kept outside report output'
    Assert-Condition ($report.Version -eq '9.16.1') 'Patch release detection failed.'
    Assert-Condition ($report.Release -eq 'NetApp Release 9.16.1P12' -and $report.VersionOutput -eq $report.Release) 'Release patch suffix was lost or build timestamp was retained.'
    Assert-Condition ($report.Checks.Count -eq $catalog.Count) 'Report does not contain one result per catalog entry.'
    $storagePoolCheck = $report.Checks | Where-Object Command -eq 'storage pool show -is-healthy false'
    Assert-Condition ($storagePoolCheck.Status -eq 'Collected' -and $storagePoolCheck.Health -eq 'NoFindings') "An empty unhealthy-storage-pool query did not pass: status='$($storagePoolCheck.Status)' health='$($storagePoolCheck.Health)' outcome='$($storagePoolCheck.AssessmentOutcome)' reason='$($storagePoolCheck.Reason)' output='$($storagePoolCheck.StdOut)'."
    & $module { $script:testDiskOutput = "There are no entries matching your query.`r`n`r`nInfo: This cluster has storage pools. To view available capacity in the storage`r`n      pools use `"storage pool show-available-capacity`".`r`n" }
    $diskBannerReport = Invoke-OntapHealthCheck @parameters
    $diskCheck = $diskBannerReport.Checks | Where-Object Command -eq 'storage disk show -state !spare,!present -container-type !remote,!mediator'
    Assert-Condition ($diskCheck.Status -eq 'Collected' -and $diskCheck.Health -eq 'NoFindings' -and $diskCheck.Reason -match 'storage-pool capacity note is informational') 'Storage-pool CLI guidance changed the abnormal-disk check from NoFindings.'
    & $module { $script:testDiskOutput = $null; $script:testPoolOutput = "Storage Pool`r`n-----------`r`nFlashPool-1`r`nIs Pool Healthy?: false`r`nReason for storage pool being unhealthy: insufficient healthy disks`r`n1 entry was displayed.`r`n" }
    $unhealthyPoolReport = Invoke-OntapHealthCheck @parameters
    $storagePoolCheck = $unhealthyPoolReport.Checks | Where-Object Command -eq 'storage pool show -is-healthy false'
    Assert-Condition ($storagePoolCheck.Health -eq 'ReviewRequired' -and $storagePoolCheck.AssessmentOutcome -eq 'findings' -and $storagePoolCheck.Reason -match 'unhealthy storage pools') "Reported unhealthy storage-pool rows were not classified as findings: status='$($storagePoolCheck.Status)' health='$($storagePoolCheck.Health)' outcome='$($storagePoolCheck.AssessmentOutcome)' reason='$($storagePoolCheck.Reason)' output='$($storagePoolCheck.StdOut)'."
    & $module { $script:testPoolOutput = $null }
    Assert-Condition (@($report.Checks | Where-Object Status -eq 'Skipped').Count -eq ($catalog.Count - $supportedCatalog.Count)) 'Default collection skipped the wrong number of checks.'
    Assert-Condition (@($report.Checks | Where-Object Health -eq 'NoFindings').Count -eq ($expectedEmptyQueries + 2)) 'Empty-query checks and matching two-node topology checks did not pass.'
    foreach ($passed in @($report.Checks | Where-Object Health -eq 'NoFindings')) {
        $definition = $catalog | Where-Object Command -eq $passed.Command
        Assert-Condition ($passed.Reason.StartsWith($definition.PassMessage)) 'Check-specific pass feedback was not retained.'
        Assert-Condition ($passed.Description -eq $definition.Description) 'The report lost the check description.'
    }
    Assert-Condition (@($report.Checks | Where-Object { $_.Diagnostic -and $_.Status -eq 'Collected' }).Count -eq $expectedDiagnostics) 'Diagnostics were not collected by default.'
    Assert-Condition $report.IncludeDiagnostics 'Report did not reflect default diagnostic execution.'
    Assert-Condition ([datetimeoffset]::Parse($report.StartedAt).Offset -eq [datetimeoffset]::Now.Offset) 'Report timestamp did not retain the runner local offset.'
    Assert-Condition (@($report.Checks | Where-Object { [datetimeoffset]::Parse($_.StartedAt).Offset -ne [datetimeoffset]::Now.Offset }).Count -eq 0) 'Check timestamps did not retain the local offset.'
    Assert-Condition ($report.PSObject.Properties.Name -notcontains 'StartedAtUtc') 'Local timestamps retained misleading UTC property names.'
    Assert-Condition ($report.Inventory.ClusterName -eq 'test-cluster' -and $report.Inventory.ClusterUuid -eq '12345678-1234-1234-1234-123456789abc' -and $report.Inventory.NodeCount -eq 2 -and $report.Inventory.ClusterSwitchCount -eq 0) "Cluster identity or node/switch inventory was not captured: name='$($report.Inventory.ClusterName)' UUID='$($report.Inventory.ClusterUuid)' nodes='$($report.Inventory.NodeCount)' switches='$($report.Inventory.ClusterSwitchCount)'."
    Assert-Condition ($report.Inventory.SpareDiskInventoryCommand -eq 'storage aggregate show-spare-disks' -and $report.Inventory.SpareDiskInventoryStatus -eq 'Collected' -and $report.Inventory.SpareDiskInventoryOutput -match '1\.0\.10' -and [string]::IsNullOrWhiteSpace($report.Inventory.SpareDiskInventoryError)) 'Unassessed spare-disk inventory was not retained separately from health checks.'
    foreach ($case in @(
        @{ Name = 'two-node switchless'; Nodes = 2; Switches = 0; SwitchUnknown = $false; Ha = 'true'; Switchless = 'true'; HaHealth = 'NoFindings'; SwitchHealth = 'NoFindings'; HaOutcome = 'pass'; SwitchOutcome = 'pass' },
        @{ Name = 'two-node switched'; Nodes = 2; Switches = 2; SwitchUnknown = $false; Ha = 'true'; Switchless = 'false'; HaHealth = 'NoFindings'; SwitchHealth = 'NoFindings'; HaOutcome = 'pass'; SwitchOutcome = 'pass' },
        @{ Name = 'more than two nodes'; Nodes = 3; Switches = 2; SwitchUnknown = $false; Ha = 'false'; Switchless = 'false'; HaHealth = 'NoFindings'; SwitchHealth = 'NoFindings'; HaOutcome = 'pass'; SwitchOutcome = 'pass' },
        @{ Name = 'single node'; Nodes = 1; Switches = 0; SwitchUnknown = $false; Ha = 'false'; Switchless = 'false'; HaHealth = 'NotApplicable'; SwitchHealth = 'NotApplicable'; HaOutcome = 'info'; SwitchOutcome = 'info' },
        @{ Name = 'HA disabled on two nodes'; Nodes = 2; Switches = 0; SwitchUnknown = $false; Ha = 'false'; Switchless = 'true'; HaHealth = 'ReviewRequired'; SwitchHealth = 'NoFindings'; HaOutcome = 'findings'; SwitchOutcome = 'pass' },
        @{ Name = 'switchless enabled with switches'; Nodes = 2; Switches = 2; SwitchUnknown = $false; Ha = 'true'; Switchless = 'true'; HaHealth = 'NoFindings'; SwitchHealth = 'ReviewRequired'; HaOutcome = 'pass'; SwitchOutcome = 'findings' },
        @{ Name = 'invalid zero-node inventory'; Nodes = 0; Switches = 0; SwitchUnknown = $false; Ha = 'false'; Switchless = 'false'; HaHealth = 'ReviewRequired'; SwitchHealth = 'ReviewRequired'; HaOutcome = 'review'; SwitchOutcome = 'review' },
        @{ Name = 'unknown cluster-switch inventory'; Nodes = 2; Switches = 0; SwitchUnknown = $true; Ha = 'true'; Switchless = 'true'; HaHealth = 'NoFindings'; SwitchHealth = 'ReviewRequired'; HaOutcome = 'pass'; SwitchOutcome = 'review' }
    )) {
        & $module { param($case) $script:testNodeCount = $case.Nodes; $script:testSwitchCount = $case.Switches; $script:testSwitchInventoryUnknown = $case.SwitchUnknown; $script:testHaConfigured = $case.Ha; $script:testSwitchlessEnabled = $case.Switchless } $case
        $topologyReport = Invoke-OntapHealthCheck @parameters
        $haCheck = $topologyReport.Checks | Where-Object Command -eq 'cluster ha show'
        $switchlessCheck = $topologyReport.Checks | Where-Object Command -eq 'network options switchless-cluster show'
        Assert-Condition ($haCheck.Health -eq $case.HaHealth -and $switchlessCheck.Health -eq $case.SwitchHealth) "Incorrect topology health for $($case.Name)."
        Assert-Condition ($haCheck.AssessmentOutcome -eq $case.HaOutcome -and $switchlessCheck.AssessmentOutcome -eq $case.SwitchOutcome) "Incorrect report outcome for $($case.Name)."
        Assert-Condition ($haCheck.StdOut -match 'High-Availability Configured:' -and $switchlessCheck.StdOut -match 'Enable Switchless Cluster:') "Topology output was not retained for $($case.Name)."
    }
    & $module { $script:testNodeCount = 2; $script:testSwitchCount = 0; $script:testSwitchInventoryUnknown = $false; $script:testHaConfigured = 'true'; $script:testSwitchlessEnabled = 'true' }
    Write-Host 'PASS: captured cluster inventory and topology-aware HA/switchless assessments'
    $report = Invoke-OntapHealthCheck @parameters -IncludeDiagnostics:$false
    Assert-Condition (@($report.Checks | Where-Object Status -eq 'Collected').Count -eq $supportedCatalog.Count) 'Legacy diagnostic switch excluded required checks.'
    Assert-Condition $report.IncludeDiagnostics 'Legacy switch changed diagnostic execution metadata.'
    Write-Host 'PASS: catalog and unconditional diagnostic inclusion'

    foreach ($release in @('9.1', '9.2', '9.5', '9.6', '9.8', '9.9.1')) {
        & $module { param($release) $script:testVersion = "NetApp Release $release"; $script:testCalls = @() } $release
        $report = Invoke-OntapHealthCheck @parameters -InformationVariable releaseProgress
        if ([version]$release -lt [version]'9.9.1') {
            $messages = @($releaseProgress | ForEach-Object { [string]$_.MessageData })
            Assert-Condition (@($messages | Where-Object { $_ -match 'cluster connectivity' }).Count -eq 0) 'Skipped connectivity checks were announced as running.'
        }
        foreach ($definition in $catalog) {
            $actual = @($report.Checks | Where-Object Command -eq $definition.Command)[0]
            $expected = if ([version]$release -lt $definition.MinimumVersion) { 'Skipped' } else { 'Collected' }
            Assert-Condition ($actual.Status -eq $expected) "Release gate failed: $release / $($definition.Command)"
        }
    }
    $calls = & $module { $script:testCalls }
    Assert-Condition (($calls[1..4] -join "`n") -ceq "cluster identity show`nsystem node show -fields node`nsystem switch ethernet show -type cluster-network`nstorage aggregate show-spare-disks" -and $calls[5] -like '*cluster-connectivity start*' -and $calls[-1] -like '*cluster-connectivity show*') 'Inventory capture or diagnostic start/results ordering failed.'
    $expectedOrder = @(foreach ($phase in @('Start', 'Check', 'Results')) {
        $catalog | Where-Object Phase -eq $phase | Select-Object -ExpandProperty Command
    })
    Assert-Condition (($report.Checks.Command -join "`n") -ceq ($expectedOrder -join "`n")) 'Intervening checks did not retain KB order.'
    Assert-Condition ($report.Checks[-1].Health -eq 'ReviewRequired') 'An empty connectivity-results query incorrectly passed without test records.'
    Write-Host 'PASS: version boundaries and diagnostic ordering'

    $categories = @($catalog | Where-Object Phase -eq 'Check' | Select-Object -ExpandProperty Category -Unique)
    Assert-Condition (($categories -join ',') -match 'General,Security,Storage') 'Security checks do not run between General and Storage.'
    foreach ($case in @(
        @{ Output = 'NetApp Release 9.16.1P12: <1O>'; Build = 'DAR'; Health = 'Successful' },
        @{ Output = 'NetApp Release 9.16.1P12: <1Ono-DARE>'; Build = 'NODAR'; Health = 'ReviewRequired' },
        @{ Output = "NetApp Release 9.16.1P12: <1O>`nNetApp Release 9.16.1P12: <1Ono-DARE>"; Build = 'NODAR'; Health = 'ReviewRequired' },
        @{ Output = 'NetApp Release 9.16.1P12: <1Ounknown>'; Build = 'Unknown'; Health = 'ReviewRequired' },
        @{ Output = 'There are no entries matching your query.'; Build = 'Unknown'; Health = 'ReviewRequired' },
        @{ Output = "Warning: incomplete response`nNetApp Release 9.16.1P12: <1O>"; Build = 'DAR'; Health = 'ReviewRequired' }
    )) {
        & $module { param($output) $script:testVerboseVersion = $output } $case.Output
        $report = Invoke-OntapHealthCheck @parameters
        $nodar = $report.Checks | Where-Object Command -eq 'version -v'
        Assert-Condition ($nodar.Name -eq 'NODAR check' -and $nodar.Category -eq 'Security') 'NODAR display metadata was not preserved.'
        Assert-Condition ($nodar.EncryptionBuild -eq $case.Build -and $nodar.Health -eq $case.Health) 'DAR/NODAR build classification was incorrect.'
        Assert-Condition ($nodar.StdOut -ceq $case.Output) 'NODAR evidence was changed or lost.'
    }
    & $module { $script:testVerboseVersion = 'NetApp Release 9.16.1P12: <1O>' }
    Write-Host 'PASS: NODAR, DAR, mixed/unknown builds, warnings and Security ordering'

    foreach ($mode in @('connectivity-none', 'connectivity-loss', 'connectivity-unknown', 'connectivity-missing', 'connectivity-empty', 'connectivity-warning', 'connectivity-stderr', 'connectivity-pending')) {
        & $module { param($mode) $script:testFailure = $mode } $mode
        $report = Invoke-OntapHealthCheck @parameters
        $result = $report.Checks[-1]
        $expectedHealth = if ($mode -eq 'connectivity-none') { 'Successful' } else { 'ReviewRequired' }
        Assert-Condition ($result.Health -eq $expectedHealth) "Incorrect connectivity classification: $mode"
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($result.StdOut)) 'Connectivity evidence was discarded.'
        if ($mode -eq 'connectivity-none') {
            Assert-Condition ($result.StdOut.Contains("`r`r`nLast login time:")) 'Raw connectivity output was normalized in the report.'
        }
    }
    Write-Host 'PASS: local timestamps and script-side connectivity loss assessment with raw output retained'

    foreach ($mode in @('cli', 'empty', 'findings', 'warning', 'transport', 'start')) {
        & $module { param($mode) $script:testFailure = $mode; $script:testCalls = @() } $mode
        $report = Invoke-OntapHealthCheck @parameters
        if ($mode -eq 'start') {
            $results = @($report.Checks | Where-Object Command -like '*cluster-connectivity show*')[0]
            Assert-Condition ($results.Status -eq 'Skipped') 'Queried stale results after failed diagnostic start.'
        }
        else {
            $check = @($report.Checks | Where-Object Command -eq 'storage errors show')[0]
            Assert-Condition ($check.Health -ne 'NoFindings') "False healthy result for $mode."
            if ($mode -eq 'transport') {
                $calls = & $module { $script:testCalls }
                Assert-Condition ($calls[-1] -eq 'storage errors show') 'Continued SSH attempts after transport failure.'
            }
            else {
                Assert-Condition ($report.Checks[-1].Status -eq 'Collected') 'A command failure prevented subsequent collection.'
            }
        }
    }
    Write-Host 'PASS: errors, partial output, transport failure and failed diagnostic start'

    foreach ($versionText in @('unrecognized output', 'NetApp Release 10.1')) {
        & $module { param($versionText) $script:testVersion = $versionText; $script:testCalls = @() } $versionText
        $failure = $null
        try { $null = Invoke-OntapHealthCheck @parameters } catch { $failure = $_.Exception.Message }
        Assert-Condition ($failure -match 'Cannot determine a supported ONTAP 9 release') 'Unknown release did not fail closed.'
        $calls = @(& $module { $script:testCalls })
        Assert-Condition ($calls.Count -eq 1) 'Health commands ran without a supported version.'
    }
    Write-Host "PASS: unknown release rejection ($($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion))"
}
finally {
    Import-Module $modulePath -Force
}