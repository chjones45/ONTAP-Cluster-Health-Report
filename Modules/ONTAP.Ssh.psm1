#Requires -Version 5.1

<#
.SYNOPSIS
Provides the standalone ONTAP SSH and health-check module.
.NOTES
Version: 0.2
Updated: 2026-10-30
Repository release version; standalone module behavior is unchanged in 0.2.
Version 0.1 was the initial release.
Use ONTAP.HealthCheck.psm1 for the runner's current platform-aware collector.
See README.md, Release History, for release details.
#>
Set-StrictMode -Version Latest

function ConvertTo-OntapSshArgument {
    param([AllowEmptyString()][string]$Argument)

    if ($Argument.Length -gt 0 -and $Argument -notmatch '[\s"]') { return $Argument }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq '\') { $backslashes++; continue }
        if ($character -eq '"') {
            [void]$builder.Append('\' * ($backslashes * 2 + 1)).Append('"')
        }
        else {
            [void]$builder.Append('\' * $backslashes).Append($character)
        }
        $backslashes = 0
    }
    [void]$builder.Append('\' * ($backslashes * 2)).Append('"')
    return $builder.ToString()
}

function Test-OntapEmptyResponse {
    param([AllowEmptyString()][string]$Output, [switch]$AllowPartitionedDiskNote)

    $body = $Output.Trim() -replace '\ALast login time:[^\r\n]*(?:[\r\n]+|\z)', ''
    if ($AllowPartitionedDiskNote) {
        $body = $body -replace '(?:\s|\x07)*Info: This cluster has partitioned disks\.\s+To get a complete list of spare disk\s+capacity use "storage aggregate show-spare-disks"\.(?:\s+This cluster has storage pools\.\s+To view available capacity in the storage\s+pools use "storage pool show-available-capacity"\.)?\s*\z', ''
    }
    return $body.Trim() -match '^(There are no entries matching your query\.|This table is currently empty\.)$'
}

function Invoke-OntapSshCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-zA-Z0-9:][a-zA-Z0-9.:%_-]*$')]
        [string]$Target,
        [System.Management.Automation.PSCredential]$Credential,
        [ValidateRange(1, 65535)][int]$Port = 22,
        [string]$KnownHostsPath,
        [switch]$AcceptNewHostKey,
        [switch]$NonInteractive,
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 60,
        [string]$SshExecutable = 'ssh',
        [string[]]$Command,
        [switch]$Advanced,
        [switch]$ContinueOnCommandError,
        [scriptblock]$SessionBody,
        [object]$Session
    )

    if ($null -ne $Session) {
        foreach ($commandText in $Command) {
            Invoke-OntapSessionCommand -Session $Session -Command $commandText -Advanced:$Advanced -TimeoutSeconds $TimeoutSeconds -ContinueOnCommandError:$ContinueOnCommandError
        }
        return
    }
    if ($null -eq $SessionBody -and @($Command).Count -eq 0) { throw 'Specify Command or SessionBody.' }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'This SSH implementation requires Windows (DPAPI and Windows OpenSSH).'
    }
    $sshCommand = Get-Command -Name $SshExecutable -CommandType Application -ErrorAction Stop | Select-Object -First 1
    if ($null -eq $Credential) {
        if ($NonInteractive) { throw 'Specify -Credential when using -NonInteractive.' }
        $Credential = Get-Credential -Message "ONTAP SSH credentials for $Target"
        if ($null -eq $Credential) { throw 'Credential entry was cancelled.' }
    }
    if ([string]::IsNullOrWhiteSpace($Credential.UserName) -or $Credential.UserName -match '[\r\n\x00]') {
        throw 'Specify a nonempty SSH user name without control characters.'
    }
    if ([string]::IsNullOrWhiteSpace($KnownHostsPath)) {
        $KnownHostsPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.ssh\known_hosts'
    }
    $KnownHostsPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($KnownHostsPath)
    if ($KnownHostsPath -match '[\r\n\x00"]') { throw 'KnownHostsPath contains unsupported characters.' }
    if ($AcceptNewHostKey) {
        $null = [System.IO.Directory]::CreateDirectory((Split-Path -Parent $KnownHostsPath))
        Write-Warning 'Trust on first use is enabled. Verify the cluster host-key fingerprint independently before proceeding.'
    }

    $hostKeyPolicy = if ($AcceptNewHostKey) { 'accept-new' } else { 'yes' }
    $sshArguments = @(
        '-F', 'NUL', '-T', '-p', [string]$Port,
        '-o', "StrictHostKeyChecking=$hostKeyPolicy",
        '-o', ('UserKnownHostsFile="{0}"' -f $KnownHostsPath.Replace('\', '/')),
        '-o', 'GlobalKnownHostsFile=NUL',
        '-o', 'ConnectTimeout=15', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=2',
        '-o', 'NumberOfPasswordPrompts=1',
        '-o', 'PreferredAuthentications=keyboard-interactive,password',
        '-o', 'PubkeyAuthentication=no', '-o', 'PasswordAuthentication=yes',
        '-o', 'KbdInteractiveAuthentication=yes', '-o', 'BatchMode=no',
        '-o', 'ForwardAgent=no', '-o', 'ClearAllForwardings=yes',
        '-l', $Credential.UserName, $Target
    )

    $helperDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('ontap-ssh-' + [guid]::NewGuid().ToString('N'))
    $process = $null
    $startInfo = $null
    try {
        $null = [System.IO.Directory]::CreateDirectory($helperDirectory)
        $helperPath = Join-Path $helperDirectory 'askpass.cmd'
        $hostExecutable = if ($PSVersionTable.PSEdition -eq 'Core') { Join-Path $PSHOME 'pwsh.exe' } else { Join-Path $PSHOME 'powershell.exe' }
        $helperCommand = '$secret = ConvertTo-SecureString $env:ONTAP_SSH_ASKPASS_BLOB; [Console]::Out.Write((New-Object System.Net.NetworkCredential -ArgumentList '''', $secret).Password)'
        $helperContent = "@`"$hostExecutable`" -NoLogo -NoProfile -NonInteractive -Command `"$helperCommand`"`r`n"
        [System.IO.File]::WriteAllText($helperPath, $helperContent, [System.Text.Encoding]::ASCII)

        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $sshCommand.Source
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
        $startInfo.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
        $startInfo.EnvironmentVariables['SSH_ASKPASS'] = $helperPath
        $startInfo.EnvironmentVariables['SSH_ASKPASS_REQUIRE'] = 'force'
        $startInfo.EnvironmentVariables['DISPLAY'] = 'ontap:0'
        $startInfo.EnvironmentVariables['ONTAP_SSH_ASKPASS_BLOB'] = ConvertFrom-SecureString -SecureString $Credential.Password

        if ($null -ne $SessionBody) {
            $startInfo.Arguments = (@($sshArguments | ForEach-Object { ConvertTo-OntapSshArgument $_ }) -join ' ')
            $process = [System.Diagnostics.Process]::Start($startInfo)
            $sessionState = [pscustomobject]@{
                Process = $process
                Target = $Target
                Port = $Port
                Advanced = $false
                Broken = $false
                Prompt = $null
                StdOutBuffer = New-Object char[] 4096
                StdErrBuffer = New-Object char[] 4096
                StdOutTask = $null
                StdErrTask = $null
                StdOutClosed = $false
                StdErrClosed = $false
                PendingOutput = ''
                StartupStdOut = ''
                StartupStdErr = ''
            }
            $sessionState.StdOutTask = $process.StandardOutput.ReadAsync($sessionState.StdOutBuffer, 0, 4096)
            $sessionState.StdErrTask = $process.StandardError.ReadAsync($sessionState.StdErrBuffer, 0, 4096)
            $greeting = Read-OntapSessionResponse -Session $sessionState -TimeoutSeconds $TimeoutSeconds
            $sessionState.StartupStdOut = $greeting.StdOut
            $sessionState.StartupStdErr = $greeting.StdErr
            $sessionResult = & $SessionBody $sessionState
            if (-not $sessionState.Broken -and -not $process.HasExited) {
                $process.StandardInput.WriteLine('exit')
                $process.StandardInput.Close()
                if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                    $sessionResult.SessionError = 'SSH session did not exit within the configured timeout.'
                    $process.Kill()
                    $process.WaitForExit()
                }
                $sessionResult.SessionExitCode = $process.ExitCode
                if ($process.ExitCode -ne 0 -and $null -eq $sessionResult.SessionError) { $sessionResult.SessionError = "SSH session exited with code $($process.ExitCode)." }
            }
            elseif ($process.HasExited) { $sessionResult.SessionExitCode = $process.ExitCode }
            if ($sessionState.Broken -and $null -eq $sessionResult.SessionError) { $sessionResult.SessionError = 'SSH session ended before all commands completed.' }
            $sessionResult.SessionStartupStdOut = $sessionState.StartupStdOut
            $sessionResult.SessionStartupStdErr = $sessionState.StartupStdErr
            $sessionResult
            return
        }
        $results = @()
        foreach ($commandText in $Command) {
            $remoteCommand = if ($Advanced) { 'set -privilege advanced -confirmations off; set -rows 0; ' + $commandText } else { $commandText }
            $startInfo.Arguments = (@($sshArguments + @($remoteCommand) | ForEach-Object { ConvertTo-OntapSshArgument $_ }) -join ' ')
            Write-Verbose "Running ONTAP command '$commandText' on ${Target}:$Port."
            $process = [System.Diagnostics.Process]::Start($startInfo)
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            $process.StandardInput.Close()
            if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                $process.Kill()
                $process.WaitForExit()
                $timedOut = $true
            }
            else { $timedOut = $false }
            $process.WaitForExit()
            $standardOutput = $stdoutTask.Result
            $standardError = $stderrTask.Result
            $exitCode = $process.ExitCode
            $process.Dispose()
            $process = $null
            $failure = $null
            $isDiskQuery = $commandText -match '^storage disk show(?:\s|$)'
            $recognizedEmptyExit = $Advanced -and $ContinueOnCommandError -and $exitCode -eq 255 -and
                [string]::IsNullOrWhiteSpace($standardError) -and (Test-OntapEmptyResponse -Output $standardOutput -AllowPartitionedDiskNote:$isDiskQuery)
            if ($timedOut) {
                $failure = "SSH command '$commandText' exceeded $TimeoutSeconds seconds."
            }
            elseif ($exitCode -ne 0 -and -not $recognizedEmptyExit) {
                $failure = "SSH command '$commandText' failed on ${Target}:$Port (exit $exitCode). Check the verified known-hosts entry, credentials, SSH access and account role. OpenSSH: $standardError"
            }
            elseif ([string]::IsNullOrWhiteSpace($standardOutput) -or ($standardOutput + "`n" + $standardError) -match '(?im)^\s*(Error:|command not found|Invalid command|.*not authorized|.*command not supported|.*permission denied)') {
                $failure = "ONTAP did not return a successful response to '$commandText': $standardOutput $standardError"
            }
            if ($null -ne $failure -and -not $ContinueOnCommandError) { throw $failure }
            $results += [pscustomobject]@{
                Target = $Target
                Port = $Port
                Command = $commandText
                ExitCode = $exitCode
                StdOut = $standardOutput
                StdErr = $standardError
                Status = if ($null -eq $failure) { 'Collected' } else { 'Error' }
                Error = $failure
            }
        }
        return $results
    }
    finally {
        if ($null -ne $process) {
            try { if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() } }
            finally { $process.Dispose() }
        }
        if ($null -ne $startInfo) { $startInfo.EnvironmentVariables.Remove('ONTAP_SSH_ASKPASS_BLOB') }
        if (Test-Path -LiteralPath $helperDirectory) {
            Remove-Item -LiteralPath $helperDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-OntapSessionResponse {
    param([object]$Session, [int]$TimeoutSeconds)

    $output = New-Object System.Text.StringBuilder
    [void]$output.Append($Session.PendingOutput)
    $Session.PendingOutput = ''
    $errors = New-Object System.Text.StringBuilder
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        if (-not $Session.StdErrClosed -and $Session.StdErrTask.IsCompleted) {
            $count = $Session.StdErrTask.GetAwaiter().GetResult()
            if ($count -eq 0) { $Session.StdErrClosed = $true }
            else {
                [void]$errors.Append($Session.StdErrBuffer, 0, $count)
                $Session.StdErrTask = $Session.Process.StandardError.ReadAsync($Session.StdErrBuffer, 0, 4096)
            }
        }
        if (-not $Session.StdOutClosed -and $Session.StdOutTask.IsCompleted) {
            $count = $Session.StdOutTask.GetAwaiter().GetResult()
            if ($count -eq 0) { $Session.StdOutClosed = $true }
            else {
                [void]$output.Append($Session.StdOutBuffer, 0, $count)
                $Session.StdOutTask = $Session.Process.StandardOutput.ReadAsync($Session.StdOutBuffer, 0, 4096)
            }
        }
        $text = $output.ToString()
        $promptPattern = '(?:\A|[\r\n])(?<prompt>[a-zA-Z0-9][a-zA-Z0-9_.-]*::\*?>)[\t ]*\z'
        if ($null -ne $Session.Prompt) {
            $promptPattern = '(?:\A|[\r\n])(?<prompt>' + [regex]::Escape($Session.Prompt) + '\*?>)[\t ]*\z'
        }
        $match = [regex]::Match($text, $promptPattern)
        if ($match.Success) {
            if ($null -eq $Session.Prompt) { $Session.Prompt = $match.Groups['prompt'].Value -replace '\*?>$', '' }
            $body = $text.Substring(0, $match.Groups['prompt'].Index)
            $promptTrailer = '(?:\A|[\r\n])(?:' + [regex]::Escape($Session.Prompt) + '\*?>[\t ]*(?:[\r\n]+|\z))+\z'
            $body = $body -replace $promptTrailer, ''
            return [pscustomobject]@{ StdOut = $body; StdErr = $errors.ToString() }
        }
        if ($Session.StdOutClosed -and $Session.StdErrClosed) {
            $Session.Broken = $true
            $exception = New-Object System.IO.IOException("SSH session disconnected before a command-completion prompt. Output: $text $($errors.ToString())")
            $exception.Data['StdOut'] = $text
            $exception.Data['StdErr'] = $errors.ToString()
            throw $exception
        }
        $remaining = $TimeoutSeconds * 1000 - [int]$clock.ElapsedMilliseconds
        if ($remaining -le 0) {
            $Session.Broken = $true
            $exception = New-Object System.TimeoutException("SSH session response exceeded $TimeoutSeconds seconds. Output: $text $($errors.ToString())")
            $exception.Data['StdOut'] = $text
            $exception.Data['StdErr'] = $errors.ToString()
            throw $exception
        }
        $tasks = @()
        if (-not $Session.StdOutClosed) { $tasks += $Session.StdOutTask }
        if (-not $Session.StdErrClosed) { $tasks += $Session.StdErrTask }
        if ($tasks.Count -gt 0) { $null = [Threading.Tasks.Task]::WaitAny([Threading.Tasks.Task[]]$tasks, $remaining) }
    }
}

function Invoke-OntapSessionCommand {
    param([object]$Session, [string]$Command, [switch]$Advanced, [int]$TimeoutSeconds, [switch]$ContinueOnCommandError)

    $response = $null
    $failure = $null
    try {
        if ($Session.Broken) { throw 'SSH session is no longer usable.' }
        if ($Advanced -and -not $Session.Advanced) {
            foreach ($setupCommand in @('set -privilege advanced -confirmations off', 'set -rows 0')) {
                $Session.Process.StandardInput.WriteLine($setupCommand)
                $setup = Read-OntapSessionResponse -Session $Session -TimeoutSeconds $TimeoutSeconds
                if ($setup.StdOut -match '(?im)^\s*(Error:|Warning:|.*not authorized|.*permission denied|Invalid command)' -or -not [string]::IsNullOrWhiteSpace($setup.StdErr)) {
                    $Session.Broken = $true
                    throw "ONTAP session setup failed: $($setup.StdOut) $($setup.StdErr)"
                }
            }
            $Session.Advanced = $true
        }
        $Session.Process.StandardInput.WriteLine($Command)
        $response = Read-OntapSessionResponse -Session $Session -TimeoutSeconds $TimeoutSeconds
        $response.StdOut = $response.StdOut -replace ('\A' + [regex]::Escape($Command) + '[\r\n]+'), ''
        if ([string]::IsNullOrWhiteSpace($response.StdOut) -or ($response.StdOut + "`n" + $response.StdErr) -match '(?im)^\s*(Error:|command not found|Invalid command|.*not authorized|.*command not supported|.*permission denied)') {
            $failure = "ONTAP did not return a successful response to '$Command': $($response.StdOut) $($response.StdErr)"
        }
    }
    catch {
        $Session.Broken = $true
        $failure = $_.Exception.Message
        if ($_.Exception.Data.Contains('StdOut')) {
            $response = [pscustomobject]@{ StdOut = [string]$_.Exception.Data['StdOut']; StdErr = [string]$_.Exception.Data['StdErr'] }
        }
    }
    if ($null -ne $failure -and -not $ContinueOnCommandError) { throw $failure }
    [pscustomobject]@{
        Target = $Session.Target
        Port = $Session.Port
        Command = $Command
        ExitCode = $null
        CommandSucceeded = $null -eq $failure
        StdOut = if ($null -ne $response) { $response.StdOut } else { '' }
        StdErr = if ($null -ne $response) { $response.StdErr } else { '' }
        Status = if ($null -eq $failure) { 'Collected' } else { 'Error' }
        Error = $failure
    }
}

function Test-OntapSshConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[a-zA-Z0-9:][a-zA-Z0-9.:%_-]*$')][string]$Target,
        [System.Management.Automation.PSCredential]$Credential,
        [ValidateRange(1, 65535)][int]$Port = 22,
        [string]$KnownHostsPath,
        [switch]$AcceptNewHostKey,
        [switch]$NonInteractive,
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 60,
        [string]$SshExecutable = 'ssh'
    )

    Invoke-OntapSshCommand @PSBoundParameters -Command @('version', 'cluster show')
}

function Get-OntapHealthCheckCommand {
    [CmdletBinding()]
    param()

    $descriptions = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'ONTAP.CheckDescriptions.psd1')
    $definitions = @(
        @('General', 'cluster kernel-service show -status-quorum out-of-quorum', '9.0', $false),
        @('General', 'cluster kernel-service show -status-avail !true', '9.0', $false),
        @('General', 'cluster kernel-service show -status-oper !operational', '9.0', $false),
        @('General', 'cluster peer health show -bypass-cache false -availability false', '9.0', $true),
        @('General', 'cluster ring show -online offline', '9.0', $false),
        @('General', 'cluster show -eligibility false', '9.0', $false),
        @('General', 'cluster show -health false', '9.0', $false),
        @('General', 'cluster ha show', '9.0', $false),
        @('General', 'job show -state Failure|Error|Quit|Dead|Unknown', '9.0', $false),
        @('General', 'system chassis show -status !ok', '9.0', $false),
        @('General', 'system controller config show-errors -description !"sysconfig: There are no configuration errors."*', '9.0', $false),
        @('General', 'system controller environment show -status !ok', '9.0', $false),
        @('General', 'system controller memory dimm show -status !ok', '9.0', $false),
        @('General', 'system controller service-event show', '9.0', $false),
        @('General', 'system fru-check show -fru-status !pass', '9.0', $false),
        @('General', 'system ha interconnect status show -is-link0-active !"-" -link0-status !up', '9.0', $false),
        @('General', 'system ha interconnect status show -is-link1-active !"-" -link1-status !up', '9.0', $false),
        @('General', 'system ha interconnect status show -link-status !"-",!up', '9.0', $false),
        @('General', 'system ha interconnect status show -ic-rdma !up', '9.0', $false),
        @('General', 'system health alert show', '9.0', $false),
        @('General', 'system health subsystem show -health !ok', '9.0', $false),
        @('General', 'system node environment sensors show -state !normal', '9.0', $false),
        @('General', 'system service-processor show -status !online', '9.0', $false),
        @('General', 'system services web node show -status !online', '9.0', $false),
        @('Security', 'version -v', '9.0', $false, 'NODAR check'),
        @('Security', 'security key-manager key query -restored false', '9.6', $false),
        @('Security', 'security key-manager key query -restored false', '9.6', $false),
        @('Storage', 'storage aggregate show -state !online', '9.0', $false),
        @('Storage', 'storage aggregate show -raidstatus !*normal*', '9.0', $false),
        @('Storage', 'storage aggregate object-store show -object-store-availability unavailable', '9.2', $false),
        @('Storage', 'storage bridge show -status !ok', '9.0', $false),
        @('Storage', 'storage disk show -state !spare,!present -container-type !remote,!mediator', '9.0', $false),
        @('Storage', 'storage errors show', '9.0', $false),
        @('Storage', 'storage failover show -enabled false', '9.0', $false),
        @('Storage', 'storage failover show -partner-aggregates !false -state-description !"Non-HA mode"', '9.0', $false),
        @('Storage', 'storage failover show -possible false', '9.0', $false),
        @('Storage', 'storage failover hwassist show -enabled false', '9.0', $false),
        @('Storage', 'storage failover hwassist show -local-inactive !"-"', '9.0', $false),
        @('Storage', 'storage port show -errors', '9.0', $false),
        @('Storage', 'storage shelf show -op-status !Normal', '9.0', $false),
        @('Network', 'network fcp adapter show -is-conn-established false -status-admin up', '9.0', $false),
        @('Network', 'network interface show -is-home false', '9.0', $false),
        @('Network', 'network interface show -status-oper down -status-extended !"This LIF is down because its Vserver is stopped"*', '9.0', $false),
        @('Network', 'network port ifgrp show -mode !singlemode -activeports !full', '9.0', $false),
        @('Network', 'network port ifgrp show -mode singlemode -activeports !partial', '9.0', $false),
        @('Network', 'network port reachability show -reachability-status !ok -expected-broadcast-domain !"-"', '9.8', $false),
        @('Network', 'network port show -health-status degraded', '9.0', $false),
        @('Network', 'network port show -link !up -up-admin true', '9.0', $false),
        @('Network', 'network options switchless-cluster show', '9.0', $false),
        @('Data', 'lun show -state !online', '9.0', $false),
        @('Data', 'snapmirror show -healthy false', '9.0', $false),
        @('Data', 'volume show -in-nvfailed-state true', '9.0', $false),
        @('Data', 'volume show -is-inconsistent true', '9.0', $false),
        @('Data', 'volume show -state !online,!restricted -size !"-"', '9.0', $false),
        @('Data', 'vserver cifs check -status down', '9.5', $true),
        @('Data', 'vserver cifs show -status-admin down', '9.0', $false),
        @('Data', 'vserver fcp show -status-admin down', '9.0', $false),
        @('Data', 'vserver iscsi show -status-admin down', '9.0', $false),
        @('Data', 'vserver nfs show -access !true', '9.0', $false),
        @('Data', 'vserver show -type data -operational-state !running -subtype !dp-destination,!sync-destination', '9.0', $false),
        @('Data', 'snapmirror mediator show -connection-status !connected', '9.9.1', $false),
        @('Data', 'snapmirror mediator show -quorum-status !true', '9.9.1', $false)
    )
    foreach ($definition in $definitions) {
        $details = if ($descriptions.ContainsKey($definition[1])) { $descriptions[$definition[1]] } else { @{} }
        [pscustomobject]@{
            Category = $definition[0]
            Name = if ($definition.Count -gt 4) { $definition[4] } elseif ($details.ContainsKey('Name')) { $details.Name } else { $null }
            Command = $definition[1]
            Description = $details['Description']
            PassMessage = $details['PassMessage']
            DocumentationUrl = $details['DocumentationUrl']
            InterpretationQuestion = $details['InterpretationQuestion']
            MinimumVersion = [version]$definition[2]
            Diagnostic = [bool]$definition[3]
            Phase = 'Check'
        }
    }
    foreach ($phase in @('Start', 'Results')) {
        $command = if ($phase -eq 'Start') { 'network interface check cluster-connectivity start -node *' } else { 'network interface check cluster-connectivity show -node * -date-time >10m -instance' }
        $details = $descriptions[$command]
        [pscustomobject]@{
            Category = 'Network'
            Name = $details.Name
            Command = $command
            Description = $details.Description
            PassMessage = $null
            DocumentationUrl = $details['DocumentationUrl']
            InterpretationQuestion = $null
            MinimumVersion = [version]'9.9.1'
            Diagnostic = $true
            Phase = $phase
        }
    }
}

function Invoke-OntapHealthCheckCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[a-zA-Z0-9:][a-zA-Z0-9.:%_-]*$')][string]$Target,
        [System.Management.Automation.PSCredential]$Credential,
        [ValidateRange(1, 65535)][int]$Port = 22,
        [string]$KnownHostsPath,
        [switch]$AcceptNewHostKey,
        [switch]$NonInteractive,
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 60,
        [string]$SshExecutable = 'ssh',
        [switch]$IncludeDiagnostics = $true,
        [Parameter(Mandatory = $true)][object]$Session
    )

    $connection = @{} + $PSBoundParameters
    $null = $connection.Remove('IncludeDiagnostics')
    $startedAt = [datetimeoffset]::Now.ToString('o')
    $discovery = Invoke-OntapSshCommand @connection -Command 'version'
    $releases = @([regex]::Matches($discovery.StdOut, 'NetApp Release\s+(\d+\.\d+(?:\.\d+)?)') | ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object)
    if ($releases.Count -eq 0 -or $releases[0].Major -ne 9) { throw "Cannot determine a supported ONTAP 9 release from: $($discovery.StdOut)" }
    $release = $releases[0]
    $releaseLabels = @([regex]::Matches($discovery.StdOut, '(?im)^\s*(NetApp Release\s+\d+\.\d+(?:\.\d+)?[^:\r\n]*)') | ForEach-Object { $_.Groups[1].Value.Trim() } | Select-Object -Unique)
    $releaseLabel = $releaseLabels -join '; '
    $identityRaw = Invoke-OntapSshCommand @connection -Command 'cluster identity show' -Advanced -ContinueOnCommandError
    $nodeInventoryRaw = Invoke-OntapSshCommand @connection -Command 'system node show -fields node' -Advanced -ContinueOnCommandError
    $switchInventoryRaw = Invoke-OntapSshCommand @connection -Command 'system switch ethernet show -type cluster-network' -Advanced -ContinueOnCommandError
    $spareDiskInventoryRaw = Invoke-OntapSshCommand @connection -Command 'storage aggregate show-spare-disks' -Advanced -ContinueOnCommandError
    $identityUsable = $identityRaw.Status -eq 'Collected' -and [string]::IsNullOrWhiteSpace($identityRaw.StdErr) -and $identityRaw.StdOut -notmatch '(?im)^\s*(Warning:|Error:|Info:)'
    $clusterName = $null
    $clusterUuid = $null
    if ($identityUsable) {
        $nameMatch = [regex]::Match($identityRaw.StdOut, '(?im)^[\t ]*Cluster Name:[\t ]*(?<value>[^\r\n]+)')
        $uuidMatch = [regex]::Match($identityRaw.StdOut, '(?im)^[\t ]*Cluster UUID:[\t ]*(?<value>[0-9a-fA-F-]{36})[\t ]*\r?$')
        if (-not $uuidMatch.Success) { $uuidMatch = [regex]::Match($identityRaw.StdOut, '(?im)^[\t ]*Cluster UUID:[\t ]*\r?\n[\t ]*(?<value>[0-9a-fA-F-]{36})[\t ]*\r?$') }
        if ($nameMatch.Success) { $clusterName = $nameMatch.Groups['value'].Value.Trim() }
        if ($uuidMatch.Success) { $clusterUuid = $uuidMatch.Groups['value'].Value.Trim() }
    }
    $nodeCount = $null
    if ($nodeInventoryRaw.Status -eq 'Collected' -and [string]::IsNullOrWhiteSpace($nodeInventoryRaw.StdErr) -and $nodeInventoryRaw.StdOut -notmatch '(?im)^\s*(Warning:|Error:|Info:)') {
        $nodeCountMatch = [regex]::Match($nodeInventoryRaw.StdOut, '(?im)^\s*(?<count>\d+)\s+entr(?:y|ies)\s+(?:were|was)\s+displayed\.')
        if ($nodeCountMatch.Success) { $nodeCount = [int]$nodeCountMatch.Groups['count'].Value }
    }
    $clusterSwitchCount = $null
    if ($switchInventoryRaw.Status -eq 'Collected' -and [string]::IsNullOrWhiteSpace($switchInventoryRaw.StdErr) -and $switchInventoryRaw.StdOut -notmatch '(?im)^\s*(Warning:|Error:|Info:)') {
        if (Test-OntapEmptyResponse -Output $switchInventoryRaw.StdOut) { $clusterSwitchCount = 0 }
        else {
            $switchCountMatch = [regex]::Match($switchInventoryRaw.StdOut, '(?im)^\s*(?<count>\d+)\s+entr(?:y|ies)\s+(?:were|was)\s+displayed\.')
            if ($switchCountMatch.Success) { $clusterSwitchCount = [int]$switchCountMatch.Groups['count'].Value }
        }
    }
    $inventory = [pscustomobject]@{
        ClusterName = $clusterName
        ClusterUuid = $clusterUuid
        IdentityStatus = if ($null -ne $clusterName -and $null -ne $clusterUuid) { 'Collected' } else { 'ReviewRequired' }
        NodeCount = $nodeCount
        NodeInventoryStatus = if ($null -ne $nodeCount -and $nodeCount -gt 0) { 'Collected' } else { 'ReviewRequired' }
        ClusterSwitchCount = $clusterSwitchCount
        ClusterSwitchInventoryStatus = if ($null -ne $clusterSwitchCount) { 'Collected' } else { 'ReviewRequired' }
        NodeInventoryOutput = $nodeInventoryRaw.StdOut
        ClusterSwitchInventoryOutput = $switchInventoryRaw.StdOut
        SpareDiskInventoryCommand = 'storage aggregate show-spare-disks'
        SpareDiskInventoryStatus = $spareDiskInventoryRaw.Status
        SpareDiskInventoryOutput = $spareDiskInventoryRaw.StdOut
        SpareDiskInventoryError = $spareDiskInventoryRaw.StdErr
    }
    $catalog = @(Get-OntapHealthCheckCommand)
    $plan = @($catalog | Where-Object Phase -eq 'Start') +
        @($catalog | Where-Object Phase -eq 'Check') +
        @($catalog | Where-Object Phase -eq 'Results')
    $checks = @()
    $connectivityStarted = $false
    $transportFailure = $Session.Broken
    $reportedCategories = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($check in $plan) {
        $status = 'Skipped'
        $reason = $null
        $raw = $null
        $health = 'Unknown'
        $encryptionBuild = $null
        $assessmentOutcome = $null
        $checkStartedAt = [datetimeoffset]::Now.ToString('o')
        if ($transportFailure) {
            $reason = 'Collection stopped after an SSH transport failure.'
        }
        elseif ($release -lt $check.MinimumVersion) {
            $reason = "Requires ONTAP $($check.MinimumVersion) or later."
        }
        elseif ($check.Phase -eq 'Results' -and -not $connectivityStarted) {
            $reason = 'Connectivity diagnostic start did not succeed; existing results were not queried.'
        }
        else {
            if ($check.Phase -eq 'Start') {
                Write-Host '  Starting cluster connectivity checks'
            }
            elseif ($check.Phase -eq 'Results') {
                Write-Host '  Collecting cluster connectivity results'
            }
            elseif ($reportedCategories.Add($check.Category)) {
                Write-Host "  Performing Checks: $($check.Category)"
            }
            $raw = Invoke-OntapSshCommand @connection -Command $check.Command -Advanced -ContinueOnCommandError
            $status = $raw.Status
            $reason = $raw.Error
            $transportFailure = $Session.Broken -or ($raw.Status -eq 'Error' -and $raw.ExitCode -eq 255)
            if ($check.Phase -eq 'Start') {
                $connectivityStarted = $status -eq 'Collected'
            }
            if ($status -eq 'Collected') {
                $health = 'ReviewRequired'
                if ($null -ne $raw.ExitCode -and $raw.ExitCode -ne 0) {
                    $reason = "ONTAP returned an explicit empty result but SSH exited $($raw.ExitCode); command completion requires review."
                }
                elseif ($check.Command -eq 'version -v') {
                    $buildTags = [regex]::Matches($raw.StdOut, '<(?<build>1O[^<>\r\n]*)>')
                    $noDareTags = @($buildTags | Where-Object { $_.Groups['build'].Value -ceq '1Ono-DARE' })
                    $otherTags = @($buildTags | Where-Object { $_.Groups['build'].Value -cne '1O' })
                    $hasWarnings = $raw.StdOut -match '(?im)^\s*(Warning:|Error:|Info:)'
                    if ($noDareTags.Count -gt 0) {
                        $encryptionBuild = 'NODAR'
                        $reason = 'NODAR / no-DARE build detected (<1Ono-DARE>). At least one reported build does not support ONTAP software data-at-rest encryption (NVE). This does not assess hardware encryption.'
                    }
                    elseif ($buildTags.Count -gt 0 -and $otherTags.Count -eq 0) {
                        $encryptionBuild = 'DAR'
                        if (-not $hasWarnings -and [string]::IsNullOrWhiteSpace($raw.StdErr)) {
                            $health = 'Successful'
                            $reason = 'DAR build detected (<1O>): the reported build supports data-at-rest encryption capability. Platform support, licensing, key management and actual encryption enablement are not assessed.'
                        }
                        else { $reason = 'DAR build marker detected, but warnings or stderr require review of the retained version output.' }
                    }
                    else {
                        $encryptionBuild = 'Unknown'
                        $reason = 'Unable to determine DAR/NODAR build capability: expected <1O> or <1Ono-DARE> markers were absent or unrecognized.'
                    }
                }
                elseif ($check.Phase -eq 'Results') {
                    $normalized = $raw.StdOut -replace '\r\n?', "`n"
                    $records = [regex]::Matches($normalized, '(?im)^[\t ]*Node:[\t ]*[^\r\n]+')
                    $lossValues = [regex]::Matches($normalized, '(?im)^[\t ]*Packet Loss:[\t ]*([^\r\n]+)')
                    $hasLoss = @($lossValues | Where-Object { $_.Groups[1].Value.Trim() -ine 'none' }).Count -gt 0
                    $hasWarnings = $normalized -match '(?im)^[\t ]*(Warning:|Error:|Info:|[^\r\n]*\bin progress\b|[^\r\n]*\bpending\b)'
                    if ($records.Count -gt 0 -and $records.Count -eq $lossValues.Count -and -not $hasLoss -and -not $hasWarnings -and [string]::IsNullOrWhiteSpace($raw.StdErr)) {
                        $health = 'Successful'
                        $reason = "All $($lossValues.Count) returned connectivity records report no packet loss. Raw output retained; run freshness and expected coverage are not automatically verified."
                    }
                    else {
                        $reason = 'Connectivity results contain loss, warnings, missing or incomplete records; review the retained output.'
                    }
                }
                elseif ($check.Command -in @('cluster ha show', 'network options switchless-cluster show')) {
                    $fieldName = if ($check.Command -eq 'cluster ha show') { 'High-Availability Configured' } else { 'Enable Switchless Cluster' }
                    $fieldMatch = [regex]::Match($raw.StdOut, '(?im)^\s*' + [regex]::Escape($fieldName) + ':\s*(?<value>true|false)\s*$')
                    if (-not $fieldMatch.Success -or -not [string]::IsNullOrWhiteSpace($raw.StdErr) -or $raw.StdOut -match '(?im)^\s*(Warning:|Error:|Info:)') {
                        $reason = "Could not reliably read '$fieldName' from the command response or the response contained warnings; review the retained output."
                        $assessmentOutcome = 'review'
                    }
                    elseif ($null -eq $inventory.NodeCount -or $inventory.NodeCount -lt 1) {
                        $reason = 'The node inventory did not provide a valid node count, so this setting cannot be assessed against cluster size.'
                        $assessmentOutcome = 'review'
                    }
                    elseif ($inventory.NodeCount -eq 1) {
                        $health = 'NotApplicable'
                        $reason = 'Not applicable: this cluster has one node; cluster HA and switchless cluster mode are assessed only for multi-node cluster layouts.'
                        $assessmentOutcome = 'info'
                    }
                    else {
                        $actualValue = $fieldMatch.Groups['value'].Value -ieq 'true'
                        if ($check.Command -eq 'cluster ha show') {
                            $expectedValue = $inventory.NodeCount -eq 2
                        }
                        elseif ($inventory.NodeCount -gt 2) {
                            $expectedValue = $false
                        }
                        elseif ($null -eq $inventory.ClusterSwitchCount) {
                            $expectedValue = $null
                        }
                        else {
                            $expectedValue = $inventory.ClusterSwitchCount -eq 0
                        }
                        if ($null -eq $expectedValue) {
                            $reason = 'Cluster-switch inventory could not be determined, so switchless mode cannot be compared with the reported topology.'
                            $assessmentOutcome = 'review'
                        }
                        elseif ($actualValue -eq $expectedValue) {
                            $health = 'NoFindings'
                            $assessmentOutcome = 'pass'
                            if ($check.Command -eq 'cluster ha show') {
                                $reason = if ($expectedValue) { 'Cluster HA configuration matches the captured node count. Cluster HA is enabled for this two-node cluster.' } else { "Cluster HA configuration matches the captured node count. Cluster HA is disabled for this $($inventory.NodeCount)-node cluster." }
                            }
                            else {
                                $topology = if ($inventory.ClusterSwitchCount -eq 0) { 'no reported cluster-network switches' } else { "$($inventory.ClusterSwitchCount) reported cluster-network switch(es)" }
                                $reason = "Switchless cluster configuration matches the captured node count and cluster-network switch inventory. Switchless mode matches the two-node topology ($topology)."
                            }
                        }
                        else {
                            $reason = "Finding: '$fieldName' is $($actualValue.ToString().ToLowerInvariant()), but the expected value for $($inventory.NodeCount) node(s) is $($expectedValue.ToString().ToLowerInvariant())."
                            $assessmentOutcome = 'findings'
                        }
                    }
                }
                elseif ($check.Phase -eq 'Check' -and (Test-OntapEmptyResponse -Output $raw.StdOut -AllowPartitionedDiskNote:($check.Command -match '^storage disk show(?:\s|$)')) -and [string]::IsNullOrWhiteSpace($raw.StdErr)) {
                    $health = 'NoFindings'
                    $reason = if ([string]::IsNullOrWhiteSpace($check.PassMessage)) { 'No entries matched the configured unhealthy-condition filters; a check-specific interpretation has not been supplied.' } else { $check.PassMessage }
                    if (-not (Test-OntapEmptyResponse -Output $raw.StdOut)) {
                        $reason += ' The partitioned-disk spare-capacity and storage-pool capacity notes are informational and retained in the output; this check does not assess either capacity.'
                    }
                }
                elseif ($check.Diagnostic) {
                    $reason = 'Diagnostic activity returned output; review completion and the retained response.'
                }
            }
        }
        $checks += [pscustomobject]@{
            Category = $check.Category
            Name = $check.Name
            Description = $check.Description
            DocumentationUrl = $check.DocumentationUrl
            InterpretationQuestion = $check.InterpretationQuestion
            Command = $check.Command
            MinimumVersion = $check.MinimumVersion.ToString()
            Diagnostic = $check.Diagnostic
            Status = $status
            Health = $health
            EncryptionBuild = $encryptionBuild
            AssessmentOutcome = $assessmentOutcome
            Reason = $reason
            StartedAt = $checkStartedAt
            FinishedAt = [datetimeoffset]::Now.ToString('o')
            ExitCode = if ($null -ne $raw) { $raw.ExitCode } else { $null }
            CommandSucceeded = if ($null -ne $raw) { $raw.Status -eq 'Collected' } else { $null }
            StdOut = if ($null -ne $raw) { $raw.StdOut } else { $null }
            StdErr = if ($null -ne $raw) { $raw.StdErr } else { $null }
        }
    }
    [pscustomobject]@{
        Target = $Target
        Port = $Port
        Version = $release.ToString()
        Release = $releaseLabel
        VersionOutput = $releaseLabel
        StartedAt = $startedAt
        FinishedAt = [datetimeoffset]::Now.ToString('o')
        IncludeDiagnostics = $true
        Inventory = $inventory
        SessionMode = 'Persistent'
        SessionExitCode = $null
        SessionError = $null
        SessionStartupStdOut = ''
        SessionStartupStdErr = ''
        Checks = $checks
    }
}

function Invoke-OntapHealthCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[a-zA-Z0-9:][a-zA-Z0-9.:%_-]*$')][string]$Target,
        [System.Management.Automation.PSCredential]$Credential,
        [ValidateRange(1, 65535)][int]$Port = 22,
        [string]$KnownHostsPath,
        [switch]$AcceptNewHostKey,
        [switch]$NonInteractive,
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 60,
        [string]$SshExecutable = 'ssh',
        [switch]$IncludeDiagnostics = $true
    )

    $collectorParameters = @{} + $PSBoundParameters
    $connection = @{} + $PSBoundParameters
    $null = $connection.Remove('IncludeDiagnostics')
    Invoke-OntapSshCommand @connection -SessionBody {
        param($sessionState)
        Invoke-OntapHealthCheckCollection @collectorParameters -Session $sessionState
    }
}

Export-ModuleMember -Function Test-OntapSshConnection, Get-OntapHealthCheckCommand, Invoke-OntapHealthCheck