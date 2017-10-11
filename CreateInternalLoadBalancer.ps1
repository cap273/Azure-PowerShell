$ServiceName = "placeholder"
$ILBName = "placeholder"
$SubnetName = "placeholder"
$VNetName = "placeholder"
$IPAddressPrefix = "placeholder"
$ILBSetName = "placeholder"
$EndpointNamePrefix = "placeholder"

Write-Host "List of available IP addresses:"
Write-Host (Test-AzureStaticVNetIP -VNetName $VNetName -IPAddress $IPAddressPrefix).AvailableAddresses

$IPAddress = Read-Host -Prompt "Enter the desired IP address of the ILB:"

Write-Host "Adding Internal Load Balancer $ILBName..."

# Make the internal load balancer
Add-AzureInternalLoadBalancer -InternalLoadBalancerName $ILBName `
                              -ServiceName $ServiceName `
                              -SubnetName $SubnetName `
                              -StaticVNetIPAddress $IPAddress

# Get all VMs in selected cloud service
$vms = Get-AzureVM -ServiceName $ServiceName

# Initialize a counter
$i = 1
foreach ($vm in $vms) {
    
    # Build endpoint name specific to each VM
    $EndpointName = $EndpointNamePrefix + $i

    Write-Host "Adding Endpoint $EndpointName on VM $($vm.HostName)..."
    
    $vm | Add-AzureEndpoint -Name $EndpointName `
                            -LBSetName $ILBSetName `
                            -Protocol tcp `
                            -LocalPort 8080 `
                            -PublicPort 8080 `
                            -ProbeProtocol tcp `
                            -ProbePort 8080 `
                            -ProbeIntervalInSeconds 5 `
                            -ProbeTimeoutInSeconds 15 `
                            -IdleTimeoutInMinutes 5 `
                            -InternalLoadBalancerName $ILBName `
                            | Update-AzureVM

    $i += 1
} 
