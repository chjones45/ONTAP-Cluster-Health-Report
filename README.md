# ONTAP Health Check (PowerShell)

Collect health-check evidence from **NetApp ONTAP 9** clusters over SSH and generate one interactive, self-contained HTML report. Review General, Security, Storage, Network, and Data checks across one or more clusters, inspect the CLI evidence, and export filtered results to CSV.

No remediation or persistent configuration changes are performed. Diagnostics run by default and may initiate tests or refresh diagnostic state. Results are a point-in-time assessment, not an overall cluster-health verdict.

## Requirements

- **Windows PowerShell 5.1 or PowerShell 7 on Windows.**
- **Windows OpenSSH Client 8.4+** (`ssh.exe`). Check with `ssh -V`.
- SSH access to each cluster's management address and an ONTAP account with advanced CLI privilege and permission to run the checks.
- Password or single-password keyboard-interactive authentication. Multi-step MFA is not supported.

No additional PowerShell modules are required.

## Quick Start

1. Download and extract the **whole repository**, or clone it, then open PowerShell in its folder. Keep the root script, `Modules`, and `ReportAssets` together; downloading only the root script is not enough. If Windows blocks the downloaded PowerShell files, review them and unblock them:

   ```powershell
   Get-ChildItem . -Recurse -File -Include *.ps1,*.psm1,*.psd1 | Unblock-File
   ```

2. Establish SSH trust for each cluster. Obtain its host-key fingerprint from a trusted administrator or management channel, then connect and compare it **before accepting**:

   ```powershell
   ssh -F NUL -o StrictHostKeyChecking=ask -l admin cluster-mgmt.example.com
   ```

   Replace `admin` with your ONTAP username. Exit the SSH session after verifying the key. Do not accept an unverified fingerprint or bypass a changed-key warning.

3. Run the health check and enter your credentials when prompted:

   ```powershell
   .\ONTAPHealthCheck.ps1 cluster-mgmt.example.com -OpenReport
   ```

   The report opens when collection and HTML generation finish. Without `-OpenReport`, open the HTML file at the path printed in the console:

   ```text
   Reports/<run-timestamp>/ONTAP-Health-Report.html
   ```

Running `.\ONTAPHealthCheck.ps1` without arguments prompts for cluster names or IP addresses first. Use bare hostnames, FQDNs, or IP addresses, not URLs or `user@host` values.

### More Examples

```powershell
# Check several clusters; choose whether to reuse credentials when prompted
.\ONTAPHealthCheck.ps1 cluster1 cluster2 192.0.2.10 -OpenReport

# Read cluster targets from a text file
.\ONTAPHealthCheck.ps1 -ClusterFile .\clusters.txt -OpenReport

# Keep the per-cluster JSON as well as the HTML report
.\ONTAPHealthCheck.ps1 cluster1 -KeepAllOutputFiles
```

## Report Preview

![ONTAP Health Check sample report showing cluster summaries and an attention register, using synthetic data only](samples/ONTAP-Health-Report.png)

[Download the interactive HTML sample](samples/ONTAP-Health-Report.html) using GitHub's **Download raw file** button, then open it in a browser. The sample uses synthetic data only; no cluster access is needed. GitHub's repository file viewer does not run HTML or JavaScript.

Your generated report works offline and can be shared as a single HTML file. It includes cluster summaries, clickable totals, filters, expandable check evidence, and CSV exports. Reports contain sensitive infrastructure data: store and share real reports securely, and do not commit them to GitHub. JSON is removed after successful HTML generation unless you use `-KeepAllOutputFiles`.

## Detailed Reference

See [README - Detailed.md](README%20-%20Detailed.md) for SSH trust options, unattended runs, output retention and recovery, check assessments, diagnostic caveats, security details, and regression tests.

## License

Code is provided under the [MIT License](LICENSE), without warranty. NetApp and ONTAP names and the NetApp logo are trademarks of NetApp, Inc.; the code license does not grant trademark rights. This is a community tool, not an official NetApp support assessment.
