# ONTAP Health Check

[Quick start and report preview](README.md)

## Contents

- [Project details](#project-details)
- [Description](#description)
- [Repository layout](#repository-layout)
- [Quick start, multiple clusters, and reports](#quick-start)
- [Requirements](#requirements)
- [Establish host trust](#establish-host-trust)
- [Test the connection](#test-the-connection)
- [Security and reuse](#security-and-reuse)
- [Collect health checks and interpret results](#collect-health-checks)
- [Local regression test](#local-regression-test)
- [Public samples and publishing](#public-samples-and-publishing)
- [License](#license)

## Project Details

| Field | Value |
|---|---|
| Version | Unreleased |
| Last Updated | 2026-10-28 |
| Language | Windows PowerShell 5.1 / PowerShell 7 |
| Platform | Windows |

## Description

The module provides a secure SSH connection test and a catalog-based, non-remediating health-check collector for ONTAP 9. `Test-OntapSshConnection` runs `version` and `cluster show` using separate SSH connections. `Invoke-OntapHealthCheck` includes all current catalog entries by default, including diagnostics, subject to release support and execution failures, using one retained SSH session per cluster. No remediation or persistent configuration changes are performed.

## Repository Layout

Collection and production HTML generation require these six files, keeping their relative layout:

```text
ONTAPHealthCheck.ps1
Modules/
	ONTAP.HealthCheck.psm1
	ONTAP.CheckDescriptions.psd1
ReportAssets/
	New-OntapHealthReport.ps1
	ONTAP_Health_Report.template.html
	NA_logo_violet_white_rgb.png
```

The collector module was renamed from `ONTAP.Ssh.psm1` to `ONTAP.HealthCheck.psm1` because it owns the health-check catalog, assessments, and SSH transport. The root script imports it automatically. Direct module users should use the current filename and module qualifier. The remaining `ONTAP.Ssh.psm1` is an older implementation, is not kept in sync, and is not loaded by the runner or regression tests. The runtime template and selected logo are under `ReportAssets`. Public samples under `samples` use synthetic data only and are not runtime dependencies.

Keep the three scripts under `Tests` for regression coverage; they use the runtime files above and do not require samples or saved report collections. `.gitignore` and this README are repository support files, not runtime dependencies.

The `Reports` directory is generated output, not application code. It may be removed if its saved assessments are no longer needed and is recreated on the next collection. Removing it destroys those saved reports; move or archive any reports you want to keep. The production scripts and tests do not depend on sample files.

## Quick Start

After verifying each cluster's SSH host key as described below, run the root script. No manual module import is required:

```powershell
.\ONTAPHealthCheck.ps1 cluster1
```

It prompts for credentials, runs all supported health checks (including diagnostics), displays a per-cluster collection summary, and saves reports. For multiple clusters, interactive execution asks whether the same username and password should be used for all targets. Each invocation reloads the local module so updates are used even in an existing PowerShell session. Running it without arguments prompts for cluster names or addresses first:

```powershell
.\ONTAPHealthCheck.ps1
```

During each cluster's collection, the console announces connectivity start, then `Performing Checks: General`, `Security`, `Storage`, `Network`, and `Data` once each as their first check executes, followed by connectivity result collection. Skipped phases are not announced as running. These progress messages are separate from returned report objects and saved CLI output.

### Multiple Clusters

Hostnames, FQDNs, IPv4, and bare IPv6 addresses are supported. Any of these forms works from PowerShell:

```powershell
.\ONTAPHealthCheck.ps1 cluster1 cluster2 192.0.2.10
.\ONTAPHealthCheck.ps1 -Clusters cluster1 cluster2
.\ONTAPHealthCheck.ps1 -Clusters cluster1,cluster2
.\ONTAPHealthCheck.ps1 -Clusters 'cluster1, cluster2 192.0.2.10'
.\ONTAPHealthCheck.ps1 -ClusterFile .\clusters.txt
```

The text file can use one target per line, commas, spaces, tabs, or any mixture:

```text
cluster1
cluster2.example.com, 192.0.2.10
cluster3 cluster4.example.com
2001:db8::10
```

File and direct inputs can be combined. Blank entries are ignored, duplicates are removed case-insensitively, and the first occurrence determines execution order. Invalid targets are rejected before any connection is made. Do not include URLs, `user@host`, bracketed IPv6, or `host:port`; use `-Port` for a nondefault port.

Clusters run sequentially using the selected credentials and shared SSH options. For interactive runs without `-Credential`, multiple targets produce `Use the same username and password for all clusters? [Y/n]`. Y (or Enter) prompts once with a message that the credentials apply to all listed clusters. N prompts before each cluster, naming the exact hostname, FQDN, or IP address supplied as input. A single target prompts once for that target without a reuse question. Invalid Y/N input is retried. Cancelling credential entry stops the run; existing completed reports remain on disk. Per-cluster credentials are released from the connection parameters after their cluster finishes and are never saved in reports. Supplying `-Credential` explicitly reuses that credential for all targets without prompting. A failed cluster is recorded and does not prevent collection from the remaining clusters. `TimeoutSeconds` is per command, not per cluster.

### Reports

After all requested clusters have been processed, the root script automatically generates one self-contained `ONTAP-Health-Report.html` in the run directory. Per-cluster JSON files are written temporarily and used as the HTML generator's input. Once HTML generation finishes successfully and the report file is nonempty, those JSON files are removed by default. No summary CSV is created. The HTML includes every cluster attempted during that run, including failed and partial collections, and never includes illustrative clusters. The console prints the HTML path when generation completes. The file embeds the NetApp logo, styling, scripts, and result data; it can be opened locally or moved by itself without a server or internet connection.

Use `-OpenReport` to open the generated HTML in the system's default application after successful generation. It is opt-in and does not launch anything by default. If no HTML file association is available (for example, in a headless or scheduled session), the runner warns and prints the path; this does not change collection status, invalidate the report, or alter JSON cleanup.

Dashboard totals for all health checks, passes, findings, needs review, and collection errors are clickable. Each opens the matching `All checks` view for the currently selected cluster or all clusters. Category and search filters are cleared so the displayed results match the clicked total; the cluster selection is retained. `All health checks`, in both the dashboard and results filter, counts/shows completed checks with `Status = Collected`, not errored or skipped checks. Cluster-level errors remain visible when clicking collection errors even if no individual checks were collected. Selected-cluster count is informational and is not clickable. The controls support keyboard activation and expose descriptive tooltips.

`Results Explained`, aligned right below the dashboard, opens a compact explanation of Passed (green), Findings (yellow), Needs review (violet), Collection error (red), Skipped, and Information. It opens on mouse hover or keyboard focus; click or tap pins it open. It can be dismissed with its close button, Escape, or an outside click. The same scrollable popup works on mobile without navigating away or requiring internet access. It distinguishes a returned condition from uncertain evidence and from a check that could not complete, and notes that collection completeness is not an overall health verdict.

The `Results` section groups evidence by cluster, then collapsible category, then expandable individual check. Expand all and Collapse all controls appear above the first cluster and below the last cluster; they toggle every cluster, category, and individual check currently shown in Results. Cluster and category badges use worst-recorded severity in this order: collection error (red), needs review (violet), findings (yellow), passed (green). Skipped checks make the rollup require review; information-only groups remain neutral blue. Rollups use the full recorded cluster/category, not only currently visible checks, so filtering to passes cannot hide a known issue behind a green category badge. Each heading states how many checks are shown out of its total, and the badge tooltip explains its scope. Evidence links expand the containing cluster and category automatically.

`Export filtered results` is the primary CSV action. It exports one row per check matching the selected clusters, result types, categories, and search, regardless of which sections are expanded. Rows include the target, source/illustrative-data label, category, check name, command, displayed result, assessment, collection status, stored health, timestamps, stdout, and stderr. Matching cluster-level collection errors are included as separate `Collection error` rows even if no checks were collected. No matches produces a header-only CSV.

`Export cluster summary` separately exports all-check totals for the selected clusters. Result, category, and search filters do not narrow those summary totals; its tooltip explains this scope. Both exports are UTF-8 CSV with quoted fields supporting commas, quotation marks, and multiline output. Spreadsheet formula-like values are prefixed with an apostrophe in the CSV; the source JSON and browser evidence remain unchanged. Production downloads are named `ontap-health-filtered-results.csv` and `ontap-health-summary.csv`, with a `preview` qualifier for design previews.

Clusters, results, and categories have checkbox multi-select menus. Select any number of choices, use each menu's `All` checkbox to select all or clear all, and combine menus freely. Choices within a menu are OR conditions; the different menus and free-text search are combined with AND. An empty selection shows no matching results rather than silently reverting to all. `Clear filters` resets every menu and search. Keyboard users can toggle checkboxes normally and use Escape to close a filter menu. Dashboard drill-downs retain any selected subset of clusters.

```text
Reports/<local-run-timestamp>/
	ONTAP-Health-Report.html
```

Use `-KeepAllOutputFiles` (equivalent to `-KeepAllOutputFiles:$true`) to retain the per-cluster JSON alongside HTML. The default is false; `-KeepAllOutputFiles:$false` explicitly selects HTML-only output. This switch does not restore CSV generation. The console summary, in-memory `-PassThru` results, and browser-generated CSV downloads remain available and unchanged.

```powershell
.\ONTAPHealthCheck.ps1 cluster1 cluster2 -KeepAllOutputFiles
```

If HTML rendering fails, returns without a report, or creates an empty report, JSON is always retained regardless of the switch and a warning explains how to recover. Cancellation or an interrupted collection also leaves any JSON already written. Cleanup removes only JSON paths created by the current run; it does not retroactively delete existing report folders or unrelated files. A cleanup failure issues a warning without discarding the HTML report.

You can regenerate HTML from retained JSON without credentials or another collection. This requires having used `-KeepAllOutputFiles` or JSON retained after a failure:

```powershell
$runFolder = '.\Reports\<run-folder-with-retained-json>'
$jsonPaths = @(Get-ChildItem -LiteralPath $runFolder -Filter '*.json' -File | Select-Object -ExpandProperty FullName)
& (Join-Path $PSScriptRoot 'ReportAssets/New-OntapHealthReport.ps1') -ReportPath $jsonPaths -OutputPath (Join-Path $runFolder 'ONTAP-Health-Report.html')
```

The report generator under `ReportAssets` also accepts JSON paths from multiple directories. It refuses to overwrite an input JSON file. The generator, check descriptions under `Modules`, and shared template/logo under `ReportAssets` are required while building the report, but the finished HTML has no dependency on those files. The HTML separates evidence into passes, findings, review items, information, errors, and skips without changing the source JSON's health values; collection completeness is not an overall health verdict.

Each invocation creates a unique directory under `Reports` beside the script, named using the runner system's local time. Successful rendering leaves HTML only by default, or HTML and one numbered JSON file per cluster when retention is enabled. The console summary still shows `TotalHealthChecks`, `Passed`, `ReviewRequired`, `Errors`, and `Skipped`; its counts are calculated in memory without writing a CSV. `TotalHealthChecks` counts completed checks. Per-check JSON and the HTML's embedded data still use `Status = Collected`. `Passed` combines completed checks with `Health = NoFindings` or `Health = Successful`; it is not limited to connectivity checks. Both browser CSV exports are generated on the fly from embedded HTML data and do not require the deleted JSON files or any disk CSV. The root `.gitignore` excludes `Reports/`. Reports contain sensitive infrastructure data; their filesystem permissions inherit from the parent directory. Use a suitably protected location, particularly if the repository is inside a synced folder.

Use `-OutputDirectory` to select a new directory. Existing directories are rejected to prevent overwriting earlier reports. `CollectionStatus = Complete` means no checks errored or were skipped, not that the cluster is healthy; `Partial` means some checks errored or were skipped; `Failed` means the collector threw a terminating error, recorded in the report. Review `ReviewRequired`, `Unknown`, and raw responses before drawing health conclusions.

For unattended use or to reuse an in-memory credential:

```powershell
$credential = Get-Credential
$results = .\ONTAPHealthCheck.ps1 -Clusters 'cluster1,cluster2' -Credential $credential -NonInteractive -OutputDirectory 'C:\SecureReports\run-001' -PassThru
$results | Select-Object Target, CollectionStatus, Error
$results[0].Report.Checks | Format-List Command, Status, Health, Reason, StdOut, StdErr
```

`-NonInteractive` requires supplied targets and credentials; it never prompts for them. `-PassThru` additionally returns one structured result per cluster. The script also accepts `-KnownHostsPath`, `-Port`, `-TimeoutSeconds`, `-SshExecutable`, and the explicit trust-on-first-use switch `-AcceptNewHostKey`; verified host keys remain the default requirement. Credentials are not included in saved reports.

The root script runs live cluster health checks, not the offline developer regression tests listed at the end of this README.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7 on Windows.
- Windows OpenSSH Client with `SSH_ASKPASS_REQUIRE=force` support (OpenSSH 8.4+).
- Cluster-management SSH access and an ONTAP account authorized for the requested commands, using password or single-password keyboard-interactive authentication. The collector additionally requires advanced CLI privilege and the relevant command permissions. Multi-step MFA is not supported by this helper.
- A verified cluster host key in your Windows user's `.ssh\known_hosts`, or a dedicated file supplied using `-KnownHostsPath`.

## Establish Host Trust

Strict host-key validation is the default. For a new cluster, obtain its SSH host-key fingerprint independently from a trusted administrator or management channel. Then connect manually and compare the displayed fingerprint before accepting it:

```powershell
ssh -F NUL -o StrictHostKeyChecking=ask -l admin cluster-mgmt.example.com
```

Use `-p 2222` for a nondefault SSH port. Do not accept a fingerprint you cannot verify. A key obtained using `ssh-keyscan` alone does not establish authenticity.

The test deliberately ignores user/system SSH configuration and global known-hosts files. Use `-KnownHostsPath` if your verified key is stored outside the user's default file. A changed host key is rejected; verify a legitimate key rotation independently before updating the entry. Do not delete an entry just to bypass a warning.

## Test the Connection

Run from the repository directory. Supply a bare DNS name or IP address, not a URL, user name, or host/port pair. Use bare IPv6 addresses without brackets.

```powershell
Import-Module .\Modules\ONTAP.HealthCheck.psm1 -Force
$credential = Get-Credential -Message 'ONTAP SSH credentials'
$results = Test-OntapSshConnection -Target cluster-mgmt.example.com -Credential $credential
$results | Format-List Command, ExitCode, StdOut, StdErr
```

For unattended execution, supply `-Credential -NonInteractive`. No password-string parameter is supported. Credentials are not written to reports or command-line arguments. Treat returned CLI output as potentially sensitive infrastructure data.

An explicit trust-on-first-use option is available when the environment's security policy permits it:

```powershell
Test-OntapSshConnection -Target cluster-mgmt.example.com -Credential $credential -AcceptNewHostKey
```

`-AcceptNewHostKey` stores previously unknown keys and still rejects changed keys. It cannot authenticate a first connection against a man-in-the-middle attack; preverified keys are preferred. The policy applies to each of the two connections.

Other options: `-Port`, `-KnownHostsPath`, `-TimeoutSeconds` (per command, default 60), `-SshExecutable`, and `-Verbose`. SSH connection establishment has an additional 15-second limit. Failures throw terminating errors; successful authentication alone does not prove either command was authorized.

## Security and Reuse

Adapted from the working `Invoke-SgNetworkPortReport.ps1` in the sibling StorageGRID network-port report repository: Windows argument quoting, redirected asynchronous output capture, and a temporary `SSH_ASKPASS` helper. The helper contains no password. A Windows DPAPI-protected credential blob is supplied only in the child process environment and decrypted by the helper under the current Windows identity. The helper directory is removed on success, failure, and timeout; abruptly terminating PowerShell can prevent cleanup. This protects credentials at rest, not against a compromised account, administrator, or process memory inspection. OpenSSH necessarily receives the decrypted password for authentication.

Unlike the StorageGRID collector, this module does not use sudo, Bash, root access, password data on stdin, or automatic first-use trust by default. It does not weaken SSH algorithms or disable host-key checks.

## Collect Health Checks

The health-check catalog includes additional checks grouped into General, Security, Storage, Network, and Data. Inspect it without contacting a cluster:

```powershell
Get-OntapHealthCheckCommand | Format-Table Category, MinimumVersion, Diagnostic, Command -Wrap
```

The current total can be calculated without contacting a cluster:

```powershell
@(Get-OntapHealthCheckCommand).Count
```

Regression tests derive expected totals, supported-release counts, diagnostics, and pass counts from this live catalog. Adding normal query rows to `$definitions` does not require changing fixed totals in the tests. Tests still check completeness, duplicate commands, ordering, classification, and failures; checks that need new parsing or execution behavior may require additional test cases.

### Check Descriptions and Assessments

Check-specific guidance is maintained in [Modules/ONTAP.CheckDescriptions.psd1](Modules/ONTAP.CheckDescriptions.psd1), keyed by the exact CLI command including its filters. It supplies a display name, a description of what the check tests, the meaning of an empty successful query, and selected documentation links or interpretation questions. New checks should receive a matching entry; metadata-coverage tests identify missing descriptions and query pass messages. Check totals remain dynamic.

For example, `storage failover show -possible false` reports that no nodes returned takeover possible=false and explicitly states that a takeover was not exercised. LIF checks describe the home-port or operational-state condition, interface-group checks distinguish singlemode from non-singlemode participation, and volume/SVM checks state the excluded states or subtypes. Empty results do not prove a feature is configured, every expected object was queried, or an active end-to-end test succeeded.

New JSON reports retain `Description`, `DocumentationUrl`, and `InterpretationQuestion` along with their check-specific `Reason`. HTML reports embed the same guidance offline. When regenerating an older report, the renderer enriches only generic `NoFindings` assessment text and displays the original saved assessment separately; the source JSON, raw output, health classifications, warnings, and diagnostic caveats are not changed. Each expanded check includes a `What is checked` field. Interpretation questions are visible as `Needs clarification`.

The single-link HA interconnect check uses the confirmed command `system ha interconnect status show -link-status !"-",!up`: one comma-separated exclusion list selects statuses other than dash and up. Its pass assessment excludes dash-valued records where this link status is not reported. The previous repeated-parameter clarification has been resolved.

Cluster HA and switchless mode use the captured node count plus `system switch ethernet show -type cluster-network`. The matrix is: a one-node cluster marks both settings not applicable; a two-node cluster expects cluster HA enabled and switchless mode enabled only when no cluster-network switches are reported; clusters with more than two nodes expect both flags disabled. The checks are findings when a reported value conflicts with that matrix, and needs review if node count, switch inventory, or the setting value cannot be read. Inventory counts and raw node/switch output appear in Collection details. Switch inventory is ONTAP's reported configuration and does not independently verify physical cabling.

`storage aggregate show-spare-disks` is collected for every cluster and shown in Collection details as raw evidence only. ONTAP groups spare output by pool and reports partitioned spares separately; do not infer adequate reserve from a nonempty listing alone. A defensible finding needs explicit reserve criteria by node, disk class, and SyncMirror pool. `storage pool show-available-capacity` is a different metric: pool allocation units may be provisioned and are not protection against disk failure. The collector does not currently run that command or calculate spare adequacy.

The final two Data checks query SnapMirror Mediator configuration using `snapmirror mediator show -connection-status !connected` and `snapmirror mediator show -quorum-status !true`. Their supported minimum is ONTAP 9.9.1, where both parameters are documented. The first selects any reported mediator connection status other than connected; the second includes false and unknown quorum status and checks whether the consistency-group relationships are synchronized with the mediator. They are read-only status queries, not active failover tests. Empty successful queries pass with an explicit caveat that mediator deployment, protected groups, and expected coverage were not established. See the [SnapMirror mediator command reference](https://docs.netapp.com/us-en/ontap-cli-991/snapmirror-mediator-show.html).

To list checks with unresolved or missing descriptive guidance without connecting:

```powershell
Get-OntapHealthCheckCommand | Where-Object { $_.InterpretationQuestion -or -not $_.Description } | Format-List Name, Command, InterpretationQuestion
```

Collect and review raw output, or export the structured report:

```powershell
$report = Invoke-OntapHealthCheck -Target cluster-mgmt.example.com -Credential $credential -NonInteractive
$report.Checks | Format-Table Category, Status, Health, Command -Wrap
$report.Checks | Where-Object Health -notin @('NoFindings', 'Successful') | Format-List *
$report | ConvertTo-Json -Depth 6 | Set-Content .\ontap-health-check.json -Encoding UTF8
```

The collector accepts the connection test's SSH options. `TimeoutSeconds` applies to each command, not the whole collection. It discovers the release using `version`, rejects unrecognized or non-ONTAP-9 releases, and applies the catalog's minimum releases: object-store availability (9.2), CIFS checks (9.5), key-manager queries (9.6), reachability (9.8), and connectivity diagnostics (9.9.1). If discovery returns multiple releases, the lowest is used. A single reported release cannot establish every node's version during a rolling upgrade.

`version` is the first command sent after the authenticated session prompt, before advanced setup or health checks. `Release` and `VersionOutput` retain the release text up to the first colon, for example `NetApp Release 9.16.1P12`; the build date and timestamp are excluded. Numeric `Version` remains `9.16.1` for release comparisons and compatibility. The HTML displays the patch-level version (`9.16.1P12`), including when it can recover that value from older saved `VersionOutput`. Distinct release labels from multi-line output are retained, separated by semicolons.

### Retained SSH Session

The collector authenticates once, discovers the release, enters advanced mode and disables pagination once, runs the checks sequentially, and sends `exit` at the end. All commands for one cluster share the same OpenSSH process and temporary credential helper. Verified host keys, isolated SSH configuration, DPAPI, and disabled forwarding remain unchanged. The connection-test function retains its original two-connection implementation.

```text
Authenticate -> Version -> Advanced/Rows Setup -> Connectivity Start
			 -> General -> Security -> Storage -> Network -> Data -> Connectivity Results -> Exit
```

Each command is sent only after the preceding command's ONTAP root prompt is received. Prompts and echoed input are excluded from command stdout; the remaining response is preserved, including partial output on failure. A command timeout, unexpected prompt, setup failure, or disconnect makes the session unusable: the affected check is errored, remaining checks are skipped, and the process is closed. No automatic reconnect or replay is attempted. Ordinary CLI errors are recorded and subsequent independent checks continue in the same session. `TimeoutSeconds` also bounds session startup, each setup command, and graceful shutdown. Unexpected confirmation prompts time out rather than being answered automatically.

The report exposes `SessionMode = Persistent`, the final process `SessionExitCode`, and `SessionError`. A shutdown error preserves completed check results and marks the root script's cluster collection `Partial`. Session authentication or release-discovery failures still terminate that cluster's collector. The prompt reader currently supports ONTAP root prompts such as `cluster::>` and `cluster::*>`; unsupported/custom prompt formats fail closed.

The baseline `9.0` catalog value means no newer minimum is specified, not that every argument is certified on all ONTAP 9 releases. Role, release, and platform differences can still cause command errors. Hardware-specific checks, such as service events and FRU LEDs, may fail on unsupported or mixed platforms. Their raw errors are retained, not converted to a passing result; node-specific platform discovery is not yet implemented.

### Security Checks

`NODAR check` runs `version -v` after General and before Storage. Its full command output is retained, independently of the trimmed release metadata gathered by the initial `version` command. The catalog row has an optional fifth value for its display name; saved checks include `Name` and, for this check, `EncryptionBuild`.

- `<1Ono-DARE>`: `EncryptionBuild = NODAR`, `Health = ReviewRequired`. At least one reported build lacks ONTAP software data-at-rest encryption/NVE support. The HTML preview groups it as a finding.
- `<1O>` with no conflicting/unknown build tags, warnings, or stderr: `EncryptionBuild = DAR`, `Health = Successful`, counted as passed. This assesses build capability only; platform support, licensing, key management, and encryption enablement are not checked.
- Missing/unrecognized tags: `EncryptionBuild = Unknown`, `Health = ReviewRequired`. An empty-query response is not a pass for this check. Mixed DAR/NODAR output is flagged as NODAR.

See NetApp's [Determine whether your ONTAP cluster version supports NVE](https://docs.netapp.com/us-en/ontap/encryption-at-rest/cluster-version-support-nve-task.html). NODAR does not establish whether independent hardware-based encryption is supported or enabled. Older saved collections are not modified and will not contain this new check; collect again to obtain its evidence.

### Diagnostic Checks

Cluster-connectivity start/results, peer-health queries, and CIFS checks run automatically as part of the default collection. These checks may initiate tests or refresh diagnostic state; they do not perform remediation. No diagnostic opt-in is required. The legacy `-IncludeDiagnostics` parameter is accepted for compatibility but has no effect, even when explicitly set to false.

```powershell
$report = Invoke-OntapHealthCheck -Target cluster-mgmt.example.com -Credential $credential -NonInteractive
```

After release discovery, the collector captures cluster identity, node inventory, cluster-network switch inventory, and `storage aggregate show-spare-disks` output once. Spare-disk output is displayed as inventory evidence only; no minimum spare threshold, reserve adequacy, or health verdict is inferred from it. For ONTAP 9.9.1+, connectivity start is the first health-check command, followed by catalog checks in order; connectivity results are queried last, allowing the other checks to run while diagnostics execute. The collector requests recent, unfiltered connectivity-test output and evaluates `Packet Loss` in PowerShell. If start fails, the results query is skipped to avoid presenting unrelated cached results. A local SSH timeout does not cancel an already-started cluster diagnostic.

Connectivity results receive `Health = Successful` when the command response completes without a detected CLI error, stderr is empty, at least one node record is returned, every node record has a `Packet Loss` value of `none`, and no warning or pending/in-progress message is detected. Loss, unknown values, missing records, empty results, or warnings require review. Raw output is always retained, including successful records, for inspection. This assessment covers the returned records only: expected node/path coverage, run freshness, and diagnostic completion are not automatically verified, and the cluster's relative `>10m` filter alone does not prove every record belongs to this run. The faster collection may reach results before diagnostics complete; empty/incomplete results require review rather than an artificial delay or assumed success. Peer-health and CIFS queries pass when their completed response explicitly contains no matching entries; diagnostic labeling alone does not imply a problem. Connectivity-start output describes test initiation, not a health verdict, and remains available for review.

### Result Semantics

The report includes target, port, detected release, discovery output, local start/finish times, an `Inventory` object with cluster name/UUID, node count, cluster-network switch count, raw node/switch output, and raw spare-disk output plus collection status. Spare-disk output is evidence only and is not included in health-check totals. `SessionStartupStdOut`/`SessionStartupStdErr` retain text emitted before the initial ONTAP prompt. Startup notices such as legal banners are displayed in Collection details; they do not prevent collection after the prompt is established. `StartedAt` and `FinishedAt` are ISO 8601 strings with the runner system's local UTC offset, for example `2026-10-26T20:49:15.5970000+11:00`; these replace the former `StartedAtUtc` and `FinishedAtUtc` fields at wrapper, report, and check levels. Cluster timestamps in raw CLI output are preserved unchanged. Diagnostic inclusion does not guarantee every diagnostic executed: inspect each check's status and reason. Each check retains its command, category, minimum release, diagnostic flag, timestamps, SSH exit code, stdout, stderr, status, health assessment, and reason.

- Per-check `ExitCode` is `null` for the persistent shell: OpenSSH provides a process exit status, not separate exit statuses for commands inside that shell. `CommandSucceeded` indicates whether that command produced a completed response without a detected CLI error (`null` for skipped checks). Do not interpret it as a health verdict. The final transport exit is stored separately as `SessionExitCode`.
- `Status = Collected`: the command returned nonempty output followed by the expected prompt without a detected CLI error. This is not a health verdict. Empty-table responses no longer inherit the legacy per-connection SSH exit of 255. Partitioned-disk informational output is retained for review; its suggested spare-capacity command is not run automatically.
- `Status = Error`: timeout, disconnected session, detected CLI error, failed setup, or blank output. Ordinary CLI command errors do not prevent subsequent independent checks. Session-level failures stop further execution and retain partial output in the affected check.
- `Status = Skipped`: the release is too old, connectivity start failed, or a prior SSH transport failure stopped collection. The reason explains which. Diagnostic entries are not skipped merely because they are diagnostics.
- `Health = NoFindings`: a pass for a successfully completed query check whose stdout, after trimming and removing an optional leading `Last login time:` line, is an explicit `There are no entries matching your query.` or `This table is currently empty.` response, with no stderr. This includes peer-health and CIFS queries. Confirmed session prompts, including repeated trailing prompts, are excluded from command responses. A disk query may also include the exact partitioned-disk notice and its optional known storage-pool capacity notice; these are retained as informational output, and neither spare-disk nor pool capacity is assessed by this check. Blank, unauthorized, unsupported, warning-bearing, or otherwise unrecognized responses never pass. This rule does not apply to connectivity initiation or its result-evidence check.
- `Health = Successful`: a specialized assessment passed, such as no packet loss in the final connectivity results or a recognized DAR-capable build in the NODAR check. The evidence is retained; this is not an overall cluster-health verdict.
- `Health = NotApplicable`: the check completed, but its documented configuration scope does not apply, such as cluster HA or switchless mode on a single-node cluster. The HTML classifies this as Information, not Passed.
- `Health = ReviewRequired`: other collected output, including unhealthy-condition rows, warnings, diagnostic activity not assessed as a pass, or incomplete connectivity evidence; review the raw response and reason. `AssessmentOutcome` distinguishes topology mismatches shown as Findings from uncertain evidence shown as Needs review. It is not assigned merely because a query is marked diagnostic.
- `Health = Unknown`: errored or skipped checks. There is deliberately no overall healthy verdict.

Discovery and local setup failures throw terminating errors. Treat saved reports as sensitive infrastructure data and store them with appropriate access controls.

## Local Regression Test

No cluster, credentials, Pester installation, or additional SSH library is needed. The test compiles a temporary mock executable using Windows PowerShell's .NET Framework compiler and exercises argument quoting, password-helper round trips, trust options, CLI errors, timeouts, and cleanup:

```powershell
powershell.exe -NoProfile -File .\Tests\Test-OntapSsh.ps1
powershell.exe -NoProfile -File .\Tests\Test-OntapHealthCheck.ps1
pwsh -NoProfile -File .\Tests\Test-OntapHealthCheck.ps1
powershell.exe -NoProfile -File .\Tests\Test-OntapHealthCheckRunner.ps1
pwsh -NoProfile -File .\Tests\Test-OntapHealthCheckRunner.ps1
```

The SSH integration test verifies exactly one authenticated process and one privilege setup per collection, all supported catalog entries, per-command response framing, output larger than one read buffer, prompt-like response text, graceful exit, nonzero shutdown, CLI-error continuation, setup failures, disconnects, timeouts, partial output, and helper cleanup. The collector policy test uses an in-module transport double and covers all explicit version boundaries, default diagnostic inclusion, legacy-switch compatibility, diagnostic ordering, failed starts, error continuation, transport abort, and conservative health classification on both PowerShell editions. The mock executable test requires Windows PowerShell 5.1 to compile its .NET Framework executable.

The runner test uses a temporary copy of the real collector with a private transport double to verify comma/whitespace/file inputs, case-insensitive deduplication, IPv6, per-cluster JSON reports, HTML generation, absence of a summary CSV, failure isolation, validation before connections, unattended mode, and overwrite protection on both PowerShell editions. It also preloads a stale module and verifies the entry script replaces it with the current module file.

The persistent collector was live-tested against ONTAP 9.16.1P12: all 56 entries collected without errors or skips and the session exited zero. Collector execution after authentication took approximately 33 seconds, compared with roughly 5.5 minutes for the saved per-command-connection run. This is one cluster's observation, not a performance guarantee. Other releases/platforms, RBAC combinations, prompt formats, and diagnostic completion still require validation; local tests do not certify those cluster-side behaviors.

## Public Samples and Publishing

Maintained by Chris Jones. This repository is intended for publication in NTAP-Automation-Central and under chjones45 on GitHub. Documentation and sample links use relative paths so they work in either copy without assuming a branch name or a final repository URL.

### Sample Report

The front-page README embeds [a screenshot](samples/ONTAP-Health-Report.png) and links to [the interactive HTML sample](samples/ONTAP-Health-Report.html). The HTML is self-contained: download it using GitHub's **Download raw file** button and open it locally. GitHub's repository file viewer displays source rather than executing HTML or JavaScript.

[samples/synthetic-collection.json](samples/synthetic-collection.json) is a deliberately small, entirely fictional collection illustrating different result types, not a complete catalog run or a real cluster assessment. The renderer adds two illustrative clusters to demonstrate complete and failed collections. No saved production reports are used. The sample is marked as a design preview, and its collection details identify the input as synthetic.

To rebuild the HTML from the repository root without credentials or network access:

```powershell
.\ReportAssets\New-OntapHealthReport.ps1 -ReportPath .\samples\synthetic-collection.json -OutputPath .\samples\ONTAP-Health-Report.html -DesignPreview -IncludeDemoClusters
```

Rebuild the HTML and refresh the screenshot when the report design changes. These are documentation assets; collection and regression tests do not depend on them. Do not replace the synthetic input with customer data or publish real reports, credentials, addresses, serial numbers, or other sensitive infrastructure evidence. Generated production reports remain excluded by the `Reports/` ignore rule. Output saved elsewhere with `-OutputDirectory` is not automatically excluded; use a protected location outside this repository.

### Optional Browser-Hosted Demo

GitHub Pages can serve the sample as a working interactive report, subject to repository visibility, account support, and organization policy. Pages has not been configured by this documentation change. To enable it in an approved repository:

1. In **Settings > Pages**, choose **Deploy from a branch**, select the published branch, and select **/(root)** as the publishing folder.
2. After deployment, append `samples/ONTAP-Health-Report.html` to the Pages site URL shown in Settings.
3. Add that URL to the front-page README as a live-demo link. Choose one canonical demo if both GitHub repositories should link to the same deployment.

A project site's default URL is typically `https://<owner>.github.io/<repository>/samples/ONTAP-Health-Report.html`; use the actual deployed URL rather than assuming this pattern. Organization repositories and private repositories may have different availability, access controls, or domains. Only publish the synthetic sample. The screenshot and downloadable HTML work without Pages.

### Publish to GitHub

Create an empty repository at https://github.com/new with these settings:

- Owner: `chjones45`
- Repository name: `ONTAP-Cluster-Health-Report`
- Description: `PowerShell health checks for NetApp ONTAP 9 clusters over SSH, with self-contained HTML reports.`
- Visibility: Public for open-source distribution, or Private until publication is approved.
- Do not initialize with a README, .gitignore, or license; these files already exist locally.

After creating the repository, its HTTPS remote will be:

```text
https://github.com/chjones45/ONTAP-Cluster-Health-Report.git
```

In VS Code, review Source Control changes before staging and creating the initial commit. Use **Git: Add Remote** from the Command Palette, name it `origin`, and enter the URL above. Use **Git: Push** and select `origin` if prompted. Complete GitHub sign-in through VS Code's browser flow; do not put a password or token in the remote URL. If `origin` is already configured, do not add it again.

The `.gitignore` protects the default `Reports/` directory, the local `clusters.txt` target list, common private-key/credential files, and temporary files. It is not a secret scanner: inspect the staged files, including samples, before every push. Confirm that you have permission to publish the code and redistribute the included NetApp branding before making the repository public.

## License

Code is provided under the [MIT License](LICENSE), without warranty. NetApp and ONTAP names and the NetApp logo are trademarks of NetApp, Inc.; the code license does not grant trademark rights. This is a community tool, not an official NetApp support assessment.
