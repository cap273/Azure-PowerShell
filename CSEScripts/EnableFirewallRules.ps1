### Enable ICMP (PING) Firewall Rule ###
New-NetFirewallRule -Name Allow_Ping -DisplayName “Allow Ping” -Description “Packet Internet Groper ICMPv4” -Protocol ICMPv4 -IcmpType 8 -Enabled True -Profile Any -Action Allow

### Enable file sharing Firewall Rule ###
Set-NetFirewallRule -Enabled True -Name 'FPS-NB_Session-In-TCP' -Profile any
Set-NetFirewallRule -Enabled True -Name 'FPS-SMB-In-TCP' -Profile any
Set-NetFirewallRule -Enabled True -Name 'FPS-NB_Name-In-UDP' -Profile any
Set-NetFirewallRule -Enabled True -Name 'FPS-NB_Datagram-In-UDP' -Profile any

### Enable WMI for Remote Management ###
Set-NetFirewallRule -Enabled True -Name 'WMI-RPCSS-In-TCP' -Profile any
Set-NetFirewallRule -Enabled True -Name 'WMI-WINMGMT-In-TCP' -Profile any
Set-NetFirewallRule -Enabled True -Name 'WMI-ASYNC-In-TCP' -Profile any
