<#
    This script will create a new VM. All required input variables can be inputted under
    the User-Defined Variables section.

    This script uses Azure PowerShell version 1.0.1

    Before using this script, make sure to log into your Azure Resource Manager account
    by using the command:
        Login-AzureRmAccount
#>


###########################
# User-Defined Variables
###########################

# Global
$ResourceGroupName = "computeRG"
$Location = "EastUS"

# Network
$InterfaceName = "azbackupnew3"
$VNetName = "testVnet1"

# Compute
$VMName = "AzbackupNew3"
$ComputerName = "AzbackupNew3"
$VMSize = "Standard_DS1"
$OSDiskName = $VMName
$OSDiskUri = "https://teststor.blob.core.windows.net/vhds/testVM1.vhd"

###########################
# Networking configuration
###########################

# Create a new public IP address only if one doesn't yet exist with the name $InterfaceName
try 
{
    $PIp = Get-AzureRmPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $InterfaceName

    Write-Host "Azure Public IP address with the name " $InterfaceName " already exists in Resource Group " `
                $ResourceGroupName "."
}
catch [Hyak.Common.CloudException] 
{
    <#
        This catch block executes when a public IP address with name $InterfaceName in
        Resource Group #ResourceGroupName is not found.
        This block will create a new public IP address.
    #>

    # Create new public IP address
    $PIp = New-AzureRmPublicIpAddress -Name $InterfaceName -ResourceGroupName $ResourceGroupName `
                                      -Location $Location -AllocationMethod Dynamic
}


# Get the virtual network in which to place the VM.
try
{
    $VNet = Get-AzureRmVirtualNetwork -Name $VNetName -ResourceGroupName networkingRG #CHANGE THIS
}
catch [Hyak.Common.CloudException] 
{
    Write-Host "The VNet by name " $VNetName " does not exist in Resource Group " $ResourceGroupName `
                ". The script will now terminate."
    Throw "Error: Virtual Network does not exist"

}

# Create a new NIC only if one doesn't yet exist with the name $InterfaceName
try 
{
    $Interface = Get-AzureRmNetworkInterface -ResourceGroupName $ResourceGroupName -Name $InterfaceName

    Write-Host "Network Interface Controller (NIC) with the name " $InterfaceName " already exists in Resource Group " `
                $ResourceGroupName "."
}
catch [Hyak.Common.CloudException] 
{
    <#
        This catch block executes when a NIC with name $InterfaceName in
        Resource Group #ResourceGroupName is not found.
        This block will create a new Network Interface Controller.
    #>

    # Create new public IP address
    $Interface = New-AzureRmNetworkInterface -Name $InterfaceName -ResourceGroupName $ResourceGroupName `
                                            -Location $Location -SubnetId $VNet.Subnets[0].Id `
                                            -PublicIpAddressId $PIp.Id
}


###########################
# Computing configuration
###########################

# Setup local VM object
$VirtualMachine = New-AzureRmVMConfig -VMName $VMName -VMSize $VMSize 
$VirtualMachine = Add-AzureRmVMNetworkInterface -VM $VirtualMachine -Id $Interface.Id
$VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -Name $OSDiskName -VhdUri $OSDiskUri -CreateOption Attach -Windows

# Create the VM in Azure
New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VirtualMachine