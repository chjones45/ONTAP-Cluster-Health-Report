@{
    'cluster kernel-service show -status-quorum out-of-quorum' = @{
        Name = 'Kernel services outside quorum'
        Description = 'Checks cluster kernel services for an out-of-quorum status.'
        PassMessage = 'No cluster kernel services reported an out-of-quorum status.'
    }
    'cluster kernel-service show -status-avail !true' = @{
        Name = 'Unavailable kernel services'
        Description = 'Checks for kernel services whose availability flag is not true.'
        PassMessage = 'No cluster kernel services reported availability other than true.'
    }
    'cluster kernel-service show -status-oper !operational' = @{
        Name = 'Nonoperational kernel services'
        Description = 'Checks for kernel services whose operational status is not operational.'
        PassMessage = 'No cluster kernel services reported a nonoperational status.'
    }
    'cluster peer health show -bypass-cache false -availability false' = @{
        Name = 'Unavailable cluster peers'
        Description = 'Checks peer-cluster health for availability=false using cached information where available; the cache is not forcibly bypassed.'
        PassMessage = 'No peer-cluster health entries reported availability=false in this query. This does not establish that peers are configured or independently verify current connectivity.'
    }
    'cluster ring show -online offline' = @{
        Name = 'Offline cluster rings'
        Description = 'Checks the cluster ring service records for an offline state.'
        PassMessage = 'No cluster ring entries were reported offline.'
    }
    'cluster show -eligibility false' = @{
        Name = 'Ineligible cluster nodes'
        Description = 'Checks for cluster nodes that are not eligible to participate in the cluster.'
        PassMessage = 'No cluster nodes reported eligibility=false.'
    }
    'cluster show -health false' = @{
        Name = 'Unhealthy cluster nodes'
        Description = 'Checks the cluster node health flag. This flag is not a comprehensive assessment of every subsystem.'
        PassMessage = 'No cluster nodes reported health=false. Other subsystem and hardware checks remain separate.'
    }
    'cluster ha show' = @{
        Name = 'Cluster HA configuration'
        Description = 'Checks the High-Availability Configured value against the captured node count. ONTAP cluster HA is applicable to two-node clusters; single-node clusters are reported as not applicable, and clusters with more than two nodes are expected to have this setting disabled.'
        PassMessage = 'Cluster HA configuration matches the captured node count.'
        DocumentationUrl = 'https://docs.netapp.com/us-en/ontap-cli/cluster-ha-show.html'
    }
    'network options switchless-cluster show' = @{
        Name = 'Switchless cluster configuration'
        Description = 'Checks Enable Switchless Cluster against node count and the reported cluster-network switch inventory. Single-node clusters are not applicable; on two-node clusters switchless mode is expected only when no cluster-network switches are reported; clusters with more than two nodes are expected to have it disabled.'
        PassMessage = 'Switchless cluster configuration matches the captured node count and cluster-network switch inventory.'
        DocumentationUrl = 'https://docs.netapp.com/us-en/ontap-cli/network-options-switchless-cluster-show.html'
    }
    'job show -state Failure|Error|Quit|Dead|Unknown' = @{
        Name = 'Failed or abnormal jobs'
        Description = 'Checks visible job records for Failure, Error, Quit, Dead, or Unknown states; it is not a complete historical job audit.'
        PassMessage = 'No visible job records matched Failure, Error, Quit, Dead, or Unknown.'
    }
    'system chassis show -status !ok' = @{
        Name = 'Chassis status'
        Description = 'Checks chassis records for status other than ok, on platforms that expose this command.'
        PassMessage = 'No reported chassis had a status other than ok.'
    }
    'system controller config show-errors -description !"sysconfig: There are no configuration errors."*' = @{
        Name = 'Controller configuration errors'
        Description = 'Checks controller configuration error descriptions, excluding the standard sysconfig message stating there are no configuration errors.'
        PassMessage = 'No controller configuration error descriptions remained after excluding the standard no-configuration-errors message.'
    }
    'system controller environment show -status !ok' = @{
        Name = 'Controller environmental status'
        Description = 'Checks controller environmental component records for status other than ok.'
        PassMessage = 'No controller environmental components reported status other than ok.'
    }
    'system controller memory dimm show -status !ok' = @{
        Name = 'Controller memory DIMMs'
        Description = 'Checks reported controller DIMM status for values other than ok.'
        PassMessage = 'No reported controller memory DIMMs had status other than ok.'
    }
    'system controller service-event show' = @{
        Name = 'Controller service events'
        Description = 'Lists controller service events on supported platforms. An empty table does not verify platform coverage or every hardware fault source.'
        PassMessage = 'No controller service events were returned by the supported service-event interface.'
    }
    'system fru-check show -fru-status !pass' = @{
        Name = 'FRU validation status'
        Description = 'Checks field-replaceable-unit validation records for a result other than pass.'
        PassMessage = 'No reported field-replaceable-unit validation checks had a status other than pass.'
    }
    'system ha interconnect status show -is-link0-active !"-" -link0-status !up' = @{
        Name = 'HA interconnect link 0'
        Description = 'Checks for HA link 0 status other than up where the link-0-active field is populated rather than a dash. The filter does not require that active=true.'
        PassMessage = 'No applicable HA interconnect link 0 records reported a link status other than up; dash-valued activity records were excluded.'
        DocumentationUrl = 'https://docs.netapp.com/us-en/ontap-cli/system-ha-interconnect-status-show.html'
    }
    'system ha interconnect status show -is-link1-active !"-" -link1-status !up' = @{
        Name = 'HA interconnect link 1'
        Description = 'Checks for HA link 1 status other than up where the link-1-active field is populated rather than a dash. The filter does not require that active=true.'
        PassMessage = 'No applicable HA interconnect link 1 records reported a link status other than up; dash-valued activity records were excluded.'
        DocumentationUrl = 'https://docs.netapp.com/us-en/ontap-cli/system-ha-interconnect-status-show.html'
    }
    'system ha interconnect status show -link-status !"-",!up' = @{
        Name = 'Single-link HA interconnect status'
        Description = 'Checks single-link HA interconnect records for link status other than up, excluding dash-valued records where this status is not reported.'
        PassMessage = 'No applicable single-link HA interconnect records reported a link status other than up; dash-valued records were excluded.'
        DocumentationUrl = 'https://docs.netapp.com/us-en/ontap-cli/system-ha-interconnect-status-show.html'
    }
    'system ha interconnect status show -ic-rdma !up' = @{
        Name = 'HA interconnect RDMA connection'
        Description = 'Checks the HA interconnect RDMA connection to each partner for a state other than up.'
        PassMessage = 'No reported HA interconnect RDMA connections had a state other than up.'
        DocumentationUrl = 'https://docs.netapp.com/us-en/ontap-cli/system-ha-interconnect-status-show.html'
    }
    'system health alert show' = @{
        Name = 'System health alerts'
        Description = 'Checks alerts currently exposed by the ONTAP system-health monitor, not historical EMS events or every possible monitoring source.'
        PassMessage = 'No system-health-monitor alerts were returned at collection time.'
    }
    'system health subsystem show -health !ok' = @{
        Name = 'System health subsystems'
        Description = 'Checks monitored health subsystems for a health state other than ok.'
        PassMessage = 'No monitored health subsystems reported health other than ok.'
    }
    'system node environment sensors show -state !normal' = @{
        Name = 'Environmental sensor states'
        Description = 'Checks reported node environmental sensors for a state other than normal.'
        PassMessage = 'No reported environmental sensors had a state other than normal.'
    }
    'system service-processor show -status !online' = @{
        Name = 'Service processor availability'
        Description = 'Checks the ONTAP-reported service processor or BMC status for values other than online; it does not perform an external management-network login.'
        PassMessage = 'No reported service processors had status other than online.'
    }
    'system services web node show -status !online' = @{
        Name = 'Node web service status'
        Description = 'Checks per-node web-service status for values other than online; external HTTPS reachability and certificates are not tested.'
        PassMessage = 'No node web-service entries reported status other than online.'
    }
    'version -v' = @{
        Name = 'NODAR check'
        Description = 'Examines version -v build markers to distinguish DAR-capable <1O> builds from no-DARE/NODAR <1Ono-DARE> builds. Build capability does not prove encryption is enabled.'
        DocumentationUrl = 'https://docs.netapp.com/us-en/ontap/encryption-at-rest/cluster-version-support-nve-task.html'
    }
    'security key-manager key query -restored false' = @{
        Name = 'Encryption keys not restored'
        Description = 'Checks encryption-key records exposed by the key manager for restored=false; it does not prove that encryption or a key manager is configured.'
        PassMessage = 'No queried encryption keys reported restored=false. Key-manager configuration and actual encryption enablement are not established by an empty result.'
    }
    'storage aggregate show -state !online' = @{
        Name = 'Aggregate operational state'
        Description = 'Checks aggregates for an operational state other than online.'
        PassMessage = 'No reported aggregates had a state other than online.'
    }
    'storage aggregate show -raidstatus !*normal*' = @{
        Name = 'Aggregate RAID status'
        Description = 'Checks aggregate RAID-status text for entries that do not contain normal. This filter is not a physical disk or path diagnostic.'
        PassMessage = 'No aggregate RAID-status entries failed the configured *normal* text match.'
    }
    'storage aggregate object-store show -object-store-availability unavailable' = @{
        Name = 'Aggregate object-store availability'
        Description = 'Checks aggregate object-store associations for availability=unavailable; clusters without object-store associations may return no entries.'
        PassMessage = 'No aggregate object-store associations reported unavailable. This does not establish that an object store is configured.'
    }
    'storage bridge show -status !ok' = @{
        Name = 'Storage bridge status'
        Description = 'Checks reported storage bridges for status other than ok; systems without bridges may return no entries.'
        PassMessage = 'No reported storage bridges had status other than ok. Bridge inventory is not established by an empty result.'
    }
    'storage disk show -state !spare,!present -container-type !remote,!mediator' = @{
        Name = 'Abnormal disk states'
        Description = 'Checks disk records outside spare/present states, excluding remote and mediator container types. It is not a complete spare-capacity or disk-path assessment.'
        PassMessage = 'No disks matched states outside spare/present after excluding remote and mediator containers. Spare capacity and disk-path redundancy are separate checks.'
        DocumentationUrl = 'https://docs.netapp.com/us-en/ontap-cli/storage-disk-show.html'
    }
    'storage pool show -is-healthy false' = @{
        Name = 'Unhealthy storage pools'
        Description = 'Checks SSD storage pools for is-healthy=false. ONTAP provides an unhealthy-reason for unhealthy pools, and is-healthy must be true to provision allocation units into an aggregate. An empty result does not establish that any storage pools are configured.'
        PassMessage = 'No storage pools reported is-healthy=false. This does not establish that the cluster has storage pools configured.'
        DocumentationUrl = 'https://docs.netapp.com/us-en/ontap-cli/storage-pool-show.html'
    }
    'storage errors show' = @{
        Name = 'Storage configuration errors'
        Description = 'Checks storage configuration faults exposed by storage errors show; it is not a complete historical disk-error log.'
        PassMessage = 'No storage configuration errors were returned by storage errors show.'
    }
    'storage failover show -enabled false' = @{
        Name = 'Storage failover disabled'
        Description = 'Checks nodes for storage takeover enabled=false. No takeover or failover test is performed.'
        PassMessage = 'No nodes reported storage takeover enabled=false; takeover was not exercised.'
        DocumentationUrl = 'https://docs.netapp.com/us-en/ontap-cli/storage-failover-show.html'
    }
    'storage failover show -partner-aggregates !false -state-description !"Non-HA mode"' = @{
        Name = 'Partner aggregates under local control'
        Description = 'Checks for nodes whose control-partner-aggregates field is not false, excluding the Non-HA mode description. This identifies takeover-related ownership states for review.'
        PassMessage = 'No nodes matched control of partner aggregates outside the excluded Non-HA mode description. This does not prove a takeover test would succeed.'
        DocumentationUrl = 'https://docs.netapp.com/us-en/ontap-cli/storage-failover-show.html'
    }
    'storage failover show -possible false' = @{
        Name = 'Storage takeover not possible'
        Description = 'Checks the currently reported takeover-possible flag for false; it does not perform a takeover.'
        PassMessage = 'No nodes reported takeover possible=false at collection time; takeover was not exercised.'
        DocumentationUrl = 'https://docs.netapp.com/us-en/ontap-cli/storage-failover-show.html'
    }
    'storage failover hwassist show -enabled false' = @{
        Name = 'Hardware-assisted failover disabled'
        Description = 'Checks for nodes with local hardware-assisted failover disabled. This is separate from the general storage takeover-enabled flag.'
        PassMessage = 'No hardware-assisted failover entries reported enabled=false.'
        DocumentationUrl = 'https://docs.netapp.com/us-en/ontap-cli/storage-failover-hwassist-show.html'
    }
    'storage failover hwassist show -local-inactive !"-"' = @{
        Name = 'Hardware-assisted failover inactive reason'
        Description = 'Checks for a populated local hardware-assist inactive reason, excluding the dash used when no inactive reason is reported.'
        PassMessage = 'No hardware-assisted failover entries reported a local inactive reason other than the dash placeholder.'
        DocumentationUrl = 'https://docs.netapp.com/us-en/ontap-cli/storage-failover-hwassist-show.html'
    }
    'storage port show -errors' = @{
        Name = 'Storage port errors'
        Description = 'Checks storage ports returned by the errors view; this is not a reset or an active port diagnostic.'
        PassMessage = 'No storage port entries were returned by the errors view.'
    }
    'storage shelf show -op-status !Normal' = @{
        Name = 'Storage shelf operational status'
        Description = 'Checks reported storage shelves for an operational status other than Normal.'
        PassMessage = 'No reported storage shelves had an operational status other than Normal.'
    }
    'network fcp adapter show -is-conn-established false -status-admin up' = @{
        Name = 'Enabled FCP adapters without a connection'
        Description = 'Checks FCP adapters that are administratively up but have no established connection. Administratively down adapters are excluded.'
        PassMessage = 'No administratively up FCP adapters reported an unestablished connection. FCP deployment is not established by an empty query.'
    }
    'network interface show -is-home false' = @{
        Name = 'LIF(s) are not at their home port'
        Description = 'Checks LIFs for is-home=false. A LIF away from its home port may be intentional during failover or maintenance and is not automatically an outage.'
        PassMessage = 'No LIFs reported is-home=false; no queried LIFs were reported away from their home port.'
    }
    'network interface show -status-oper down -status-extended !"This LIF is down because its Vserver is stopped"*' = @{
        Name = 'Operationally down LIFs'
        Description = 'Checks operationally down LIFs, excluding the extended-status explanation that their SVM is stopped.'
        PassMessage = 'No operationally down LIFs remained after excluding LIFs whose SVM is stopped. Client connectivity is not actively tested.'
    }
    'network port ifgrp show -mode !singlemode -activeports !full' = @{
        Name = 'Multimode interface-group participation'
        Description = 'Checks non-singlemode interface groups for activeports other than full, looking for less-than-full member-port participation.'
        PassMessage = 'No non-singlemode interface groups reported active-port participation other than full.'
    }
    'network port ifgrp show -mode singlemode -activeports !partial' = @{
        Name = 'Singlemode interface-group participation'
        Description = 'Checks singlemode interface groups for activeports other than partial; singlemode normally uses one active member rather than all members.'
        PassMessage = 'No singlemode interface groups reported active-port participation other than partial.'
    }
    'network port reachability show -reachability-status !ok -expected-broadcast-domain !"-"' = @{
        Name = 'Port reachability'
        Description = 'Checks reachability status other than ok for ports with an expected broadcast domain. Records with a dash expected domain are excluded.'
        PassMessage = 'No ports with an assigned expected broadcast domain reported reachability status other than ok. Ports without an expected domain were excluded.'
    }
    'network port show -health-status degraded' = @{
        Name = 'Degraded network ports'
        Description = 'Checks physical/network port health-status records specifically for degraded.'
        PassMessage = 'No network ports reported health-status=degraded.'
    }
    'network port show -link !up -up-admin true' = @{
        Name = 'Enabled network ports without link'
        Description = 'Checks ports that are administratively enabled but whose link state is not up. Administratively disabled ports are excluded.'
        PassMessage = 'No administratively enabled network ports reported a link state other than up.'
    }
    'lun show -state !online' = @{
        Name = 'LUNs not online'
        Description = 'Checks reported LUNs for a state other than online. This does not validate host mapping, multipathing, or client I/O.'
        PassMessage = 'No reported LUNs had a state other than online. Host access and actual I/O were not tested.'
    }
    'snapmirror show -healthy false' = @{
        Name = 'Unhealthy SnapMirror relationships'
        Description = 'Checks visible SnapMirror relationships for healthy=false. A result can reflect intentional break-off or maintenance and needs operational context.'
        PassMessage = 'No visible SnapMirror relationships reported healthy=false. This does not establish that relationships exist or validate recovery-point objectives.'
    }
    'volume show -in-nvfailed-state true' = @{
        Name = 'Volumes in NVFAIL state'
        Description = 'Checks volumes explicitly reporting in-nvfailed-state=true.'
        PassMessage = 'No volumes reported in-nvfailed-state=true.'
    }
    'volume show -is-inconsistent true' = @{
        Name = 'Inconsistent volumes'
        Description = 'Checks volumes explicitly marked inconsistent by ONTAP; no filesystem repair or consistency scan is initiated.'
        PassMessage = 'No volumes reported is-inconsistent=true. No active filesystem consistency scan was performed.'
    }
    'volume show -state !online,!restricted -size !"-"' = @{
        Name = 'Volumes not online or restricted'
        Description = 'Checks volumes with a reported size whose state is neither online nor restricted; dash-sized records are excluded.'
        PassMessage = 'No volumes with a reported size had a state outside online/restricted. Restricted volumes and dash-sized records were excluded.'
    }
    'vserver cifs check -status down' = @{
        Name = 'CIFS supporting-service checks'
        Description = 'Checks CIFS/SMB supporting-service diagnostic results for status=down; this is not an end-to-end client share access test.'
        PassMessage = 'No CIFS supporting-service check entries reported status=down. Client share access and CIFS deployment were not established by this query.'
    }
    'vserver cifs show -status-admin down' = @{
        Name = 'Administratively down CIFS servers'
        Description = 'Checks configured CIFS/SMB server records for an administratively down state.'
        PassMessage = 'No reported CIFS/SMB servers were administratively down. An empty result can also occur when no CIFS servers are configured.'
    }
    'vserver fcp show -status-admin down' = @{
        Name = 'Administratively down FCP services'
        Description = 'Checks SVM FCP service records for an administratively down state.'
        PassMessage = 'No reported SVM FCP services were administratively down. An empty result does not establish that FCP is configured.'
    }
    'vserver iscsi show -status-admin down' = @{
        Name = 'Administratively down iSCSI services'
        Description = 'Checks SVM iSCSI service records for an administratively down state.'
        PassMessage = 'No reported SVM iSCSI services were administratively down. An empty result does not establish that iSCSI is configured.'
    }
    'vserver nfs show -access !true' = @{
        Name = 'NFS access not enabled'
        Description = 'Checks SVM NFS service records whose access-enabled flag is not true; export-policy correctness and actual client access are not tested.'
        PassMessage = 'No reported NFS service records had an access flag other than true. This does not establish NFS deployment or validate export-policy access.'
    }
    'vserver show -type data -operational-state !running -subtype !dp-destination,!sync-destination' = @{
        Name = 'Data SVMs not running'
        Description = 'Checks data SVMs for operational states other than running, excluding dp-destination and sync-destination subtypes.'
        PassMessage = 'No data SVMs outside the excluded replication-destination subtypes reported an operational state other than running.'
    }
    'snapmirror mediator show -connection-status !connected' = @{
        Name = 'SnapMirror mediator connection status'
        Description = 'Checks ONTAP Mediator configurations for a connection status other than connected, including unreachable, suspended, unusable, misconfigured, transitional or unknown states. It does not configure a mediator or initiate failover.'
        PassMessage = 'No reported SnapMirror mediator configurations had a connection status other than connected. An empty result can also mean no mediator is configured; deployment and expected coverage were not established.'
        DocumentationUrl = 'https://docs.netapp.com/us-en/ontap-cli-991/snapmirror-mediator-show.html'
    }
    'snapmirror mediator show -quorum-status !true' = @{
        Name = 'SnapMirror mediator quorum status'
        Description = 'Checks ONTAP Mediator configurations for quorum-status other than true, including false and unknown. This status reports whether SnapMirror consistency-group relationships are synchronized with the mediator; it is not an active failover test.'
        PassMessage = 'No reported SnapMirror mediator configurations had quorum-status other than true. An empty result does not establish that a mediator or protected consistency groups are configured, and no failover was exercised.'
        DocumentationUrl = 'https://docs.netapp.com/us-en/ontap-cli-991/snapmirror-mediator-show.html'
    }
    'network interface check cluster-connectivity start -node *' = @{
        Name = 'Cluster connectivity diagnostics started'
        Description = 'Starts cluster-network connectivity diagnostics on all selected nodes. Acknowledgement is not proof of completion or zero packet loss.'
    }
    'network interface check cluster-connectivity show -node * -date-time >10m -instance' = @{
        Name = 'Cluster connectivity packet loss'
        Description = 'Retrieves recent unfiltered connectivity records and evaluates their Packet Loss values in the script. Freshness and complete expected node/path coverage are not automatically verified.'
    }
}