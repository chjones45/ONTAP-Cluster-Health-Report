#Requires -Version 5.1
#Requires -PSEdition Desktop
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\Modules\ONTAP.HealthCheck.psm1') -Force
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('ontap-ssh-tests-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($testDirectory)
$originalMode = $env:ONTAP_SSH_TEST_MODE
$originalBlob = $env:ONTAP_SSH_ASKPASS_BLOB
$originalHelper = $env:SSH_ASKPASS
$originalRequire = $env:SSH_ASKPASS_REQUIRE

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

try {
    $executable = Join-Path $testDirectory 'fake ssh.exe'
    Add-Type -OutputAssembly $executable -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
public static class OntapSshTestClient {
    public static int Main(string[] args) {
        string mode = Environment.GetEnvironmentVariable("ONTAP_SSH_TEST_MODE");
        if (mode == "timeout") { Thread.Sleep(10000); return 0; }
        if (mode == "reject") { Console.Error.Write("Host key verification failed."); return 255; }
        if (mode == "clierror") { Console.Write("Error: command failed: not authorized"); return 0; }
        if (mode == "empty") { return 0; }
        string policy = mode == "accept" ? "accept-new" : "yes";
        string knownHosts = "UserKnownHostsFile=\"" + Environment.GetEnvironmentVariable("ONTAP_SSH_TEST_KNOWN_HOSTS").Replace('\\', '/') + "\"";
        string[] expected = {
            "-F", "NUL", "-T", "-p", "2222", "-o", "StrictHostKeyChecking=" + policy,
            "-o", knownHosts, "-o", "GlobalKnownHostsFile=NUL",
            "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2",
            "-o", "NumberOfPasswordPrompts=1", "-o", "PreferredAuthentications=keyboard-interactive,password",
            "-o", "PubkeyAuthentication=no", "-o", "PasswordAuthentication=yes",
            "-o", "KbdInteractiveAuthentication=yes", "-o", "BatchMode=no",
            "-o", "ForwardAgent=no", "-o", "ClearAllForwardings=yes",
            "-l", "domain\\user with \"quotes\"\\", "::1"
        };
        if ((args.Length != expected.Length + 1 && args.Length != expected.Length) || !args.Take(expected.Length).SequenceEqual(expected)) {
            Console.Error.Write("Argument round-trip or SSH security options failed."); return 90;
        }
        bool shell = args.Length == expected.Length;
        string command = shell ? null : args[args.Length - 1];
        if (!shell && mode.StartsWith("collector") && command != "version") {
            string prefix = "set -privilege advanced -confirmations off; set -rows 0; ";
            if (!command.StartsWith(prefix)) {
                Console.Error.Write("Collector privilege or pagination failed."); return 94;
            }
            if (mode == "collector-clierror") { Console.Write("Error: command failed: not authorized\r\n"); }
            if (mode == "collector-warning") { Console.Write("Warning: partial response\r\n"); }
            if (mode == "collector-stderr") { Console.Error.Write("Connection closed unexpectedly."); }
            string newline = mode == "collector-empty255-crcrlf" ? "\r\r\n" : "\r\n";
            Console.Write(newline + "Last login time: 10/26/2026 17:28:28" + newline + newline + "There are no entries matching your query." + newline);
            if (mode.StartsWith("collector-partitioned") && command.Contains("storage disk show ")) {
                Console.Write("\a\r\nInfo: This cluster has partitioned disks. To get a complete list of spare disk\r\n      capacity use \"storage aggregate show-spare-disks\".\r\n\r\n");
            }
            return mode == "collector" || mode == "collector-partitioned0" ? 0 : 255;
        }
        if (!shell && command != "version" && command != "cluster show") { return 91; }
        string helper = Environment.GetEnvironmentVariable("SSH_ASKPASS");
        if (Environment.GetEnvironmentVariable("SSH_ASKPASS_REQUIRE") != "force" ||
            File.ReadAllText(helper).Contains("test password")) { return 92; }
        var info = new ProcessStartInfo(Environment.GetEnvironmentVariable("COMSPEC"), "/d /c \"\"" + helper + "\"\"");
        info.UseShellExecute = false;
        info.CreateNoWindow = true;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        using (var process = Process.Start(info)) {
            string password = process.StandardOutput.ReadToEnd();
            string error = process.StandardError.ReadToEnd();
            process.WaitForExit();
            if (process.ExitCode != 0 || password != "test password & % ! \" \\ end" || error.Length != 0) {
                Console.Error.Write("Askpass round-trip failed."); return 93;
            }
        }
        if (shell) {
            string log = Environment.GetEnvironmentVariable("ONTAP_SSH_TEST_SESSION_LOG");
            File.AppendAllText(log, "SESSION\n");
            Console.Write("Last login time: 10/27/2026 09:00:00\r\n");
            if (mode == "collector-banner") Console.Error.Write("WARNING: Unauthorised access to this system is forbidden.\r\n");
            Console.Write("cluster::> ");
            Console.Out.Flush();
            bool advanced = false;
            while ((command = Console.ReadLine()) != null) {
                File.AppendAllText(log, command + "\n");
                if (command == "exit") { return mode == "collector-exitfail" ? 255 : 0; }
                Console.Write(command + "\r\n");
                if (command == "version") { Console.Write("NetApp Release 9.16.1P12\r\n"); }
                else if (command == "set -privilege advanced -confirmations off") {
                    if (mode == "collector-setupfail") { Console.Write("Error: not authorized\r\n"); }
                    else { advanced = true; }
                }
                else if (command == "set -rows 0") { }
                else {
                    if (!advanced) { return 95; }
                    if (command == "storage errors show" && mode == "collector-disconnect") { Console.Write("Partial response before disconnect\r\n"); return 255; }
                    if (command == "storage errors show" && mode == "collector-commandtimeout") { Console.Write("Partial response before timeout\r\n"); Console.Out.Flush(); Thread.Sleep(10000); return 0; }
                    if (mode == "collector-clierror") { Console.Write("Error: command failed: not authorized\r\n"); }
                    else if (command == "cluster identity show") { Console.Write("Cluster UUID:\r\n12345678-1234-1234-1234-123456789abc\r\nCluster Name: test-cluster\r\n"); }
                    else if (command == "system node show -fields node") { Console.Write("Node\r\n----------\r\nnode1\r\nnode2\r\n2 entries were displayed.\r\n"); }
                    else if (command == "system node show -fields model") { Console.Write("node model\r\n---- -----\r\nnode1 AFF-A250\r\nnode2 AFF-A250\r\n2 entries were displayed.\r\n"); }
                    else if (command == "system switch ethernet show -type cluster-network") { Console.Write("There are no entries matching your query.\r\n"); }
                    else if (command == "storage aggregate show-spare-disks") { Console.Write("Original Owner: node1\r\nPool0 Spare Pool\r\n1.0.10 SSD solid-state 894GB 894GB zeroed\r\n"); }
                    else if (command == "cluster ha show") { Console.Write("High-Availability Configured: true\r\n"); }
                    else if (command == "network options switchless-cluster show") { Console.Write("Enable Switchless Cluster: true\r\n"); }
                    else if (command == "version -v") { Console.Write("NetApp Release 9.16.1P12: <1O>\r\n"); }
                    else if (command.Contains("cluster-connectivity start")) { Console.Write("2 entries were acted on.\r\n"); }
                    else if (command.Contains("cluster-connectivity show")) { Console.Write("Node: node1\r\nPacket Loss: none\r\nNode: node2\r\nPacket Loss: none\r\n"); }
                    else {
                        Console.Write("There are no entries matching your query.\r\n");
                        if (mode == "collector-long" && command == "storage errors show") {
                            Console.Write(new string('x', 12000) + "\r\nother-cluster::> not the session prompt\r\n");
                        }
                        if (command.Contains("storage disk show ")) { Console.Write("\a\r\nInfo: This cluster has partitioned disks. To get a complete list of spare disk\r\n      capacity use \"storage aggregate show-spare-disks\".\r\n"); }
                    }
                }
                Console.Write(advanced ? "cluster::*> \r\ncluster::*> " : "cluster::> \r\ncluster::> ");
                Console.Out.Flush();
            }
            return 0;
        }
        Console.Write(command == "version" ? "NetApp Release 9.16.1" : "node1 true true");
        return 0;
    }
}
'@
    $knownHostsPath = Join-Path $testDirectory 'known hosts'
    $env:ONTAP_SSH_TEST_KNOWN_HOSTS = $knownHostsPath
    $parameters = @{
        Target = '::1'
        Port = 2222
        KnownHostsPath = $knownHostsPath
        Credential = New-Object System.Management.Automation.PSCredential('domain\user with "quotes"\', (ConvertTo-SecureString 'test password & % ! " \ end' -AsPlainText -Force))
        NonInteractive = $true
        SshExecutable = $executable
        TimeoutSeconds = 15
    }
    $helpersBefore = @(Get-ChildItem ([IO.Path]::GetTempPath()) -Directory -Filter 'ontap-ssh-*' | Select-Object -ExpandProperty FullName)
    foreach ($mode in @('success', 'accept', 'reject', 'clierror', 'empty', 'timeout')) {
        $env:ONTAP_SSH_TEST_MODE = $mode
        $parameters.TimeoutSeconds = if ($mode -eq 'timeout') { 1 } else { 15 }
        $failure = $null
        try {
            $results = @(Test-OntapSshConnection @parameters -AcceptNewHostKey:($mode -eq 'accept') -WarningAction SilentlyContinue)
        }
        catch { $failure = $_.Exception.Message }
        if ($mode -in @('success', 'accept')) {
            Assert-Condition ($null -eq $failure) "Success case failed: $failure"
            Assert-Condition ($results.Count -eq 2) 'Expected one result for each read-only command.'
            Assert-Condition ($results[0].StdOut -eq 'NetApp Release 9.16.1') 'Version output not preserved.'
            Assert-Condition ($results[1].Command -eq 'cluster show') 'Cluster command not preserved.'
        }
        else {
            $expectedError = switch ($mode) {
                'reject' { 'exit 255.*Host key verification failed' }
                'clierror' { 'not authorized' }
                'empty' { 'did not return a successful response' }
                'timeout' { 'exceeded 1 seconds' }
            }
            Assert-Condition ($null -ne $failure -and $failure -match $expectedError) "Wrong failure for ${mode}: $failure"
        }
        $newHelpers = @(Get-ChildItem ([IO.Path]::GetTempPath()) -Directory -Filter 'ontap-ssh-*' | Where-Object { $_.FullName -notin $helpersBefore })
        Assert-Condition ($newHelpers.Count -eq 0) "Helper leaked in mode $mode."
        Assert-Condition ($env:ONTAP_SSH_ASKPASS_BLOB -eq $originalBlob -and $env:SSH_ASKPASS -eq $originalHelper -and $env:SSH_ASKPASS_REQUIRE -eq $originalRequire) 'Parent SSH environment was changed.'
        Write-Host "PASS: $mode"
    }
    $env:ONTAP_SSH_TEST_MODE = 'collector'
    $env:ONTAP_SSH_TEST_SESSION_LOG = Join-Path $testDirectory 'session.log'
    $parameters.TimeoutSeconds = 15
    $catalog = @(Get-OntapHealthCheckCommand)
    $supportedCatalog = @($catalog | Where-Object { $_.MinimumVersion -le [version]'9.16.1' })
    $topologyCommands = @('cluster ha show', 'network options switchless-cluster show')
    $expectedEmptyQueries = @($supportedCatalog | Where-Object { $_.Phase -eq 'Check' -and $_.Command -ne 'version -v' -and $_.Command -notin $topologyCommands }).Count
    $expectedStarts = @($supportedCatalog | Where-Object Phase -eq 'Start').Count
    $expectedResults = @($supportedCatalog | Where-Object Phase -eq 'Results').Count
    $report = Invoke-OntapHealthCheck @parameters
    $collected = @($report.Checks | Where-Object Status -eq 'Collected')
    Assert-Condition ($report.Checks.Count -eq $catalog.Count) 'Report does not contain one entry per catalog command.'
    Assert-Condition ($collected.Count -eq $supportedCatalog.Count) 'Collector did not execute all supported checks.'
    Assert-Condition (@($collected | Where-Object Health -eq 'NoFindings').Count -eq ($expectedEmptyQueries + 2)) 'Explicit empty tables and matching topology assessments were not classified correctly.'
    Assert-Condition (@($collected | Where-Object { $_.Diagnostic -and $_.Health -eq 'ReviewRequired' }).Count -eq $expectedStarts) 'Only diagnostic start activity should require review.'
    Assert-Condition (@($collected | Where-Object { $_.StdOut -match '(?m)^cluster::\*?>' }).Count -eq 0) 'Repeated session prompts leaked into command output.'
    $diskCheck = $collected | Where-Object Command -like 'storage disk show *'
    Assert-Condition ($diskCheck.StdOut -match 'Info: This cluster has partitioned disks' -and $diskCheck.Health -eq 'NoFindings') 'Informational disk note was discarded or incorrectly flagged.'
    Assert-Condition ($collected[-1].Health -eq 'Successful') 'Connectivity results did not use the final command response.'
    Assert-Condition (@($collected | Where-Object { $null -ne $_.ExitCode }).Count -eq 0) 'Persistent shell invented per-command exit codes.'
    Assert-Condition (@($report.Checks | Where-Object Status -eq 'Skipped').Count -eq ($catalog.Count - $supportedCatalog.Count)) 'Default collection skipped the wrong number of checks.'
    $sessionLog = @(Get-Content -LiteralPath $env:ONTAP_SSH_TEST_SESSION_LOG)
    $executedChecks = @($sessionLog | Where-Object { $_ -notin @('SESSION', 'version', 'set -privilege advanced -confirmations off', 'set -rows 0', 'exit') })
    $expectedCommands = @('cluster identity show', 'system node show -fields node', 'system node show -fields model', 'system switch ethernet show -type cluster-network', 'storage aggregate show-spare-disks') + @(foreach ($phase in @('Start', 'Check', 'Results')) {
        $supportedCatalog | Where-Object Phase -eq $phase | Select-Object -ExpandProperty Command
    })
    Assert-Condition (($executedChecks -join "`n") -ceq ($expectedCommands -join "`n")) 'Supported catalog commands were omitted, duplicated or executed out of order.'
    Assert-Condition (@($sessionLog | Where-Object { $_ -eq 'SESSION' }).Count -eq 1) 'Collector opened more than one SSH process.'
    Assert-Condition (@($sessionLog | Where-Object { $_ -eq 'set -privilege advanced -confirmations off' }).Count -eq 1) 'Privilege setup was repeated.'
    Assert-Condition ($sessionLog[-1] -eq 'exit') 'SSH session was not exited.'
    Assert-Condition ($report.SessionMode -eq 'Persistent' -and $report.SessionExitCode -eq 0 -and $null -eq $report.SessionError) 'Session transport metadata was not retained.'
    Write-Host 'PASS: one authenticated session, one setup, separate command results and graceful exit'
    $env:ONTAP_SSH_TEST_MODE = 'collector-banner'
    $report = Invoke-OntapHealthCheck @parameters
    Assert-Condition (@($report.Checks | Where-Object Status -eq 'Collected').Count -eq $supportedCatalog.Count -and $report.SessionExitCode -eq 0 -and $null -eq $report.SessionError) 'A legal notice on startup stderr prevented a prompt-established session from completing.'
    Assert-Condition ($report.SessionStartupStdErr -match 'Unauthorised access') 'SSH startup banner stderr was not retained in the report.'
    Write-Host 'PASS: startup legal notice retained without failing an established SSH session'
    $env:ONTAP_SSH_TEST_MODE = 'collector'
    foreach ($mode in @('collector-long', 'collector-exitfail')) {
        $env:ONTAP_SSH_TEST_MODE = $mode
        $report = Invoke-OntapHealthCheck @parameters
        Assert-Condition (@($report.Checks | Where-Object Status -eq 'Collected').Count -eq $supportedCatalog.Count) 'Framing or shutdown lost completed command results.'
        if ($mode -eq 'collector-long') {
            $longCheck = $report.Checks | Where-Object Command -eq 'storage errors show'
            $nextCheck = $report.Checks | Where-Object Command -eq 'storage failover show -enabled false'
            Assert-Condition ($longCheck.StdOut.Length -gt 12000 -and $nextCheck.StdOut -notmatch 'xxxx') 'Large or prompt-like output crossed command boundaries.'
        }
        else {
            Assert-Condition ($report.SessionExitCode -eq 255 -and $report.SessionError -match 'exited with code') 'Shutdown failure was hidden.'
        }
        Write-Host "PASS: $mode"
    }
    foreach ($mode in @('collector-clierror', 'collector-setupfail', 'collector-disconnect', 'collector-commandtimeout')) {
        $env:ONTAP_SSH_TEST_MODE = $mode
        $parameters.TimeoutSeconds = if ($mode -eq 'collector-commandtimeout') { 5 } else { 15 }
        $report = Invoke-OntapHealthCheck @parameters
        $executed = @($report.Checks | Where-Object Status -ne 'Skipped')
        if ($mode -eq 'collector-clierror') {
            $expectedErrors = $supportedCatalog.Count - $expectedResults
            Assert-Condition ($executed.Count -eq $expectedErrors -and @($executed | Where-Object Status -eq 'Error').Count -eq $expectedErrors) 'CLI errors did not remain independent of transport failure.'
        }
        elseif ($mode -eq 'collector-setupfail') {
            Assert-Condition ($executed.Count -eq 0 -and @($report.Checks | Where-Object Status -eq 'Skipped').Count -eq $supportedCatalog.Count) 'Failed inventory setup did not stop subsequent collection cleanly.'
            Assert-Condition ($report.SessionError -match 'before all commands completed') 'Failed inventory setup was not retained as a session error.'
        }
        else {
            Assert-Condition ($executed[-1].Status -eq 'Error' -and $executed[-1].Health -eq 'Unknown') "Fatal session failure not recorded: $mode"
            Assert-Condition (@($report.Checks | Where-Object Status -eq 'Skipped').Count -gt 0) "Commands continued after session failure: $mode"
            if ($mode -in @('collector-disconnect', 'collector-commandtimeout')) {
                Assert-Condition ($executed[-1].StdOut -match 'Partial response before') 'Partial output was lost on session failure.'
            }
        }
        $newHelpers = @(Get-ChildItem ([IO.Path]::GetTempPath()) -Directory -Filter 'ontap-ssh-*' | Where-Object { $_.FullName -notin $helpersBefore })
        Assert-Condition ($newHelpers.Count -eq 0) "Session helper leaked in $mode."
        Write-Host "PASS: $mode"
    }
    $null = $parameters.Remove('Credential')
    try {
        $null = Test-OntapSshConnection @parameters
        throw 'Expected missing-credential failure.'
    }
    catch {
        Assert-Condition ($_.Exception.Message -match 'Specify -Credential') 'Noninteractive mode did not reject missing credentials.'
    }
    Write-Host 'PASS: noninteractive credentials required'
}
finally {
    $env:ONTAP_SSH_TEST_MODE = $originalMode
    Remove-Item Env:\ONTAP_SSH_TEST_SESSION_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:\ONTAP_SSH_TEST_KNOWN_HOSTS -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
}