Function DeployAttachVHD
{
 
param([string] $ResourceGroupName,
        [string] $VNetResourceGroupName,
              [string] $Location,
              [string] $VNetName,
              [string] $SubnetName,
              [string] $InterfaceName,
              [string] $VMName,
              [string] $ComputerName,
              [string] $VMSize,
              [string] $OSDiskUri,
              [switch] $PublicIP,
              [string] $AvailabilitySetName
              )
 
 
 
 
$OSDiskName = $VMName
 
 
# Network
#$PIp = New-AzurePublicIpAddress -Name $InterfaceName -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Dynamic
$VNet = Get-AzureRmVirtualNetwork -Name $VNetName -ResourceGroupName $VNetResourceGroupName
 
if ($VNet )
{
    $Subnet = $VNet.Subnets | where { $_.Name -eq $SubnetName } 
 
    if ( $Subnet )
    {
        $Interface = New-AzureRmNetworkInterface -Name $InterfaceName -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $Subnet.Id ##-PublicIpAddressId $PIp.Id
        ## Setup local VM object
        #$Credential = Get-Credential
 
        if ( $AvailabilitySetName )
        {
            $av = Get-AzureRmAvailabilitySet -Name $AvailabilitySetName -ResourceGroupName $ResourceGroupName
 
            if ( $av )
            {
                 $VirtualMachine = New-AzureRmVMConfig -VMName $VMName -VMSize $VMSize -AvailabilitySetId $av.Id
                ##$VirtualMachine = Set-AzureVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $ComputerName -ProvisionVMAgent -EnableAutoUpdate
                $VirtualMachine = Add-AzureRmVMNetworkInterface -VM $VirtualMachine -Id $Interface.Id
                $VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -Name $OSDiskName -VhdUri $OSDiskUri -CreateOption Attach -Windows
 
                ## Create the VM in Azure
                New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VirtualMachine
            }
        }
        else
        {
 
            $VirtualMachine = New-AzureRmVMConfig -VMName $VMName -VMSize $VMSize 
            ##$VirtualMachine = Set-AzureVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $ComputerName -ProvisionVMAgent -EnableAutoUpdate
            $VirtualMachine = Add-AzureRmVMNetworkInterface -VM $VirtualMachine -Id $Interface.Id
            $VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -Name $OSDiskName -VhdUri $OSDiskUri -CreateOption Attach -Windows
 
            ## Create the VM in Azure
            New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VirtualMachine
 
        }
 
    }
}
#
<#
# Compute
 
 
 
#>
 
}
 

$VMName="placeholder"
$VMNicName = $VMName+ "-Nic1"
$VMResourceGroup= "placeholder"
$VNetResourceGroup="placeholder"
$VNetName="placeholder"
$Location = "East US2"
$Subnet = "placeholder"
$OSDiskURI = "https://teststorage.blob.core.windows.net/vhds/testvhd.vhd"
#$AvailabilitySet="placeholder"
$AvailabilitySet="placeholder"
$VMSize = "Standard_DS4"
 
#New-AzureRmAvailabilitySet -ResourceGroupName $VMResourceGroup -Name $AvailabilitySet -Location $Location
 
DeployAttachVHD -VNetResourceGroupName $VNetResourceGroup -VNetName $VNetName -SubnetName $Subnet -ResourceGroupName $VMResourceGroup -Location $Location -InterfaceName $VMNicName -VMName $VMName -ComputerName $VMName -VMSize $VMSize  -OSDiskUri $OSDiskURI -AvailabilitySetName $AvailabilitySet 
