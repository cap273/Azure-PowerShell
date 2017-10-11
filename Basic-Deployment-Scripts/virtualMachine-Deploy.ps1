<#

.NAME
	virtualMachine-Deploy
	
.DESCRIPTION 
    Creates an ARM template to deploy several Virtual Machines (VMs) in an existing VNet and in existing storage account(s).

    This script only deploys single-NIC VMs.

    For VMs to be placed in the same availability set, this script will place each VM's disks in separate storage accounts.
    See the parameter descriptions for availabilitySetName, storageAccountName, and storageAccountBaseName for details.



.PARAMETER subscriptionName
	Name of the subscription in which to deploy the ARM template.

.PARAMETER deploymentName
    Name of the ARM template deployment. This name is only useful for debugging purposes, and can be set to anything.

.PARAMETER location
    The location in which to deploy these VMs.



.PARAMETER vnetResourceGroupName
    The resource group name in which the Virtual Network is located.

.PARAMETER virtualNetworkName
    The name of the virtual network in which to deploy the VMs.

.PARAMETER subnetName
    The name of the subnet in which to deploy VMs.




.PARAMETER availabilitySetName
    The name of the availability set in which to deploy VMs.

    If an availability set by the selected name does not already exist,
    one will be created.

    If left empty or $null, VMs will NOT be placed in an availability set.

    Note that VMs may ONLY be placed in an availability set at the time of provisioning.

.PARAMETER storageAccountName
    Name of the storage account in which to place the OS disks (and optionally) data disks of the VMs
    to be provisioned.

    This parameter is ONLY valid IF $availabilitySetName is $null or empty.
    That is, the disks of multiple identical VMs will only be placed in the same
    storage account if the VMs are not going to be part of an availability set.
    In case $availabilitySetName is NOT $null, see description for parameter $storageAccountBaseName

    The name of the storage account must be globally unique.

    This script currently assumes that the storage account is in the same resource group
    as the VMs to be provisioned.

.PARAMETER storageAccountBaseName
    Base name of the storage accounts in which to place OS (and optionally) data disks of the VMs.

    This parameter is ONLY valid IF $availabilitySetName is set to a value that is NOT $null or empty.
    That is, if VMs will be placed in an availability group, this script will force that VMs'
    disks to be placed in separate storage accounts. The storage account names will be in
    the following format:
    - <storageAccountBaseName><Two Digit Index>

    For example, if $storageAccountBaseName = "teststorageaccount", $numberVmsToDeploy = 3, 
    and $storageAccountStartIndex = 2, the three storage account names to be used will be:
    - teststorageaccount02
    - teststorageaccount03
    - teststorageaccount04

    The name of the storage account(s) must be globally unique.

    This script currently assumes that the storage account(s) are in the same resource group
    as the VMs to be provisioned.

.PARAMETER storageAccountStartIndex
    An integer that describes the first index to use when building the names of storage accounts
    to use for VMs in an availability set. See description for $storageAccountBaseName parameter.

.PARAMETER storageAccountsPerAvailabilitySet
    The maximum number of storage accounts to use in a single availability set.
    If 7 VMs are going to be deployed in an availability set, the disks of those 7 VMs will be distributed
    across the number of storage accounts specified by $storageAccountsPerAvailabilitySet.

    For example, if the parameter $availabilitySetName is not null or blank, and:
    $numberVmsToDeploy = 7
    $storageAccountBaseName = 'teststorageaccount'
    $storageAccountStartIndex = 2
    $storageAccountsPerAvailabilitySet = 4

    Then the following storage accounts names to be used will be:
    - teststorageaccount02 [will hold the disks of VM #1 and #5]
    - teststorageaccount03 [will hold the disks of VM #2 and #6]
    - teststorageaccount04 [will hold the disks of VM #3 and #7]
    - teststorageaccount05 [will hold the disks of VM #4]



.PARAMETER numberDataDisks
    The number of data disks to be provisioned and assigned to each VM. May be set to 0.
    This script currently only provisions standard data disks.

.PARAMETER sizeDataDisksGiB
    The size of the data disks to be provisioned, in gibibyte (GiB)
    May be ignored if no data disks are to be provisioned.

.PARAMETER caching
    Sets the caching preference for the data disks to be deployed.
    Does NOT affect the caching preference of the OS disk.

.PARAMETER dataDisksInSameStorageAccountAsOSDisk
    A boolean. If $true, and $numberDataDisks > 0, then the data disks for each VM will be placed in
    the same storage account as that VM's OS disk.

    If $false, each VM's data disk will be placed in the storage accounts as specified by the parameters:
    - $dataDiskStorageAccountName [if VMs to be deployed are NOT in an availability set]
    - $dataDiskStorageAccountBaseName & $dataDiskStorageAccountStartIndex [If VMs to be deployed WILL BE IN availability set]

    When using availability sets, the number of different storage accounts through which to distribute data disks will not exceed $storageAccountsPerAvailabilitySet




.PARAMETER publicIPAddress
    If $true, add a public IP address to the NIC of the VM to deploy.
    The public IP address will be dynamically allocated.

.PARAMETER staticPrivateIP
    A boolean. If set to $true, the private IP address of the NIC assigned to each VM
    will be set to Static.

    Note that private IP addresses in Azure, even if they are Dynamic, will NOT change
    unless the VM is deallocated.

.PARAMETER useAzureDHCP
    If $staticPrivateIP = $true, and $useAzureDHCPh = $true, the DHCP functionality in Azure will
    dynamically assign private IP addresses, and afterwards the assigned private IP addresses will be
    set to 'Static'.

    If $staticPrivateIP = $true, and $useAzureDHCPh = $false, the DHCP functionality in Azure will not
    be used to assign IP addresses. Instead, the VMs to be deployed will be assigned static IP addresses
    according to the list of IP addresses specified in $listPrivateIPAddresses.

.PARAMETER listPrivateIPAddresses
    If $useAzureDHCP = $false and $staticPrivateIP = $true, $listPrivateIPAddresses is either an array,
    or a path to a CSV file, containing the list of private IP addresses to statically assign to the VMs to
    be deployed.

    If three VMs are to be provisioned (e.g. testVMName01,testVMName02,testVMName03), the IP addresses listed in 
    $listPrivateIPAddresses will be sequentially assigned.

    E.g. $listPrivateIPAddresses = @("10.0.0.4","10.0.0.5","10.0.0.6")

    E.g. $listPrivateIPAddresses = "C:\listIPAddresses.csv", where listIPAddresses.csv is a CSV file of a single
    column with 1) a header of any kind in the first row, and 2) a list of IP addresses in rows 2 through N.



.PARAMETER nicNamePrefix
    Defines the prefix to be assigned to the name of the NIC assigned to each VM. This parameter may be left blank.
    Naming format for the NIC of each VM:
    <$nicNamePrefix><vmName><$nicNamesSuffix>

    Example: if $virtualMachineBaseName = "testVMName", $nicNamePrefix = "VM-", and $nicNamesSuffix = "-NIC-01", and 
            numberVmsToDeploy = 3, then the names of the single NIC assigned to each respective VM would be:
            - "VM-testVMName01-NIC-01"
            - "VM-testVMName02-NIC-01"
            - "VM-testVMName03-NIC-01"

.PARAMETER nicNamesSuffix
    Defines the suffix to be assigned to the name of the NIC assigned to each VM. This parameter may be left blank.
    Naming format for the NIC of each VM:
    <$nicNamePrefix><vmName><$nicNamesSuffix>

    Example: if $virtualMachineBaseName = "testVMName", $nicNamePrefix = "VM-", and $nicNamesSuffix = "-NIC-01", and 
            numberVmsToDeploy = 3, then the names of the single NIC assigned to each respective VM would be:
            - "VM-testVMName01-NIC-01"
            - "VM-testVMName02-NIC-01"
            - "VM-testVMName03-NIC-01"




.PARAMETER vmResourceGroupName
    The name of the resource group in which to deploy VMs and their respective NICs.

.PARAMETER virtualMachineBaseName
    Base name of the VMs to be deployed, before indexing.

    Example: if $virtualMachineBaseName = 'testVMName' and the number
    of VMs to be deployed is 3, and $virtualMachineStartIndex = 1, the names of the VMs to be deployed will be:
    - testVMName01
    - testVMName02
    - testVMName03

    $virtualMachineBaseName must be 13 characters or less to accomodate indexing
    and the maximum VM name of 15 characters, as set by Azure.
    
.PARAMETER numberVmsToDeploy
    The number of identical VMs to deploy.

.PARAMETER virtualMachineStartIndex
    The starting index of the VM names.

    Example: if $virtualMachineBaseName = 'testVMName' and the number
    of VMs to be deployed is 3, and $virtualMachineStartIndex = 3, the names of the VMs to be deployed will be:
    - testVMName03
    - testVMName04
    - testVMName05

.PARAMETER createFromCustomImage
    A boolean. If $true, the VM will be provisioned from a user-uploaded custom image.
    The VHD holding this custom image will be specified by $imageUrl

.PARAMETER imageUrl
    The URL of the VHD holding the user-uploaded custom image from which to provision VMs.
    This parameter is only required if $createFromCustomImage = $true.

    The storage account in which this VHD (not VHDX) is located must be the same as the storage account
    in which the VM OS disks will be created. If it is not, this script will begin a copy operation
    to copy the VHD from its original storage account to all target storage accounts.

    E.g. $imageUrl = "https://teststorageaccount.blob.core.windows.net/customimages/vmbaseimage123.vhd"

.PARAMETER osName
    Name of the operating system to install on the VM.
    For Windows Server 2012 R2, set value to 'W2K12R2'
    The list of OS Image properties (i.e PublisherName, Offer, & SKU) are defined
    in a hashtable in the variable $osList. If additional OS images are required as options, add 
    them to the $osList hashtable

.PARAMETER vmSize
    Size of the VM to deploy. E.g. "Standard_A1"
    Use the cmdlet Get-AzureRmVMSize to get the list of VM sizes.

.PARAMETER username
    Name of the user for the local administrator account of the VM.

.PARAMETER password
    Password of the local administrator account of the VM.
    If left blank or $null, a random password will be generated and outputted to the console.
    The supplied password must be between 8-123 characters long and must satisfy at least 3 of password complexity requirements from the following:
        - 1) Contains an uppercase character
        - 2) Contains a lowercase character
        - 3) Contains a numeric digit
        - 4) Contains a special character

.PARAMETER vmTags
    Tags to be applied to the NICs and VMs to be deployed. A hashtable of key-value pairs.




.PARAMETER useVmDiagnostics
    A boolean. If $true, the VM extension Microsoft.Azure.Diagnostics.IaaSDiagnostics will be installed
    on Windows VM using default settings. The same storage account in which the VM is deployed will be used
    as the storage account for the VM extension files.

    Enabling VM diagnostics for Linux VMs programmatically is currently not supported.
    Reference: https://github.com/Azure/azure-linux-extensions/tree/master/Diagnostic

.PARAMETER useDiagnosticsCustomStorageAccount
    A boolean. If $true, all VM diagnostics files will be placed in a single storage account specified by the parameter
    $customStorageAccountForDiagnostics. If $false, the VM diagnostics files for each VM will be placed in the same storage
    account as that VM's disks.

.PARAMETER customStorageAccountForDiagnostics
    The name of the storage account in which to place all VM diagnostics files. This parameter is ONLY required
    when $useDiagnosticsCustomStorageAccount = $true.

.PARAMETER vmDiagnosticsStorageKey
    The key for the storage account specified by $customStorageAccountForDiagnostics. This is an OPTIONAL parameter, even if 
    $useDiagnosticsCustomStorageAccount = $true. If $vmDiagnosticsStorageKey is left $null or blank, the storage account key will
    be retrieved programatically. The success or failure of this operation will depend on the user's permissions in the target Azure
    subscription (that is, the storage account key will be retrieved only if the user has sufficient access permissions to the storage account).


.PARAMETER joinToDomain
    A boolean. If $true, the Windows VM will be joined to an Active Directory domain using the extension
    JsonADDomainExtension.

    The script will prompt for the credentials for a user or service account with permissions to join the VM to the domain.
    These credentials will NOT be stored locally.

.PARAMETER adDomain
    The Active Directory domain to which to join the VMs to be deployed.

    E.g. $adDomain = 'cloud.contoso.com'

.PARAMETER adDomainOU
    The Organizational Unit (OU) in which to place the VMs when being joined to the domain.
    Specify the OU using its Distinguished Name: https://msdn.microsoft.com/en-us/library/aa366101(v=vs.85).aspx


    E.g. $adDomainOU = 'OU=Clients,DC=Cloud,DC=Contoso,DC=com'



.PARAMETER useCustomScriptExtension
    A boolean. If $true, the VM extension Microsoft.Compute.CustomScriptExtension (for Windows VMs) or
    the VM extension Microsoft.OSTCExtensions.CustomScriptForLinux (for Linux VMs) will be deployed.

.PARAMETER customScriptExtensionStorageAccountResourceGroup
    The resource group of the storage account in which the scripts to be executed through Custom Script Extension are located.

.PARAMETER customScriptExtensionStorageAccountName
    The name of the storage account in which the scripts to be executed through Custom Script Extension are located.

.PARAMETER customScriptExtensionStorageKey
    The key of the storage account in which the scripts to be executed through Custom Script Extension are located.

    This is an OPTIONAL parameter. If $customScriptExtensionStorageKey is left blank or null, the script will attempt to
    automatically retrieve the storage account key. This operation will only work if 1) the storage account is in the same
    subscription as the subscription in which the VMs are being deployed, and 2) the user running this script has sufficient
    permissions to access the key of the storage account.

.PARAMETER fileUris
    An array of strings, where each string is the URI of a file to be downloaded into the target VMs through Custom Script Extension.

    This parameter does NOT NECESSARILY contain the URIs of the scripts that will be EXECUTED. The files contained in this parameter
    describe only the files that will be DOWNLOADED. The script execution depends on the parameter $commandToExecute.

    Example: $fileUris = @('https://teststorageaccount.blob.core.windows.net/scripts/testScript.ps1',
                           'https://teststorageaccount.blob.core.windows.net/scripts/supportingFile.csv'),

.PARAMETER commandToExecute
    The command to execute through Custom Script Extension.

    Example for a Windows VM: $commandToExecute = 'powershell -ExecutionPolicy Unrestricted -File testScript.ps1 -reboot test'

    In this example, we are executing the script 'testScript.ps1' (which was specified as a file to download in $fileUris).
    We are also passing the value 'test' to the parameter called 'reboot'.
    And we are setting the Execution Policy of the PowerShell session that is going to run the command as 'Unrestricted'


.NOTES
    AUTHOR: Carlos Patiño, Anika Dhamodharan
    LASTEDIT: December 5, 2016

FUTURE ENHANCEMENTS
- Allow for BYOL image SKUs
#>

param (
    
    #######################################
    # Azure and ARM template parameters
    #######################################
    [string] $subscriptionName = 'Visual Studio Enterprise with MSDN',
    [string] $deploymentName = 'VMDeployment-1',

    [ValidateSet("Central US", "East US", "East US 2", "West US", "North Central US", "South Central US", "West Central US", "West US 2")]
    [string] $location = 'South Central US',


    #######################################
    # Virtual Network parameters
    #######################################
    [string] $vnetResourceGroupName = 'RG-Networking-SCUS',
    [string] $virtualNetworkName = 'Personal-Network',
    [string] $subnetName = 'SubnetFront',


    #######################################
    # Availability Set & OS Disk Storage
    #######################################
    [string] $availabilitySetName = 'avset-scus',

    # If VMs are NOT in availability set, all disks placed in storage account specified by $storageAccountName. See parameter descriptions above for details.
    [string] $storageAccountName,

    # If VMs WILL BE IN availability set, each VMs disk(s) are placed in separate, sequentially-named storage accounts specified by $storageAccountBaseName and $storageAccountStartIndex.
    # See parameter descriptions above for details.
    [string] $storageAccountBaseName = 'stormigrationrcarlos',
    [ValidateRange(1,99)] [int] $storageAccountStartIndex = 1,
    [int] $storageAccountsPerAvailabilitySet = 2,


    #######################################
    # Data Disks
    #######################################

    [int] $numberDataDisks = 1,
    [int] $sizeDataDisksGiB = 127,

    [ValidateSet("None", "ReadOnly", "ReadWrite")]
    [string] $caching = 'None',

    # If $true, data disks will be placed in the same storage account as VMs' OS disk
    [bool] $dataDisksInSameStorageAccountAsOSDisk = $true,

    # This parameter is only necessary if VM is NOT in availability set, $numberDataDisks > 0, and$dataDisksInSameStorageAccountAsOSDisk = $false
    [string] $dataDiskStorageAccountName,
    
    # This parameter is only necessary i VM WILL BE IN availability set, $numberDataDisks > 0, and $dataDisksInSameStorageAccountAsOSDisk = $false
    [string] $dataDiskStorageAccountBaseName,
    [ValidateRange(1,99)] [int] $dataDiskStorageAccountStartIndex,


    #######################################
    # IP configuration parameters
    #######################################

    [bool] $publicIPAddress = $true,

    # See parameter descriptions above for details on the usage of static IP addresses
    [bool] $staticPrivateIP = $false,
    [bool] $useAzureDHCP = $true,
    $listPrivateIPAddresses,


    #######################################
    # NIC naming parameters
    #######################################

    [Parameter(Mandatory=$false)] [string] $nicNamePrefix,
    [Parameter(Mandatory=$false)] [string] $nicNameSuffix = '-nic1',


    #######################################
    # VM parameters
    #######################################

    [string] $vmResourceGroupName = 'RG-TestMigrationVms-SCUS2',
    [string] $virtualMachineBaseName = 'testmigrvm',

    [ValidateRange(1,99)]
    [int] $numberVmsToDeploy = 2,

    [ValidateRange(1,99)]
    [int] $virtualMachineStartIndex = 1,

    [bool] $createFromCustomImage = $false,

    [Parameter(Mandatory=$false)]
    [string] $imageUrl,

    [ValidateSet("W2K16", "W2K12R2", "W2008R2SP1", "SQL2008-W2008-Std", "SQL2008-W2008-Ent", "SQL2012-W2K12R2-Std", "SQL2012-W2K12R2-Std", "RHEL72", "RHEL73", "Centos71","NetScaler")]
    [string] $osName = "W2K16",
    [string] $vmSize = "Standard_D1_v2",

    [string] $username,
    [string] $password,

    [hashtable] $vmTags = @{"Department" = "TestDepartment";"Owner" = "TestOwner"},

    #######################################
    # VM diagnostics parameters
    #######################################
    [bool] $useVmDiagnostics = $false,

    [bool] $useDiagnosticsCustomStorageAccount = $false,
    [Parameter(Mandatory=$false)] [string] $customStorageAccountForDiagnostics,

    # Storage key only required if the user deploying resources does not have access/permissions to the storage account. See description for details
    [Parameter(Mandatory=$false)] [string] $vmDiagnosticsStorageKey,

    #######################################
    # Join to Active Directory Domain (only relevant for Windows VMs)
    #######################################
    [bool] $joinToDomain = $false,
    [string] $adDomain,
    [string] $adDomainOU,

    #######################################
    # Post-provisioning parameters
    #######################################

    [bool] $useCustomScriptExtension = $false,

    [string] $customScriptExtensionStorageAccountResourceGroup,
    [string] $customScriptExtensionStorageAccountName,

    # Storage key only required if user deploying resources does not hace access/permissions to the storage account. See description for details
    [Parameter(Mandatory=$false)] [string] $customScriptExtensionStorageKey,

    [string[]] $fileUris,

    [string] $commandToExecute
)



###################################################
# region: PowerShell and Azure Dependency Checks
###################################################
cls
[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
$ErrorActionPreference = 'Stop'

Write-Host "Checking Dependencies..."

# Check for the directory in which this script is running.
# Certain files (the ARM template in JSON, and an output CSV file) will be saved in this directory.
if ( [string]::IsNullOrEmpty($PSScriptRoot) ) {
    throw "Please save this script before executing it."
}

# Checking for Windows PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 4) {
    Write-Host "You need to have Windows PowerShell version 4.0 or above installed." -ForegroundColor Red
    Exit -2
}

# Checking for Azure PowerShell module
$modlist = Get-Module -ListAvailable -Name 'AzureRM.Storage'
if (($modlist -eq $null) -or ($modlist.Version.Major -lt 2)){
    Write-Host "Please install the Azure Powershell module, version 2.0.0 (released August 2016) or above." -BackgroundColor Black -ForegroundColor Red
    Write-Host "The standalone MSI file for the latest Azure Powershell versions can be found in the following URL:" -BackgroundColor Black -ForegroundColor Red
    Write-Host "https://github.com/Azure/azure-powershell/releases" -BackgroundColor Black -ForegroundColor Red
    #Exit -2
}

# Checking whether user is logged in to Azure
Write-Host "Validating Azure Accounts..."
try{
    $subscriptionList = Get-AzureRmSubscription | Sort Name
}
catch {
    Write-Host "Reauthenticating..."
    Login-AzureRmAccount | Out-Null
    $subscriptionList = Get-AzureRmSubscription | Sort Name
}
#end region




###################################################
# region: Initializations
###################################################

# Define the properties of the possible Operating Systems with which to deploy VM.
$osList = @(
#    @{Name = 'Centos66'; Publisher = 'OpenLogic'; Offer = 'CentOS'; Sku = '6.6'; OSFlavor = 'Linux' },
    @{Name = 'Centos71'; Publisher = 'OpenLogic'; Offer = 'CentOS'; Sku = '7.1'; OSFlavor = 'Linux' },
    @{Name = 'Centos72'; Publisher = 'OpenLogic'; Offer = 'CentOS'; Sku = '7.2'; OSFlavor = 'Linux' },
    @{Name = 'Centos73'; Publisher = 'OpenLogic'; Offer = 'CentOS'; Sku = '7.3'; OSFlavor = 'Linux' },
#    @{Name = 'RHEL72'; Publisher = 'RedHat'; Offer = 'RHEL'; Sku = '7.2'; OSFlavor = 'Linux' },

    @{Name = 'Ubuntu1604'; Publisher = 'Canonical'; Offer = 'UbuntuServer'; Sku = '16.04-LTS'; OSFlavor = 'Linux' },

    @{Name = 'RHEL72'; Publisher = 'RedHat'; Offer = 'RHEL'; Sku = '7.2'; OSFlavor = 'Linux' },
    @{Name = 'RHEL73'; Publisher = 'RedHat'; Offer = 'RHEL'; Sku = '7.3'; OSFlavor = 'Linux' },
    
    @{Name = 'SQL2008-W2008-Std'; Publisher = 'MicrosoftSQLServer'; Offer = 'SQL2008R2SP3-WS2008R2SP1'; Sku = 'Standard'; OSFlavor = 'Windows' }
    @{Name = 'SQL2008-W2008-Ent'; Publisher = 'MicrosoftSQLServer'; Offer = 'SQL2008R2SP3-WS2008R2SP1'; Sku = 'Enterprise'; OSFlavor = 'Windows' }
    @{Name = 'SQL2012-W2K12R2-Std'; Publisher = 'MicrosoftSQLServer'; Offer = 'SQL2012SP3-WS2012R2'; Sku = 'Standard'; OSFlavor = 'Windows' }
    @{Name = 'SQL2012-W2K12R2-Ent'; Publisher = 'MicrosoftSQLServer'; Offer = 'SQL2012SP3-WS2012R2'; Sku = 'Enterprise'; OSFlavor = 'Windows' }

    @{Name = 'W2008R2SP1'; Publisher = 'MicrosoftWindowsServer'; Offer = 'WindowsServer'; Sku = '2008-R2-SP1'; OSFlavor = 'Windows' }
    @{Name = 'W2K12R2'; Publisher = 'MicrosoftWindowsServer'; Offer = 'WindowsServer'; Sku = '2012-R2-Datacenter'; OSFlavor = 'Windows' }
    @{Name = 'W2K16'; Publisher = 'MicrosoftWindowsServer'; Offer = 'WindowsServer'; Sku = '2016-Datacenter'; OSFlavor = 'Windows' }

    @{Name = 'NetScaler'; Publisher = 'citrix'; Offer = 'netscalervpx110-6531'; Sku = 'netscalerbyol'; OSFlavor = 'MarketplacePlan' }
)
# Define the maximum number of disks in a standard storage account
# Reference: https://azure.microsoft.com/en-us/documentation/articles/storage-scalability-targets/
$maxDisksStorageAccountStandard = 40

# Define the storage account container in which to place all VM disks
$storageContainerName = 'vhds'

# Define the string to prepend and append to OS disk name
# Example name for OS disk: vd-<vmname>-os-disk, where $osDiskPrepend = 'vd-' and $osDiskAppend = "-os-disk"
# May be left empty (i.e., '')
$osDiskPrepend = 'VD-'
$osDiskAppend = '-OS-Disk'

# Define the string to prepend and append to the data disk name
# Example name for 2 data dissk: vd-<vmname>-datadisk01 and vd-<vmname>-datadisk02 , where $dataDiskPrepend = 'vd-' and $dataDiskAppend = "-datadisk"
# May be left empty (i.e., '')
$dataDiskPrepend = 'VD-'
$dataDiskAppend = '-DataDisk'

# Define the storage account container in which to copy any custom images whose
# original location is not the storage account in which VM disks will be deployed
$imageContainerName = 'customimages'

# Define the maximum allowable size of an Azure data disk, in GiB
$maxDiskSizeGiB = 1023

# Get the date in which this deployment is being executed, and add it as a Tag
$creation = Get-Date -Format MM-dd-yyyy
$creationDate = $creation.ToString()
$vmTags.Add("CreationDate", $creationDate)

# Define the length of the password to randomly generate if a password for the VM is not selected
$passwordLength = 15

# Define the location in which to store the ARM template generated for this Azure resource deployment
$jsonFilePath = Join-Path $PSScriptRoot 'armTemplate.json'

# Define the location in which to store the report generated for this Azure resource deployment
$csvfilepath = Join-Path $PSScriptRoot 'AzureVMReport.csv'

# Define function to randomly generate password
function Generate-Password{
    param($passwordlength)
    $rand = New-Object System.Random
    $NewPassword = ""
    1..$passwordlength | ForEach { $NewPassword = $NewPassword + [char]$rand.next(48,122) }
    return $NewPassword
}

#Define function to convert Bytes into Gibibytes (GiB) - 1 GiB = 2^(30) Bytes
#Truncate any decimal places
function Convert-BytesToGib{
    param($numBytes)
    return [System.Math]::Truncate($numBytes/[math]::Pow(2,30))
}
#endregion



###################################################
# region: User input validation
###################################################

Write-Host "Checking parameter inputs..."

# Check that selected Azure subscription exists.
$selectedSubscription = $subscriptionList | Where-Object {$_.Name -eq $subscriptionName}
if ($selectedSubscription -eq $null) {
    
    Write-Host "Unable to find subscription name $subscriptionName." -BackgroundColor Black -ForegroundColor Red
    Exit -2

} else {

    Select-AzureRmSubscription -SubscriptionName $subscriptionName | Out-Null
}

# Check that selected VM Resource Group exists in selected subscription.
$vmResourceGroup = Get-AzureRmResourceGroup | Where-Object {$_.ResourceGroupName -eq $vmResourceGroupName}
if ($vmResourceGroup -eq $null) {
    
    Write-Host "Unable to find resource group for Virtual Machine(s). Resource group name: $vmResourceGroupName. Subscription  name: $subscriptionName."  -BackgroundColor Black -ForegroundColor Red
    Exit -2

}

# Check that selected Virtual Network Resource Group exists in selected subscription.
$vnetResourceGroup = Get-AzureRmResourceGroup | Where-Object {$_.ResourceGroupName -eq $vnetResourceGroupName}
if ($vnetResourceGroup -eq $null) {
    
    Write-Host "Unable to find resource group for Virtual Network. Resource group name: $vnetResourceGroupName. Subscription  name: $subscriptionName." -BackgroundColor Black -ForegroundColor Red
    Exit -2

}

# Validate that the VNet already exists
$existingVnet = Get-AzureRmVirtualNetwork -ResourceGroupName $vnetResourceGroupName -Name $virtualNetworkName -ErrorAction SilentlyContinue
if ($existingVnet -eq $null) {

    Write-Host "A Virtual Network with the name $virtualNetworkName was not found in resource group $vnetResourceGroupName." -BackgroundColor Black -ForegroundColor Red
    Exit -2
}

# Validate that the subnet already exists
$existingSubnet = Get-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $existingVnet -ErrorAction SilentlyContinue
if ($existingSubnet -eq $null) {

    Write-Host "A subnet with the name $subnetName was not found in the Virtual Network $virtualNetworkName." -BackgroundColor Black -ForegroundColor Red
    Exit -2
}

# Check that, if deploying data disks and OS disks to different storage accounts, that the user input is not overlapping
if ( ($dataDisksInSameStorageAccountAsOSDisk -eq $false) -and ($numberDataDisks -gt 0) ) {
    
    if ( [string]::IsNullOrEmpty($availabilitySetName) ) {
        if ( $storageAccountName -eq $dataDiskStorageAccountName ) {
            Write-Host "Selected to use separate storage accounts for OS disks and data disks (i.e. parameter 'dataDisksInSameStorageAccountAsOSDisk' set to $dataDisksInSameStorageAccountAsOSDisk). " -BackgroundColor Black -ForegroundColor Red
            Write-Host "Storage account name parameter for both OS disks and data disks is the same." -BackgroundColor Black -ForegroundColor Red
            Write-Host "Please specify different storage account names if using separate storage accounts for OS and data disks." -BackgroundColor Black -ForegroundColor Red
            Exit -2
        }
    } else {
        if ( $storageAccountBaseName -eq $dataDiskStorageAccountBaseName ) {
            Write-Host "Selected to use separate storage accounts for OS disks and data disks (i.e. parameter 'dataDisksInSameStorageAccountAsOSDisk' set to $dataDisksInSameStorageAccountAsOSDisk). " -BackgroundColor Black -ForegroundColor Red
            Write-Host "The storage account BASE NAME parameter for both OS disks and data disks is the same." -BackgroundColor Black -ForegroundColor Red
            Write-Host "Please specify different storage account base names if using separate storage accounts for OS and data disks." -BackgroundColor Black -ForegroundColor Red
            Exit -2
        }
    }
}

# Validate that the storage account(s) already exist(s)
if ( [string]::IsNullOrEmpty($availabilitySetName) ) {

    Write-Host "`n Attempting to deploy $numberVmsToDeploy VMs that will NOT be part of an availability set.`n"
    Write-Host "Using storage account: $storageAccountName"

    # Initialize variable to correctly initialize the size of the array to hold storage accounts to use
    $numStorageAccountMultiplier = 1

    if ( ($dataDisksInSameStorageAccountAsOSDisk -eq $false) -and ($numberDataDisks -gt 0) ) {
        Write-Host "Using the following storage account for data disks: $dataDiskStorageAccountName"

        # Update variable to correctly initialize the size of the array to hold storage accounts to use
        $numStorageAccountMultiplier = 2
    }
    
    # If the VM(s) to be created will NOT be placed in an availability group, all of the VM(s) disk(s) will be placed in the same storage account.
    $existingStorageAccounts = @($null)*$numStorageAccountMultiplier
    $existingStorageAccounts[0] = Get-AzureRmStorageAccount -ResourceGroupName $vmResourceGroupName | Where-Object {$_.StorageAccountName -eq $storageAccountName}
    if ($existingStorageAccounts[0] -eq $null) {

        Write-Host "A storage account with the name $storageAccountName was not found in the resource group $vmResourceGroupName." -BackgroundColor Black -ForegroundColor Red
        
        if ([string]::IsNullOrEmpty($storageAccountName)) {
            Write-Host "If not using availability sets, please specify the name of an existing storage account in parameter 'storageAccountName'" -BackgroundColor Black -ForegroundColor Red
        }
        
        Exit -2
    }

    if ( ($dataDisksInSameStorageAccountAsOSDisk -eq $false) -and ($numberDataDisks -gt 0) ) {
        # Handle the case in which (1) data disks are being created and (2) those data disks will not be in the same
        # storage account as the OS disks

        $existingStorageAccounts[1] = Get-AzureRmStorageAccount -ResourceGroupName $vmResourceGroupName | Where-Object {$_.StorageAccountName -eq $dataDiskStorageAccountName}
        if ($existingStorageAccounts[1] -eq $null) {

            Write-Host "A storage account with the name $dataDiskStorageAccountName was not found in the resource group $vmResourceGroupName." -BackgroundColor Black -ForegroundColor Red
            
            if ([string]::IsNullOrEmpty($dataDiskStorageAccountName)) {
                Write-Host "If not using availability sets, please specify the name of an existing storage account in parameter 'dataDiskStorageAccountName'" -BackgroundColor Black -ForegroundColor Red
            }
            
            Exit -2
        }
    } else {
        # If OS disks and any data disks will be placed in the same storage account, simply
        # set the corresponding storage account variables for data disks to be the same
        # as the OS disk storage account variables

        $dataDiskStorageAccountName = $storageAccountName
    }
    
} else {

    # If the VM(s) to be created WILL be placed in an availability group, each VMs' disks will be placed in a separate storage account

    Write-Host "`nAttempting to deploy $numberVmsToDeploy VMs in the availability set $availabilitySetName."

    if ( ($dataDisksInSameStorageAccountAsOSDisk -eq $false) -and ($numberDataDisks -gt 0) ) {

        Write-Host "Each VM will have $numberDataDisks data disk(s) that will NOT share the same storage account as the VM's OS disk."
        Write-Host "The OS disks of the VMs to be deployed will be distributed across a maximum of $storageAccountsPerAvailabilitySet storage accounts."
        Write-Host "The data disks of the VMs to be deployed will be distributed across a maximum of $storageAccountsPerAvailabilitySet storage accounts, which will be different from the OS disks' storage accounts.`n"

    } elseif ($numberDataDisks -gt 0) {

        Write-Host "Each VM will have $numberDataDisks data disk(s) which will be placed in the SAME storage account as the VM's OS disk."
        Write-Host "Each VMs' OS disks and data disks will be distributed across a maximum of $storageAccountsPerAvailabilitySet storage accounts.`n"

    } else {
        Write-Host "No data disks are being created."
        Write-Host "The VMs' OS disks will be distributed across a maximum of $storageAccountsPerAvailabilitySet storage accounts.`n"
    }
    
    Write-Host "Using the following storage accounts:"

    # Calculate number of storage accounts to use
    # Number of storage accounts to use will not exceed the number of storage accounts per availability set, as specified in this deployment script
    $numStorageAccountsToUse = [Math]::Min($numberVmsToDeploy,$storageAccountsPerAvailabilitySet)

    # Output storage account names to console
    $j = $storageAccountStartIndex
    for ($i = 0; $i -lt $numStorageAccountsToUse;$i++) {

        # Get the expected storage account name
        $tempStorageAccountName = $storageAccountBaseName + $j.ToString("00")
        $j++

        Write-Host "$tempStorageAccountName"
    }

    # Output storage account names of data disks (if applicable) to console, and perform some variable initialization
    if ( ($dataDisksInSameStorageAccountAsOSDisk -eq $false) -and ($numberDataDisks -gt 0) ) {
        # Handle the case in which (1) data disks are being created and (2) those data disks will not be in the same
        # storage account as the OS disks

        if ( [string]::IsNullOrEmpty($dataDiskStorageAccountBaseName) ) {
            Write-Host "The parameter 'dataDiskStorageAccountBaseName' is empty or null. Please input the base name of the storage accounts to be used for the VM data disks." -BackgroundColor Black -ForegroundColor Red
            Exit -2
        }

        Write-Host "Using the following storage accounts only for data disks:"

        # Output storage account names for data disks to console
        $j = $dataDiskStorageAccountStartIndex
        for ($i = 0; $i -lt $numStorageAccountsToUse;$i++) {

            # Get the expected storage account name
            $tempStorageAccountName = $dataDiskStorageAccountBaseName + $j.ToString("00")
            $j++

            Write-Host "$tempStorageAccountName"
        }

        # Update variable to correctly initialize the size of the array that will contain the storage accounts to use
        $numStorageAccountMultiplier = 2

    } else {
        # If OS disks and any data disks will be placed in the same storage account, simply
        # set the corresponding storage account variables for data disks to be the same
        # as the OS disk storage account variables

        # Initialize variable to correctly initialize the size of the array to hold storage accounts to use
        $numStorageAccountMultiplier = 1

        $dataDiskStorageAccountBaseName = $storageAccountBaseName
        $dataDiskStorageAccountStartIndex = $storageAccountStartIndex
    }

    # Initialize array to hold all expected storage accounts
    $existingStorageAccounts = @($null)*$numStorageAccountsToUse*$numStorageAccountMultiplier
    
    # Initialize counter for the index of the storage accounts
    $j = $storageAccountStartIndex

    # Loop through each (expected) storage account
    for ($i = 0; $i -lt $numStorageAccountsToUse;$i++) {

        # Get the expected storage account name
        $tempStorageAccountName = $storageAccountBaseName + $j.ToString("00")

        # Get the expected storage account and store in array
        $existingStorageAccounts[$i] = Get-AzureRmStorageAccount -ResourceGroupName $vmResourceGroupName | Where-Object {$_.StorageAccountName -eq $tempStorageAccountName}
        
        # Throw an error if the expected storage account does not exist
        if ($existingStorageAccounts[$i] -eq $null) {
            
            Write-Host "A storage account with the name $tempStorageAccountName was not found in the resource group $vmResourceGroupName." -BackgroundColor Black -ForegroundColor Red
            Exit -2
        }

        # Update storage account index counter
        $j++
    }

    # Add the storage accounts FOR DATA DISKS to (expected) storage account lists
    if ( ($dataDisksInSameStorageAccountAsOSDisk -eq $false) -and ($numberDataDisks -gt 0) ) {
        # Handle the case in which (1) data disks are being created and (2) those data disks will not be in the same
        # storage account as the OS disks

        # Initialize counter for the index of the storage accounts
        $j = $dataDiskStorageAccountStartIndex

        $prevNumStorageAccounts = ($existingStorageAccounts | Measure).Count

        # Loop through each (expected) storage account
        for ($i = $prevNumStorageAccounts; $i -lt ($numStorageAccountsToUse+$prevNumStorageAccounts);$i++) {

            # Get the expected storage account name
            $tempStorageAccountName = $dataDiskStorageAccountBaseName + $j.ToString("00")

            # Get the expected storage account and store in array
            $existingStorageAccounts[$i] = Get-AzureRmStorageAccount -ResourceGroupName $vmResourceGroupName | Where-Object {$_.StorageAccountName -eq $tempStorageAccountName}
        
            # Throw an error if the expected storage account does not exist
            if ($existingStorageAccounts[$i] -eq $null) {
            
                Write-Host "A storage account with the name $tempStorageAccountName was not found in the resource group $vmResourceGroupName." -BackgroundColor Black -ForegroundColor Red
                Exit -2
            }

            # Update storage account index counter
            $j++
        }
    } #End if-statement for data disks in different storage accounts
}

# If an availability set is required, AND the availability set already exists, verify that the size of the selected VM can be deployed in the existing availability set
if (  !([string]::IsNullOrEmpty($availabilitySetName)) ) {
    $existingAvailabilitySet = Get-AzureRmAvailabilitySet -ResourceGroupName $vmResourceGroupName -AvailabilitySetName $availabilitySetName -ErrorAction SilentlyContinue
    if ($existingAvailabilitySet) {

        # Gets available sizes for virtual machines that you can deploy in the availability set
        $validVmSizes = Get-AzureRmVMSize -ResourceGroupName $vmResourceGroupName -AvailabilitySetName $availabilitySetName

        # Raise an error if the selected VM size is not in the list of allowable VM sizes for this existing availability set
        if ( !($validVmSizes | Where-Object {$_.Name -eq $vmSize} ) ) {
            
            Write-Host "The selected VM size $vmSize cannot be deployed in existing availability set $availabilitySetName." -BackgroundColor Black -ForegroundColor Red
            Exit -2
        }
    }
}

# Check that the length of the VM name is 13 characters of less.
# The maximum absolute length of the VM name is 15 characters - allow the last 2 characters for the VM index (e.g. 'baseVMName01', 'baseVMName02')
if ($virtualMachineBaseName.Length -gt 13) {

    Write-Host "Ensure that the base name of the VM is 13 characters or less." -BackgroundColor Black -ForegroundColor Red
    Write-Host "Since the maximum length of a VM name is 15 characters, this requirements allow for two characters for the indexing of the VM name (e.g. 'baseVMName01', 'baseVMName15')." -BackgroundColor Black -ForegroundColor Red
    Exit -2

}

# Check that the length the VM's local administrator username does not exceed 15 characters.
if ($username.Length -gt 13) {

    Write-Host "Ensure that the username of the VM's local administrator is 15 characters or less." -BackgroundColor Black -ForegroundColor Red
    Exit -2

}

#Validate that the index of the VMs to be deployed will not exceed 99
if (  ($virtualMachineStartIndex + $numberVmsToDeploy - 1) -gt 99 ) {
    Write-Host "You are trying to deploy $numberVmsToDeploy with a starting index for the VM names of $virtualMachineStartIndex." -BackgroundColor Black -ForegroundColor Red
    Write-Host "This script does not support deploying VM names with an index number higher than 99." -BackgroundColor Black -ForegroundColor Red
    Exit -2
}

# Check that the VMs to be deployed do not already exist
Write-Host "Virtual Machine names:"
for ($i=0; $i -lt $numberVmsToDeploy; $i++) {
    $vmNum = $i + $virtualMachineStartIndex

    $testVmName = $virtualMachineBaseName + $vmNum.ToString("00")

    $existingVm = Get-AzureRmVM -ResourceGroupName $vmResourceGroupName -Name $testVmName -ErrorAction SilentlyContinue

    if ($existingVm -ne $null) {
        Write-Host "You are trying to deploy a VM with name $testVmName in resource group $vmResourceGroupName." -BackgroundColor Black -ForegroundColor Red
        Write-Host "A Virtual Machine by that name already exists." -BackgroundColor Black -ForegroundColor Red
        Exit -2
    } else {
        Write-Host "$testVmName"
    }
}


# Validate that desired data disk size does not exceed limit and that number of requested data disks does not exceed VM size limit
if ($numberDataDisks -gt 0) {
    if ($sizeDataDisksGiB -gt $maxDiskSizeGiB) {

        Write-Host "The selected size for the data disks is $sizeDataDisksGiB. The maximum size of a data disk in Azure is $maxDiskSizeGiB." -BackgroundColor Black -ForegroundColor Red
        Exit -2

    }

    $MaxDataDiskCount = (Get-AzureRmVMSize -Location $location | Where-Object {$_.Name -eq $vmSize}).MaxDataDiskCount
    if ( !($MaxDataDiskCount) ) {

        Write-Host "The selected size for the VM $vmSize is not valid in location $location." -BackgroundColor Black -ForegroundColor Red
        Exit -2
    }

    if ( $numberDataDisks -gt $MaxDataDiskCount ) {
        
        Write-Host "Requested number of data disks: $numberDataDisks. The selected size for the VM $vmSize only supports up to $MaxDataDiskCount data disks." -BackgroundColor Black -ForegroundColor Red
        Exit -2
    }
}

# Check if using premium storage accounts
$usingPremiumStorage = $false
foreach ($existingStorageAccount in $existingStorageAccounts) {
    
    if ($existingStorageAccount.Sku.Tier -eq "Premium") {
        $usingPremiumStorage = $true
    }
}

# Premium Storage supports DS-series, DSv2-series, GS-series, and Fs-series Azure Virtual Machines (VMs).
if ($usingPremiumStorage) {
    if ( !( ($vmSize -like "Standard_DS*") -or ($vmSize -like "Standard_GS*") -or ($vmSize -like "Standard_Fs*") ) ) {
        Write-Host "At least one of the storage accounts to use are of tier 'Premium', and the selected VM size $vmSize does not support Premium Storage." -BackgroundColor Black -ForegroundColor Red
        Exit -2
    }
}

# Validate that the total number of Standard data disks to be deployed does not exceed the maximum number of disks recommended per storage account
$k = 0 # Initialize counter
foreach ($existingStorageAccount in $existingStorageAccounts) {
    # Get the context for the storage account
    $pw = Get-AzureRmStorageAccountKey -ResourceGroupName $vmResourceGroupName -Name $existingStorageAccount.StorageAccountName
    $context = New-AzureStorageContext -StorageAccountName $existingStorageAccount.StorageAccountName -StorageAccountKey $pw.Value[0] -Protocol Https

    # Get number of VHDs in deployment container
    $currentNumberOfDisks = (Get-AzureStorageBlob -Container $storageContainerName -Context $context -ErrorAction SilentlyContinue | Where-Object {$_.Name.EndsWith('vhd')}).Count

    Write-Host "Current number of disks in Storage Account $($existingStorageAccount.StorageAccountName) and Container $storageContainerName : $currentNumberOfDisks"

    # Make counter "loop back" upon reaching number of storage accounts (SA) to use WITHOUT CONSIDERING the case of separate SA for data disks
    # This "loop back" should only occur when creating separate SA for data disks
    if ($k -eq $numStorageAccountsToUse) {
        $k = 0
    }

    # Figure out number of VMs that will be leveraging current storage account (for either OS disks, data disks, or both)
    if ([string]::IsNullOrEmpty($availabilitySetName)) {
        
        # If not using an availability set, all of the VMs to deploy will be using this storage account
        $numberVMsUsingThisStorageAccount = $numberVmsToDeploy

    } else {

        # When distributing VMs across different storage accounts, formula to figure out how many VMs are using this SA
        # Example: deploying 15 VMs into 4 storage accounts. The distribution will be:
        # SA #1: 4 VMs (3 + 1)
        # SA #2: 4 VMs (3 + 1)
        # SA #3: 4 VMs (3 + 1)
        # SA #4: 3 VMs

        $baseNum = [System.Math]::Truncate($numberVmsToDeploy/$numStorageAccountsToUse)

        if ($k -lt ($numberVmsToDeploy % $numStorageAccountsToUse) ) {

            $numberVMsUsingThisStorageAccount = $baseNum + 1
        }
        else {
            $numberVMsUsingThisStorageAccount = $baseNum
        }
        
    }

    # Figure out number of disks (OS and data) to be deployed in current storage account
    if ($dataDisksInSameStorageAccountAsOSDisk -eq $true) {

        # All of the VM disks (both OS disk and data disk) will be placed in the same storage account (SA)
        $numDisksToDeploy = (1 + $numberDataDisks) * $numberVMsUsingThisStorageAccount

    }else{
                
        if ( ($existingStorageAccount.StorageAccountName -eq $dataDiskStorageAccountName) -or 
                    ($existingStorageAccount.StorageAccountName -like "$dataDiskStorageAccountBaseName*") ) {
                    
            # Current storage account will be used for all data disks, but no OS disks
            $numDisksToDeploy = $numberDataDisks * $numberVMsUsingThisStorageAccount
        }
        else {

            # Current storage account will be used for all OS disks, but no data disks
            $numDisksToDeploy = $numberVMsUsingThisStorageAccount
        }
    }

    # Raise warning and stop script if disks to be deployed exceed limit
    if ( ($currentNumberOfDisks + $numDisksToDeploy) -gt $maxDisksStorageAccountStandard ) {
    
        Write-Host "You are trying to deploy $numDisksToDeploy disks into the $($existingStorageAccount.Sku.Tier) storage account $($existingStorageAccount.StorageAccountName) that is already holding $currentNumberOfDisks disks." -BackgroundColor Black -ForegroundColor Red
        Write-Host "This would exceed the total number of disks that should be deployed in a single storage account ($maxDisksStorageAccountStandard disks). " -BackgroundColor Black -ForegroundColor Red
        Write-Host "Reference: https://azure.microsoft.com/en-us/documentation/articles/storage-scalability-targets/" -BackgroundColor Black -ForegroundColor Red
        Exit -2

    }

    # Cleanup activities to remove sensitive variables from the current PowerShell session
    Remove-Variable -Name pw
    Remove-Variable -Name context

    #Update counter
    $k++
}

# If IP addresses are to be statically assigned, check that the list of IP addresses specified is valid
if (   $staticPrivateIP -and !($useAzureDHCP)   ) {
    
    # If the input parameter is not already an array, assume it is a file path to a CSV containing the list of IP addresses
    if ( !($listPrivateIPAddresses -is [System.Array]) ) {
        
        try{
            # Import list of IP addresses from CSV file
            $ipAddressObjects = Import-Csv -Path $listPrivateIPAddresses

            # Get the header of the CSV column containing the IP addresses
            $csvHeader = (Get-Member -InputObject $ipAddressObjects[0] | Where-Object {$_.MemberType -eq 'NoteProperty'}).Name

            # Modify the $listPrivateIPAddresses array to only contain the IP address as a string
            $listPrivateIPAddresses = @($false) * $ipAddressObjects.Count
            for ($i=0;$i -lt $ipAddressObjects.Count;$i++) {
                    
                $listPrivateIPAddresses[$i] = $ipAddressObjects[$i].$csvHeader
            }

        } catch {

            $ErrorMessage = $_.Exception.Message
            
            Write-Host "The input parameter 'listPrivateIPAddresses' is not of type System.Array." -BackgroundColor Black -ForegroundColor Red
            Write-Host "Assuming it is a string containing a file path to a CSV file, attempting to import CSV file into PowerShell failed with the following error message:" -BackgroundColor Black -ForegroundColor Red
            throw "$ErrorMessage"
        }
    }

    # Precondition: $listPrivateIPAddresses is of type [System.Array]
    $numIPAddresses = ($listPrivateIPAddresses | Measure).Count
    if ( $numIPAddresses -ne $numberVmsToDeploy  ) {
        
        Write-Host "You are attempting to provision $numberVmsToDeploy VMs with statically-assigned private IP addresses." -BackgroundColor Black -ForegroundColor Red
        Write-Host "You have specified $numIPAddresses private IP addresses in the input parameter 'listPrivateIPAddresses', either as an array or as a CSV file." -BackgroundColor Black -ForegroundColor Red
        Write-Host "Ensure that the number of specified private IP addresses matches the number of VMs to deploy." -BackgroundColor Black -ForegroundColor Red
        Exit -2
    }

    Write-Host "Statically assigning the following private IP addresses:"
    $listPrivateIPAddresses

}

# Validate that user selected an allowable OS type
$image = $osList | Where-Object {$_.Name -eq $osName}
if ($image -eq $null) {

    Write-Host "The selected Operating System type $osName is not valid." -BackgroundColor Black -ForegroundColor Red
    Exit -2
}

# If using Custom Script Extension, verify that the storage account is accessible and that the storage account key can be retrieved
if ($useCustomScriptExtension) {

    # If a storage account key was NOT provided, attempt to retrieve the storage key from the account
    if ( [string]::IsNullOrEmpty($customScriptExtensionStorageKey) ) {

        # Check that the resource group of the storage account exists
        $cseResourceGroup = Get-AzureRmResourceGroup | Where-Object {$_.ResourceGroupName -eq $customScriptExtensionStorageAccountResourceGroup}
        if ($cseResourceGroup -eq $null) {
    
            Write-Host "A password for the Custom Script Extension storage account was not specified. Attempting to retrieve the storage account key requires knowing the resource group of the storage account." -BackgroundColor Black -ForegroundColor Red
            Write-Host "Unable to find resource group for Storage Account of Custom Script Extension scripts. Resource group name: $customScriptExtensionStorageAccountResourceGroup. Subscription  name: $subscriptionName." -BackgroundColor Black -ForegroundColor Red
            Exit -2

        }

        # Check that the storage account actually exists
        $cseExistingStorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $customScriptExtensionStorageAccountResourceGroup | Where-Object {$_.StorageAccountName -eq $customScriptExtensionStorageAccountName}
        if ($cseExistingStorageAccount -eq $null) {

            Write-Host "A storage account for Custom Script Extension with name $customScriptExtensionStorageAccountName was not found in the resource group $customScriptExtensionStorageAccountResourceGroup." -BackgroundColor Black -ForegroundColor Red
            Exit -2
        }

        # If a storage account key was NOT provided, attempt to retrieve the storage key from the account
        try {
            
            $customScriptExtensionStorageKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $customScriptExtensionStorageAccountResourceGroup `
                                                                             -Name $customScriptExtensionStorageAccountName).Value[0]

            # If the key was successfully acquired, that is a sufficient check to determine that current user has permissions and access to retrieve this key
            # Delete the key from this PowerShell session for security purposes, and then use the ARM template function listKeys() to get the key during the
            # execution of the ARM template deployment in Azure.
            # This prevents the storage key from being saved locally.
            $customScriptExtensionStorageKey = $null

        } catch {

            $ErrorMessage = $_.Exception.Message
            
            Write-Host "Failed to get key for storage account in which Custom Script Extension scripts are stored." -BackgroundColor Black -ForegroundColor Red
            Write-Host "If storage account is in a different subscription in which VMs are being deployed, or if RBAC rules limit user's permissions to extract storage key, manually input storage account key as a parameter." -BackgroundColor Black -ForegroundColor Red
            Write-Host "Error message:" -BackgroundColor Black -ForegroundColor Red
            throw "$ErrorMessage"
        }
    } 

    # If a storage account key was provided, check its validity
    else {

        try{
            New-AzureStorageContext -StorageAccountName $customScriptExtensionStorageAccountName `
                                    -StorageAccountKey $customScriptExtensionStorageKey `
                                    | Out-Null
        } catch {
            $ErrorMessage = $_.Exception.Message
            
            Write-Host "Failed to obtain the context of the storage account for Custom Script Extension scripts. Storage account name: $customScriptExtensionStorageAccountName" -BackgroundColor Black -ForegroundColor Red
            Write-Host "Please verify that the storage account key that was manually included as a parameter is correct." -BackgroundColor Black -ForegroundColor Red
            Write-Host "If no storage account key is specified, this script will attempt to automatically extract the storage account key. The success of this operation would depend on user and subscription permissions." -BackgroundColor Black -ForegroundColor Red
            Write-Host "Error message:" -BackgroundColor Black -ForegroundColor Red
            throw "$ErrorMessage"

        }
    }
}

# If Windows VMs are going to be joined to a domain, prompt the user the credentials of the user or service account with permissions to add VM to domain
if (  ($image.OSFlavor -eq 'Windows') -and ($joinToDomain) ) {
    
    try{
        $credential = Get-Credential

        [string] $DomainUserName = $credential.UserName
        [System.Security.SecureString] $DomainPassword = $credential.Password
    }
    catch {
        $ErrorMessage = $_.Exception.Message
    
        Write-Host "Retrieving the user or service account credentials for the Domain join operation failed with the following error message:" -BackgroundColor Black -ForegroundColor Red
        throw "$ErrorMessage"
    }
}

# If VM is being deployed from a user-uploaded custom image, validate that the VHD containing the generalized image is
# in the same storage account as the storage account in which the VMs disks will be deployed
if ($createFromCustomImage) {

    Write-Host "Ensuring that image VHD is located in the same storage account as the target storage accounts, in container $imageContainerName, for VM deployment..."

    # Check that user specified a value for the image URL
    if( [string]::IsNullOrEmpty($imageUrl) ) {
        Write-Host "If you are selecting to create a VM from a user-uploaded custom image, please specify the URL for the VHD containing the custom image." -BackgroundColor Black -ForegroundColor Red
        Write-Host "Note that the image VHD must be in the same storage account as the storage account in which the VM disks will be deployed." -BackgroundColor Black -ForegroundColor Red
        Exit -2
    }
    
    # Extract storage account in which VHD is located.
    # Method: extract any string in between "//" and ".blob"
    $imageStorageAccountName = [regex]::Match($imageUrl,"(?<=\/\/)(.*?)(?=\.blob)").Value

    # Extract the name of the VHD in which the image is stored
    # Match everything after the last "/"
    $imageName = [regex]::Match($imageUrl,"(?<=\/)[^/]*$").Value

    # Extract the name of the container in which image is stored
    # Match everything between '.net/' and '/$imageName'
    $originalImageContainerName = [regex]::Match($imageUrl,"(?<=\.net\/)(.*?)(?=\/$imageName)").Value
    
    # Verify that the storage account in which the image is located (1) exists and (2)
    # is accessible using current Azure credentials
    $imageStorageAccount = Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -eq $imageStorageAccountName}
    if ($imageStorageAccount -eq $null) {
            
        Write-Host "The URL that you specified for the custom image VHD is: $imageUrl." -BackgroundColor Black -ForegroundColor Red
        Write-Host "The storage account with the name $imageStorageAccountName was not found in subscription $subscriptionName." -BackgroundColor Black -ForegroundColor Red
        Exit -2
    }

    # Get the context of the origin storage account
    $pwImage = Get-AzureRmStorageAccountKey -ResourceGroupName $imageStorageAccount.ResourceGroupName -Name $imageStorageAccount.StorageAccountName
    $contextImage = New-AzureStorageContext -StorageAccountName $imageStorageAccount.StorageAccountName -StorageAccountKey $pwImage.Value[0] -Protocol Https

    # Intialize counter to hold number of copy operations required
    $numberCopyJobs = 0

    # Initialize an array to hold storage account contexts
    $contexts = @()

    # Loop through each storage account to be used
    # For each storage account, check that the image exists in the pre-defined container
    # for images (i.e. $imageContainerName)
    # If it does not exist, start a copy job
    foreach ($existingStorageAccount in $existingStorageAccounts) {
        
        # Get the context of the current storage account
        $pw = Get-AzureRmStorageAccountKey -ResourceGroupName $vmResourceGroupName -Name $existingStorageAccount.StorageAccountName
        $context = New-AzureStorageContext -StorageAccountName $existingStorageAccount.StorageAccountName -StorageAccountKey $pw.Value[0] -Protocol Https

        try{
            # Attempt to get the blob associated with the image VHD in the current storage account
            $imageBlob = Get-AzureStorageBlob -Blob $imageName -Container $imageContainerName -Context $context

            Write-Host "The image VHD $imageName already exists in storage account $($existingStorageAccount.StorageAccountName) and container $imageContainerName."

        } catch {

            ####################
            # If blob is not found, begin copy operation
            ####################

            Write-Host "Starting operation to copy image VHD from origin storage account $($imageStorageAccount.StorageAccountName) to destination storage account $($existingStorageAccount.StorageAccountName)..."

            # Update job counter
            $numberCopyJobs++

            # Store storage account context
            $contexts += $context

            # If the target container does not exist, create it
            $existingContainer = Get-AzureStorageContainer -Name $imageContainerName -Context $context -ErrorAction SilentlyContinue
            if ( !($existingContainer) ){
                New-AzureStorageContainer -Name $imageContainerName -Permission Off -Context $context | Out-Null
            }

            # Start the copy job
            Start-AzureStorageBlobCopy  -Context $contextImage `
                                        -SrcContainer $originalImageContainerName `
                                        -SrcBlob $imageName `
                                        -DestContext $context `
                                        -DestContainer $imageContainerName `
                                        | Out-Null

        } finally {

            # Regardless of whether image blob is found or not, delete sensitive information from current PowerShell session
            Remove-Variable -Name pw
            Remove-Variable -Name context
        }

    } # end foreach storage account

    # Delete other sensitive information
    Remove-Variable -Name pwImage
    Remove-Variable -Name contextImage

    $runningCount = $numberCopyJobs
    # Logic waiting for the jobs to complete
    while($runningCount -gt 0){
        
        # Reset counter for number of jobs still running
        $runningCount=0 
 
        # Loop through all jobs
        for ($i=0; $i -lt $numberCopyJobs; $i++) {

            # Get the status of the job
            # Get the context of the current storage account
            $jobStatus = Get-AzureStorageBlob -Container $imageContainerName -Blob $imageName -Context $contexts[$i] `
                                                | Get-AzureStorageBlobCopyState

            if(   $jobStatus.Status -eq "Pending"   ){ 
                # If the copy operation is still pending, increase the counter for number of jobs still running
                $runningCount++ 
            } 
        } 

        Write-Host "Number of copy operations still running: $runningCount. Number of total jobs: $numberCopyJobs."
         
        Start-Sleep -Seconds 30
    }

    # Delete other sensitive information
    Remove-Variable -Name contexts

    Write-Host "All copy operations complete."
}
#end region






###################################################
# region: Build ARM template
###################################################

Write-Host "Generating ARM template in JSON for VM deployment..."

# ARM template build for basic NICs and VMs
$armTemplate = @{
    '$schema' = "https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"
    parameters = @{
        adminPassword = @{
            type = "securestring"
            metadata = @{
                description = "Admin password for VM"
            }
        }
        numberOfInstances = @{
            type = "int"
            defaultValue = 1
            metadata = @{
                description = "Number of VMs to deploy"
            }
        }
    }
    variables = @{
        vnetID = "[resourceId('" + $vnetResourceGroupName + "', 'Microsoft.Network/virtualNetworks','" + $virtualNetworkName + "')]"
        OSstorageID = "[resourceId('" + $vmResourceGroupName + "', 'Microsoft.Storage/storageAccounts','" + $storageAccountName + "')]"
        subnet1Ref = "[concat(variables('vnetID'),'/subnets/" + $subnetName + "')]"
    }
    resources = @(
        @{
            apiVersion = "2015-06-15"
            type = "Microsoft.Network/networkInterfaces"
            name = "[concat('" + $nicNamePrefix + "','" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'), '" + $nicNameSuffix + "')]"
            location = $location
            tags = $vmTags
            copy = @{
                name = "nicLoop"
                count = "[parameters('numberOfInstances')]"
            }
            properties = @{
                ipConfigurations = @(
                    @{
                        name = "ipcon"
                        properties = @{
                                subnet = @{
                                    id = "[variables('subnet1Ref')]"
                            }
                        }
                    }
                )
            }
        },
        @{
            apiVersion = "2015-06-15"
            type = "Microsoft.Compute/virtualMachines"
            name = "[concat('" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'))]"
            location = $location
            tags = $vmTags
            copy = @{
                name = "virtualMachineLoop"
                count = "[parameters('numberOfInstances')]"
            }
            dependsOn = @(
                "[concat('Microsoft.Network/networkInterfaces/', '" + $nicNamePrefix + "', '" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'), '" + $nicNameSuffix + "')]"
            )
            properties = @{
                hardwareProfile = @{
                   vmSize = $vmSize
                }
                osProfile = @{
                    computerName = "[concat('" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'))]"
                    adminUsername = $username
                    adminPassword = "[parameters('adminPassword')]"
                }
                networkProfile = @{
                    networkInterfaces = @(
                        @{
                            id = "[resourceId('Microsoft.Network/networkInterfaces',concat('" + $nicNamePrefix + "','" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'), '" + $nicNameSuffix + "'))]"
                        }
                    )
                }
            }
        }
    )
}

# Ensure that the index to navigate JSON document is accurate
if ($armTemplate.resources[0].type -eq "Microsoft.Compute/virtualMachines"){
    $vmindex = 0
    $nicindex = 1
}
else{
    $vmindex = 1
    $nicindex = 0
}

# Set the private IP allocation method for the VMs' NICs
if (   $staticPrivateIP -and !($useAzureDHCP)   ) {

    #Set array of IP addresses as a variable in the JSON template
    $armTemplate['variables']['listPrivateIPAddresses'] = $listPrivateIPAddresses

    # Assign the static IP address to the NIC resource, leveraging the ARM template function copyIndex() to assign all
    # IP addresses simultaneously
    $armTemplate['resources'][$nicindex]['properties']['ipConfigurations'][0]['properties']['privateIPAddress'] = `
                "[variables('listPrivateIPAddresses')[copyIndex()]]"

    # Set IP allocation method to Static
    $armTemplate['resources'][$nicindex]['properties']['ipConfigurations'][0]['properties']['privateIPAllocationMethod'] = 'Static'

} else {

    # Set IP allocation method to Dyamic
    $armTemplate['resources'][$nicindex]['properties']['ipConfigurations'][0]['properties']['privateIPAllocationMethod'] = 'Dynamic'

}

# Modify storage profile of the VM depending on whether VM is created from a standard gallery image or from a user-uploaded custom image
if ($createFromCustomImage) {

    # Modify the location where to find VHD holding image, depending on whether VM deployment is using an availabiliy set
    # (and therefore multiple storage accounts), or no availability set and therefore only one storage account
    if ([string]::IsNullOrEmpty($availabilitySetName)) {

        $newImageUri = "[concat('http://" + $storageAccountName + "','.blob.core.windows.net/','" + $imageContainerName + "','/','" + $imageName + "')]"
             
    } else {

        $newImageUri = "[concat('http://','" + $storageAccountBaseName + "',padLeft(copyindex($storageAccountStartIndex),2,'0'),'.blob.core.windows.net/','" + $imageContainerName + "','/','" + $imageName + "')]"
    }

    $armTemplate['resources'][$vmindex]['properties']['storageProfile'] = @{
                            osDisk = @{
                                name = "[concat('" + $osDiskPrepend + "','" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'), '" + $osDiskAppend + "')]"
                                osType = $image.OSFlavor
                                caching = "ReadWrite"
                                createOption = "FromImage"
                                image =  @{
                                  uri = $newImageUri
                                }
                            }
    }
                 
} else {

    # Storage Profile if creating VM from gallery (i.e. standard) image
    $armTemplate['resources'][$vmindex]['properties']['storageProfile'] = @{
                    imageReference = @{
                        publisher = $image.Publisher
                        offer = $image.Offer
                        sku = $image.Sku
                        version = "latest"
                    }
                    osDisk = @{
                        name = "[concat('" + $osDiskPrepend + "','" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'), '" + $osDiskAppend + "')]"
                        caching = "ReadWrite"
                        createOption = "FromImage"
                    }
    }
}

# Modify the location of the OS disk
# If VM(s) will be placed in an availability set, each VMs' OS disks will be placed in a separate storage account
# Otherwise, all VMs OS disks will be placed in the same storage account
if ( [string]::IsNullOrEmpty($availabilitySetName) ) {

    $armTemplate['resources'][$vmindex]['properties']['storageProfile']['osDisk']['vhd'] = @{
                            uri = "[concat('http://" + $storageAccountName + ".blob.core.windows.net/vhds/', '" + $osDiskPrepend + "','" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'), '" + $osDiskAppend + "', '.vhd')]"
                        }
} else {

    $armTemplate['resources'][$vmindex]['properties']['storageProfile']['osDisk']['vhd'] = @{
                            uri = "[concat('http://','" + $storageAccountBaseName + "',padLeft(add(mod(copyindex(),$storageAccountsPerAvailabilitySet),$storageAccountStartIndex),2,'0'),'.blob.core.windows.net/vhds/','" + $osDiskPrepend + "', '" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'), '" + $osDiskAppend + "', '.vhd')]"
                        }
}


# Adding public IP address
if ($publicIPAddress -eq $true) {
    Write-Host "Adding public IP address..."

    # Add public IP as a dependency of the NIC
    if ($armTemplate['resources'][$nicindex]['dependsOn'] -eq $null){
        $armTemplate['resources'][$nicindex]['dependsOn'] = @()
    }
    $armTemplate['resources'][$nicindex]['dependsOn'] += "[concat('Microsoft.Network/publicIPAddresses/','" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'), 'ip1')]"

    # Associate the public IP address with its respective NIC
    $armTemplate['resources'][$nicindex]['properties']['ipConfigurations'][0]['properties']['publicIPAddress'] = @{
        id = "[resourceId('Microsoft.Network/publicIPAddresses',concat('" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'),'ip1'))]"
    }

    # Add public IP address resource to ARM template
    $armTemplate['resources'] += @{
        apiVersion = "2015-06-15"
        name = "[concat('" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'), 'ip1')]"
        type = "Microsoft.Network/publicIPAddresses"
        location = $location
        tags = $vmTags
        properties = @{
            publicIPAllocationMethod = "Dynamic"
        }
        copy = @{
                name = "publicIPLoop"
                count = "[parameters('numberOfInstances')]"
        }
    }
}

# After any possible changes to the indexes after possibly adding IP addresses, recalculate for VM index
if ($armTemplate.resources[0].type -eq "Microsoft.Compute/virtualMachines"){
    $vmindex = 0
}
elseif ($armTemplate.resources[1].type -eq "Microsoft.Compute/virtualMachines"){
    $vmindex = 1
}
else {
    $vmindex = 2
}


# Adding availability set
if ( !([string]::IsNullOrEmpty($availabilitySetName)) ){
    Write-Host "Adding Availability Set."
    $armTemplate['resources'] += @{ 
        apiVersion = "2015-06-15"
        name = $availabilitySetName
        type = "Microsoft.Compute/availabilitySets"
        location = $location
        tags = $vmTags
        properties = @{ 
            platformUpdateDomainCount = 5
            platformFaultDomainCount = 3
       }
    }

    $armTemplate['resources'][$vmindex]['dependsOn'] += "[concat('Microsoft.Compute/availabilitySets/', '" + $availabilitySetName + "')]"
    $armTemplate['resources'][$vmindex]['properties']['availabilitySet'] = @{  
        id = "[resourceId('Microsoft.Compute/availabilitySets', '" + $availabilitySetName + "')]" 
    }
}

# Adding data disks. Currently these disks are created from scratch (i.e. not from an image)
for ($i = 1; $i -le $numberDataDisks; $i++){
    Write-Host "Adding Data Disk $i"

    # JSON Schema expects the paramater that specifies the size of the data disk to be a string rather than an integer
    $sizeDataDisksGiB = $sizeDataDisksGiB.ToString()
    
    if ($armTemplate['resources'][$vmindex]['properties']['storageprofile']['dataDisks'] -eq $null){
        $armTemplate['resources'][$vmindex]['properties']['storageprofile']['dataDisks'] = @()
    }

    # Modify the location of the data disks
    # If VM(s) will be placed in an availability set, each VMs' data disks will be placed in a separate storage account
    # Otherwise, all VMs data disks will be placed in the same storage account
    if ([string]::IsNullOrEmpty($availabilitySetName)) {

        $dataDiskUri = "[concat('http://" + $dataDiskStorageAccountName + ".blob.core.windows.net/vhds/', '" + $dataDiskPrepend + "', '" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'), '" + $dataDiskAppend + "', padLeft(copyindex($i),2,'0'), '.vhd')]"
             
    } else {

        $dataDiskUri = "[concat('http://','" + $dataDiskStorageAccountBaseName + "',padLeft(add(mod(copyindex(),$storageAccountsPerAvailabilitySet),$dataDiskStorageAccountStartIndex),2,'0'),'.blob.core.windows.net/vhds/', '" + $dataDiskPrepend + "', '" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'), '" + $dataDiskAppend + "', padLeft(copyindex($i),2,'0'), '.vhd')]"
    }

    $armTemplate['resources'][$vmindex]['properties']['storageprofile']['dataDisks'] += @{
        name = "[concat('" + $dataDiskPrepend + "', '" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'), '" + $dataDiskAppend + "', padLeft(copyindex($i),2,'0'))]"
        diskSizeGB = $sizeDataDisksGiB
        lun = $i - 1
        vhd = @{
            uri = $dataDiskUri
        }
        caching = $caching
        createOption = "Empty"
    }
}


# If Marketplace item is being deployed, set the Marketplace plan information on the virtual machine
if ($image.OSFlavor -eq "MarketplacePlan") {
    
    Write-Host "Seting Marketplace plan information for product $($image.Offer)..."
    $armTemplate['resources'][$vmindex]['plan'] = @{
        name = $image.Sku
        publisher = $image.Publisher
        product = $image.Offer
    }
}

# Set VM diagnostics extension for each VM, if selected by the user
if ($useVmDiagnostics) {

    # Check if Virtual Network to which VMs are being deployed is using custom DNS servers
    # If so, throw warning advising that DNS servers must provide name resolution for storage account URLs in order
    # for VM diagnostics extension to be successfully deployed.
    $dnsServersDeployed = $existingVnet.DhcpOptions.DnsServers
    if ( !([string]::IsNullOrEmpty($dnsServersDeployed)) ) {
        Write-Host "WARNING: The Virtual Network $($existingVnet.Name) in which you are deploying these VMs is using custom DNS servers, instead of the Azure-provided DNS service." -BackgroundColor Black -ForegroundColor Yellow
        Write-Host "Please ensure that the custom DNS servers provide name resolution for Azure storage accounts, as the VM diagnostics extension requires network access to storage accounts in order to be correctly deployed." -BackgroundColor Black -ForegroundColor Yellow
        Write-Host "If name resolution for Azure storage accounts is not provided, the ARM template deployment will fail by eventually timing out." -BackgroundColor Black -ForegroundColor Yellow
    }
    
    # Modify the location of the diagnostics files
    # If VM(s) will be placed in an availability set, each VMs' data disks will be placed in a separate storage account
    # Otherwise, all VMs diagnostics files will be placed in the same storage account
    if ($useDiagnosticsCustomStorageAccount) {
        # If using a particular storage account to store all VM diagnostics (maybe a centralized storage account only for VM diagnostics data),
        # set it here.
        $storageNameForDiagnostics = $customStorageAccountForDiagnostics

        # Have ARM template acquire storage account keys at runtime using listkeys() function, unless user already manually inputted the
        # storage account key in the parameters
        if (   [string]::IsNullOrEmpty($storageKeyForDiagnostics)   ) {
            $storageKeyForDiagnostics = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', '" + $storageNameForDiagnostics + "'), '2016-01-01').keys[0].value]"
        }
        else {
            $storageKeyForDiagnostics = $vmDiagnosticsStorageKey
        }
    }
    else {
        # If not using a particular storage account, store diagnostics data on the storage account in which each VM's disks are stored.

        if ([string]::IsNullOrEmpty($availabilitySetName)) {
            # If no availability set is being used, all VMs diagnostics files will be placed in the same storage account, as the disks of all VMs will also be 
            # placed in the same storage account
            
            $storageNameForDiagnostics = $storageAccountName
            $storageKeyForDiagnostics = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', '" + $storageAccountName + "'), '2016-01-01').keys[0].value]"
        }
        else {
            # If VM(s) will be placed in an availability set, each VMs' data disks will be placed in a separate storage account
            $storageNameForDiagnostics = "[concat('" + $storageAccountBaseName + "',padLeft(add(mod(copyindex(),$storageAccountsPerAvailabilitySet),$storageAccountStartIndex),2,'0'))]"
            $storageKeyForDiagnostics = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', concat('" + $storageAccountBaseName + "',padLeft(add(mod(copyindex(),$storageAccountsPerAvailabilitySet),$storageAccountStartIndex),2,'0'))), '2016-01-01').keys[0].value]"
        }
    }

    # Adding VM diagnostics for Windows VMs
    if (  $image.OSFlavor -eq 'Windows' ) {

        Write-Host "Adding VM diagnostics for Windows VM..."

        # Define the variables needed for the default VM diagnotics configuration
        # Reference: https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-windows-extensions-diagnostics-template/#diagnostics-configuration-variables
        # In PowerShell, a double-quote character is escaped by another double-quote character.
        $vmDiagnosticsVariables = @{
                                        wadlogs = "<WadCfg> <DiagnosticMonitorConfiguration overallQuotaInMB=\""4096\"" xmlns=\""http://schemas.microsoft.com/ServiceHosting/2010/10/DiagnosticsConfiguration\""> <DiagnosticInfrastructureLogs scheduledTransferLogLevelFilter=\""Error\""/> <WindowsEventLog scheduledTransferPeriod=\""PT1M\"" > <DataSource name=\""Application!*[System[(Level = 1 or Level = 2)]]\"" /> <DataSource name=\""Security!*[System[(Level = 1 or Level = 2)]]\"" /> <DataSource name=\""System!*[System[(Level = 1 or Level = 2)]]\"" /></WindowsEventLog>"
                                        wadperfcounters1 = "<PerformanceCounters scheduledTransferPeriod=\""PT1M\""><PerformanceCounterConfiguration counterSpecifier=\""\\Processor(_Total)\\% Processor Time\"" sampleRate=\""PT15S\"" unit=\""Percent\""><annotation displayName=\""CPU utilization\"" locale=\""en-us\""/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier=\""\\Processor(_Total)\\% Privileged Time\"" sampleRate=\""PT15S\"" unit=\""Percent\""><annotation displayName=\""CPU privileged time\"" locale=\""en-us\""/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier=\""\\Processor(_Total)\\% User Time\"" sampleRate=\""PT15S\"" unit=\""Percent\""><annotation displayName=\""CPU user time\"" locale=\""en-us\""/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier=\""\\Processor Information(_Total)\\Processor Frequency\"" sampleRate=\""PT15S\"" unit=\""Count\""><annotation displayName=\""CPU frequency\"" locale=\""en-us\""/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier=\""\\System\\Processes\"" sampleRate=\""PT15S\"" unit=\""Count\""><annotation displayName=\""Processes\"" locale=\""en-us\""/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier=\""\\Process(_Total)\\Thread Count\"" sampleRate=\""PT15S\"" unit=\""Count\""><annotation displayName=\""Threads\"" locale=\""en-us\""/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier=\""\\Process(_Total)\\Handle Count\"" sampleRate=\""PT15S\"" unit=\""Count\""><annotation displayName=\""Handles\"" locale=\""en-us\""/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier=\""\\Memory\\% Committed Bytes In Use\"" sampleRate=\""PT15S\"" unit=\""Percent\""><annotation displayName=\""Memory usage\"" locale=\""en-us\""/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier=\""\\Memory\\Available Bytes\"" sampleRate=\""PT15S\"" unit=\""Bytes\""><annotation displayName=\""Memory available\"" locale=\""en-us\""/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier=\""\\Memory\\Committed Bytes\"" sampleRate=\""PT15S\"" unit=\""Bytes\""><annotation displayName=\""Memory committed\"" locale=\""en-us\""/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier=\""\\Memory\\Commit Limit\"" sampleRate=\""PT15S\"" unit=\""Bytes\""><annotation displayName=\""Memory commit limit\"" locale=\""en-us\""/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier=\""\\PhysicalDisk(_Total)\\% Disk Time\"" sampleRate=\""PT15S\"" unit=\""Percent\""><annotation displayName=\""Disk active time\"" locale=\""en-us\""/></PerformanceCounterConfiguration>"
                                        wadperfcounters2 = "<PerformanceCounterConfiguration counterSpecifier=\""\\PhysicalDisk(_Total)\\% Disk Read Time\"" sampleRate=\""PT15S\"" unit=\""Percent\""><annotation displayName=\""Disk active read time\"" locale=\""en-us\""/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier=\""\\PhysicalDisk(_Total)\\% Disk Write Time\"" sampleRate=\""PT15S\"" unit=\""Percent\""><annotation displayName=\""Disk active write time\"" locale=\""en-us\""/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier=\""\\PhysicalDisk(_Total)\\Disk Transfers/sec\"" sampleRate=\""PT15S\"" unit=\""CountPerSecond\""><annotation displayName=\""Disk operations\"" locale=\""en-us\""/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier=\""\\PhysicalDisk(_Total)\\Disk Reads/sec\"" sampleRate=\""PT15S\"" unit=\""CountPerSecond\""><annotation displayName=\""Disk read operations\"" locale=\""en-us\""/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier=\""\\PhysicalDisk(_Total)\\Disk Writes/sec\"" sampleRate=\""PT15S\"" unit=\""CountPerSecond\""><annotation displayName=\""Disk write operations\"" locale=\""en-us\""/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier=\""\\PhysicalDisk(_Total)\\Disk Bytes/sec\"" sampleRate=\""PT15S\"" unit=\""BytesPerSecond\""><annotation displayName=\""Disk speed\"" locale=\""en-us\""/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier=\""\\PhysicalDisk(_Total)\\Disk Read Bytes/sec\"" sampleRate=\""PT15S\"" unit=\""BytesPerSecond\""><annotation displayName=\""Disk read speed\"" locale=\""en-us\""/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier=\""\\PhysicalDisk(_Total)\\Disk Write Bytes/sec\"" sampleRate=\""PT15S\"" unit=\""BytesPerSecond\""><annotation displayName=\""Disk write speed\"" locale=\""en-us\""/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier=\""\\LogicalDisk(_Total)\\% Free Space\"" sampleRate=\""PT15S\"" unit=\""Percent\""><annotation displayName=\""Disk free space (percentage)\"" locale=\""en-us\""/></PerformanceCounterConfiguration></PerformanceCounters>"
                                        wadcfgxstart = "[concat(variables('wadlogs'), variables('wadperfcounters1'), variables('wadperfcounters2'), '<Metrics resourceId=\""')]"
                                        wadmetricsresourceid = "[concat('/subscriptions/', subscription().subscriptionId, '/resourceGroups/', resourceGroup().name , '/providers/', 'Microsoft.Compute/virtualMachines/')]"
                                        wadcfgxend = "\""><MetricAggregation scheduledTransferPeriod=\""PT1H\""/><MetricAggregation scheduledTransferPeriod=\""PT1M\""/></Metrics></DiagnosticMonitorConfiguration></WadCfg>"
                                    }

        # Add variables to ARM template
        foreach ($item in $vmDiagnosticsVariables.GetEnumerator()) {
            $armTemplate['variables'].Add($item.Name,$item.Value)
        }

        $armTemplate['resources'] += @{
            name = "[concat('" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'), '/','VMDiagnostics')]"
            type = "Microsoft.Compute/virtualMachines/extensions"
            location = $location
            apiVersion = "2015-06-15"
            copy = @{
                    name = "diagnosticsLoop"
                    count = "[parameters('numberOfInstances')]"
                }
            dependsOn = @(
                    "[concat('Microsoft.Compute/virtualMachines/', '" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'))]"
                )
            tags = @{
                displayName = "VMDiagnosticsWindows"
            }
            properties = @{
                publisher = "Microsoft.Azure.Diagnostics"
                type = "IaaSDiagnostics"
                typeHandlerVersion = "1.5"
                autoUpgradeMinorVersion = $true
                settings = @{
                    xmlCfg = "[base64(concat(variables('wadcfgxstart'), variables('wadmetricsresourceid'), concat('" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0')), variables('wadcfgxend')))]"
                    StorageAccount = $storageNameForDiagnostics
                }
                protectedSettings = @{
                    storageAccountName = $storageNameForDiagnostics
                    storageAccountKey = $storageKeyForDiagnostics
                    storageAccountEndPoint = "https://core.windows.net"
                }
            }
        }
    } elseif ($image.OSFlavor -eq 'Linux') {
        
        Write-Host "WARNING: Enabling VM diagnostics for Linux VMs programmatically (i.e. through ARM templates, PowerShell, or CLI) is not currently supported." -BackgroundColor Black -ForegroundColor Yellow
        Write-Host "If VM diagnostics is desired, please enable it manually on each VM through the Azure Portal." -BackgroundColor Black -ForegroundColor Yellow
        Write-Host "Reference: https://github.com/Azure/azure-linux-extensions/tree/master/Diagnostic" -BackgroundColor Black -ForegroundColor Yellow
        
        <#
        $armTemplate['resources'] += @{
            name = "[concat('" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'), '/','VMDiagnostics')]"
            type = "Microsoft.Compute/virtualMachines/extensions"
            location = $location
            apiVersion = "2015-06-15"
            copy = @{
                    name = "diagnosticsLoop"
                    count = "[parameters('numberOfInstances')]"
                }
            dependsOn = @(
                    "[concat('Microsoft.Compute/virtualMachines/', '" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'))]"
                )
            tags = @{
                displayName = "VMDiagnosticsLinux"
            }
            properties = @{
                publisher = "Microsoft.OSTCExtensions"
                type = "LinuxDiagnostic"
                typeHandlerVersion = "2.3"
                autoUpgradeMinorVersion = $true
                settings = 
                @{
                    perfCfg = 
                    @(
                        @{
                            query = "SELECT UsedMemory,AvailableMemory FROM SCX_MemoryStatisticalInformation";
                            table = "Memory"
                        }
                    )

                }
                protectedSettings = @{
                    storageAccountName = $storageNameForDiagnostics
                    storageAccountKey = $storageKeyForDiagnostics
                }
            }
        }
        #>
    }
}

# Adding Join to Domain
if (  ($image.OSFlavor -eq 'Windows') -and ($joinToDomain) ) {
    
    Write-Host "Adding Join to Domain extension..."

    # Add parameter to pass the password of the user/service account to use when adding computer to domain
    $armTemplate['parameters']['DomainPassword'] = @{
        type = "securestring"
        metadata = @{
            description = "Password for joining the domain."
        }
    }

    # Add extension resource to ARM template
    $armTemplate['resources'] += @{
        apiVersion = "2015-06-15"
        type = "Microsoft.Compute/virtualMachines/extensions"
        name = "[concat('" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'), '/JoinDomain')]"
        location = $location
        copy = @{
                name = "extensionDomainLoop"
                count = "[parameters('numberOfInstances')]"
            }
        dependsOn = @(
            "[concat('Microsoft.Compute/virtualMachines/','" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'))]"
        )
        tags = @{
            displayName = "JoinToDomain"
        }
        properties = @{ 
            publisher = "Microsoft.Compute"
            type = "JsonADDomainExtension"
            typeHandlerVersion = "1.3"
            autoUpgradeMinorVersion = $true
            settings = @{ 
                Name = $adDomain
                OUPath = $adDomainOU
                User = $DomainUserName
                Restart = $true
                Options = 3 #value of 3 is a combination of NETSETUP_JOIN_DOMAIN (0x00000001) & NETSETUP_ACCT_CREATE (0x00000002) i.e. will join the domain and create the account on the domain. For more information see https://msdn.microsoft.com/en-us/library/aa392154(v=vs.85).aspx"
 
            }
            protectedsettings = @{ 
                Password = "[parameters('DomainPassword')]" 
            }
        }
    } 
}

# Adding Custom Script Extension
if ($useCustomScriptExtension) {

    # Deploying multiple instances of Custom Script Extension (CSE) in a single
    # VM will not work if these CSE instances have different names. Therefore, the name
    # of the CSE extension should be kept consistent per VM.
    $extensionName = "CustomScriptExtension"
    
    # Custom Script Extension type is different for Windows vs. Linux VMs
    if ($image.OSFlavor -eq 'Windows'){
        Write-Host "Adding Custom Script Extension for Windows VM..."

        $armTemplate['resources'] += @{
            type = "Microsoft.Compute/virtualMachines/extensions"
            name = "[concat('" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'), '/" + $extensionName + "')]"
            apiVersion = "2015-06-15"
            location = $location
            copy = @{
                name = "extension2loop"
                count = "[parameters('numberOfInstances')]"
            }
            dependsOn = @(
                "[concat('Microsoft.Compute/virtualMachines/','" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'))]"
            )
            tags = @{
                displayName = "CustomScriptExtension"
            }
            properties = @{ 
                publisher = "Microsoft.Compute"
                type = "CustomScriptExtension"
                typeHandlerVersion = "1.8"
                autoUpgradeMinorVersion = $true
                settings = @{ 
                    fileUris = $fileUris
                    commandToExecute = $commandToExecute
                }
                protectedSettings = @{ 
                    storageAccountName = $customScriptExtensionStorageAccountName
                }
            }
        }
    }

    elseif ($image.OSFlavor -eq 'Linux'){
        Write-Host "Adding Custom Script Extension for Linux VM..."


        $armTemplate['resources'] += @{
            type = "Microsoft.Compute/virtualMachines/extensions"
            name = "[concat('" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'), '/" + $extensionName + "')]"
            apiVersion = "2015-06-15"
            location = $location
            copy = @{
                name = "extensionloop"
                count = "[parameters('numberOfInstances')]"
            }
            dependsOn = @( 
                "[concat('Microsoft.Compute/virtualMachines/','" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'))]"
            )
            tags = @{
                displayName = "CustomScriptExtension"
            }
            properties = @{ 
                publisher = "Microsoft.OSTCExtensions"
                type = "CustomScriptForLinux"
                typeHandlerVersion = "1.3"
                autoUpgradeMinorVersion = $true
                settings = @{ 
                    fileUris = $fileUris
                    commandToExecute = $commandToExecute
                }
                protectedSettings = @{ 
                    storageAccountName = $customScriptExtensionStorageAccountName
                }
            }
        }
    }

    # Calculate the index in which the Custom Script Extension resource is being defined
    $numResources = $armTemplate.resources.Count
    $cseIndex = $null
    for($k=0; $k -lt $numResources; $k++) {
                
        if ($armTemplate.resources[$k].name -eq "[concat('" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'), '/" + $extensionName + "')]" ) {
            $cseIndex = $k
        }
    }

    # If cannot find index for Custom Script Extension resource, throw an error
    if ( $cseIndex -eq $null ) {
        Write-Host "Cannot find the index of the Custom Script Extension resource in the ARM template." -BackgroundColor Black -ForegroundColor Red
        Exit -2
    }

    # If Windows VM is being added to the domain, add Join to Domain as a dependency on Custom Script Extension
    if ( ($image.OSFlavor -eq 'Windows') -and $joinToDomain ) {

        # Add dependency
        $armTemplate.resources[$cseIndex].dependsOn += "[concat('Microsoft.Compute/virtualMachines/','" + $virtualMachineBaseName + "', padLeft(copyindex($virtualMachineStartIndex),2,'0'), '/extensions/JoinDomain')]"
    }

    # If a key for the Storage Account was NOT manually specified as a parameter (and user input validation already guaranteed that the current user has access and permissions to
    # programatically obtain the storage account key), use the ARM template function listKeys() to obtain storage account key
    if ( [string]::IsNullOrEmpty($customScriptExtensionStorageKey) ) {
        $armTemplate.resources[$cseIndex].properties.protectedSettings.Add('storageAccountKey',"[listKeys(resourceId('Microsoft.Storage/storageAccounts/', '" + $customScriptExtensionStorageAccountName + "'), '2016-01-01').keys[0].value]")
    } 
    
    # If the storage account key was manually specified as a a parameter, there is no need to hide the storage account key locally. Input directly to ARM template
    else {
        $armTemplate.resources[$cseIndex].properties.protectedSettings.Add('storageAccountKey',$customScriptExtensionStorageKey)
    }
}

# Set output
$armTemplate['outputs'] = @{}
for ($i=0; $i -lt $numberVmsToDeploy; $i++) {
    $vmNum = $i + $virtualMachineStartIndex

    $outputVmName = $virtualMachineBaseName + $vmNum.ToString("00")
    $outputNicName = $nicNamePrefix + $virtualMachineBaseName + $vmNum.ToString("00") + $nicNameSuffix

    $armTemplate['outputs'][$outputVmName] = @{
        type = "object"
        value = "[reference('Microsoft.Compute/virtualMachines/" + $outputVmName + "' , '2015-06-15')]"
    }
    $armTemplate['outputs'][$outputNicName] = @{
        type = "object"
        value = "[reference('Microsoft.Network/networkInterfaces/" + $outputNicName + "', '2015-06-15')]"
    }
}
#end region





###################################################
# region: Deploy ARM Template
###################################################

# Generate password for VM if one wasn't already inputted
if ( !($password) ) {
    $password = Generate-Password -passwordlength $passwordLength
    Write-Host "Password for VM local administrator: $password"
}

Write-Host "Deploying ARM Template..."

# Convert ARM template into JSON format
$json = ConvertTo-Json -InputObject $armTemplate -Depth 99
$json = [regex]::replace($json,'\\u[a-fA-F0-9]{4}',{[char]::ConvertFromUtf32(($args[0].Value -replace '\\u','0x'))})
$json = $json -replace "\\\\\\","\" # Replace all instances of three backward slashes with just one (workaround for using the XML config for VM diagnostics resource)

# Save JSON file
Out-File -FilePath $jsonFilePath -Force -InputObject $json


try{
   
    # If joing to the domain a Windows VM, pass the password of the domain user or domain service account 
    if (  ($image.OSFlavor -eq 'Windows') -and ($joinToDomain) ) {
        $deploymentResult = New-AzureRmResourceGroupDeployment -ResourceGroupName $vmResourceGroupName `
                                            -Name $deploymentName `
                                            -Mode Incremental `
                                            -TemplateFile $jsonFilePath `
                                            -numberOfInstances $numberVmsToDeploy `
                                            -adminPassword ( ConvertTo-SecureString -String $password -AsPlainText -Force ) `
                                            -DomainPassword $DomainPassword

    } 

    # Do not pass domain user password or domain service account password if not required
    else {
        $deploymentResult = New-AzureRmResourceGroupDeployment -ResourceGroupName $vmResourceGroupName `
                                           -Name $deploymentName `
                                           -Mode Incremental `
                                           -TemplateFile $jsonFilePath `
                                           -numberOfInstances $numberVmsToDeploy `
                                           -adminPassword ( ConvertTo-SecureString -String $password -AsPlainText -Force )

    }

    Write-Host "ARM Template deployment $deploymentName finished successfully."

}
catch {
    
    $ErrorMessage = $_.Exception.Message

    Write-Host "ARM Template deployment $deploymentName failed with the error message below:" -BackgroundColor Black -ForegroundColor Red
    Write-Host "To see the inner errors for details, run the PowerShell cmdlet Get-AzureRmLog -CorrelationId xxxx-xxxx-xxxx -DetailedOutput, where the value of CorrelationId is the Tracking ID of the ARM Template deployment." -BackgroundColor Black -ForegroundColor Red
    throw "$ErrorMessage"
}

##################
# If selected, after the DHCP server in Azure has automatically assigned the NICs a private IP address, 
# set the allocation method of the NICs' private IP address to static
#
# We want these tasks to be run synchronously to save time.
# Start-Job may NOT be used, because it does not execute within the context of the current 
# PowerShell session and therefore does not have the necessary Azure credentials (i.e. will fail
# by asking the user to run Login-AzureRmAccount)
#
# Instead, we are creating jobs using [PowerShell]::Create(), which creates a new PowerShell instance in the context
# of the current PowerShell session.
##################

# Execute ONLY if static private IP addresses are required AFTER being automatically assigned by DHCP functionality in
# Azure
if ($staticPrivateIP -and $useAzureDHCP) {

    Write-Host "Changing private IP address allocation to Static..."

    # Loop through each NIC to create the job to set private IP addresses to static, and start the job
    for ($i=0; $i -lt $numberVmsToDeploy; $i++) {
        $vmNum = $i + $virtualMachineStartIndex
        
        # Define the script block that will be executed in each block
        $scriptBlock = { 
            # Define the paratemers to be passed to this script block
            Param($virtualMachineBaseName,$vmNum,$vmResourceGroupName,$nicNamePrefix,$nicNameSuffix) 

            try{
                # The actual lines of code that set NIC's private IP address to static.
                Import-Module AzureRM.Network
                $nicName = $nicNamePrefix + $virtualMachineBaseName + $vmNum.ToString("00") + $nicNameSuffix
                $nic = Get-AzureRmNetworkInterface -ResourceGroupName $vmResourceGroupName -Name $nicName
                $nic.IpConfigurations[0].PrivateIpAllocationMethod = "Static"
                $nic | Set-AzureRmNetworkInterface | Out-Null
            } catch {
                $ErrorMessage = $_.Exception.Message
                Write-Host "Setting the private IP address of a NIC as 'Static' failed with the following message:" -BackgroundColor Black -ForegroundColor Red
                throw "$ErrorMessage"
            }
        }
        
        # Create a new PowerShell object and store it in a variable
        New-Variable -Name "psSession-$virtualMachineBaseName-$i" -Value ([PowerShell]::Create())

        # Add the script block to the PowerShell session, and add the parameter values
        (Get-Variable -Name "psSession-$virtualMachineBaseName-$i" -ValueOnly).AddScript($scriptBlock).AddArgument($virtualMachineBaseName).AddArgument($vmNum).AddArgument($vmResourceGroupName).AddArgument($nicNamePrefix).AddArgument($nicNameSuffix) | Out-Null

        # Start the execution of the script block in the newly-created PowerShell session, and save its execution in a new variable as job
        New-Variable -Name "job-$virtualMachineBaseName-$i" -Value ((Get-Variable -Name "psSession-$virtualMachineBaseName-$i" -ValueOnly).BeginInvoke())

    }

    Start-Sleep -Seconds 10

    # Logic waiting for the jobs to complete
    $jobsRunning=$true 
    while($jobsRunning){
        
        # Reset counter for number of jobs still running
        $runningCount=0 
 
        # Loop through all jobs
        for ($i=0; $i -lt $numberVmsToDeploy; $i++) {
            $vmNum = $i + $virtualMachineStartIndex

            # Build name for the current NIC being checked
            $thisNicName = $nicNamePrefix + $virtualMachineBaseName + $vmNum.ToString("00") + $nicNameSuffix

            try {

                $jobCompletedStatus = (Get-Variable -Name "job-$virtualMachineBaseName-$i" -ValueOnly).IsCompleted
                
                if(   !($jobCompletedStatus)   ){ 

                    # If the PowerShell command being executed is NOT completed, increase the counter for number of jobs still running
                    $runningCount++ 
                } 
                else{ 

                    # If the PowerShell command has been completed, store the results of the job in the psSession variable, and then 
                    # release all resources of the PowerShell object
                    try {
                        $temp = Get-Variable -Name "job-$virtualMachineBaseName-$i" -ValueOnly
                        (Get-Variable -Name "psSession-$virtualMachineBaseName-$i" -ValueOnly).EndInvoke($temp)
                        (Get-Variable -Name "psSession-$virtualMachineBaseName-$i" -ValueOnly).Dispose()
                    }
                    catch {
                        
                        # Error scope: the job status was successfully acquired, but releasing the resources from the PowerShell
                        # session used to run the job encountered problems.

                        $ErrorMessage = $_.Exception.Message
                        Write-Host "Minor error reported releasing the resources of the background PowerShell session used to set static IP address on NIC: $thisNicName"
                        Write-Host "Error message: $ErrorMessage"
                        Write-Host "Verify that the private IP addresses assigned to the NICs deployed have successfully been set to Static."
                        Write-Host "Continuing..."
                        Continue
                    }
                } 
            }
            catch {

                # Error scope: acquiring the job status ran into an error.
                $ErrorMessage = $_.Exception.Message
                Write-Host "Minor error reported when getting status of job to set static IP address on NIC: $thisNicName"
                Write-Host "Error message: $ErrorMessage"
                Write-Host "Verify that the private IP addresses assigned to the NICs deployed have successfully been set to Static."
                Write-Host "Continuing..."
                Continue
            } 
        } 
        
        # If there are no more running jobs, set while-loop flap to end
        if ($runningCount -eq 0){ 
            $jobsRunning=$false 
        } 
 
        Start-Sleep -Seconds 15
    }

    # Delete all the variables holding jobs and PowerShell sessions
    for ($i=0; $i -lt $numberVmsToDeploy; $i++) {
        try {
            Remove-Variable -Name "psSession-$virtualMachineBaseName-$i"
            Remove-Variable -Name "job-$virtualMachineBaseName-$i"
        }
        catch {
            # Failed to remove variables associated with PowerShell sessions and jobs
            # Simply continue without throwing an error
            Continue
        }
    }
}
#end region





###################################################
# region: Reporting
###################################################

# Initializations
$toOutput = "" # Info to display on console
$toCSV = "" # Info to store in a CSV file
$longpadspace = 20

# Loop through each VM created to extract properties
for ($i=0; $i -lt $numberVmsToDeploy; $i++) {
    $vmNum = $i + $virtualMachineStartIndex

    $outputVmName = $virtualMachineBaseName + $vmNum.ToString("00")
    $outputNicName = ($nicNamePrefix + $virtualMachineBaseName + $vmNum.ToString("00") + $nicNameSuffix).ToLower()

    # The keys in the ARM template output may have had their upper/lower case structure modified.
    # To prevent any key matching errors, convert the case-sensitive hashtable keys to lower case
    $outputsWithLowerCaseKeys = @{}
    foreach( $oldKey in $($deploymentResult.Outputs.Keys) ){
        $outputsWithLowerCaseKeys.Add($oldKey.ToLower(),$deploymentResult.Outputs[$oldKey])
    }

    $data = $outputsWithLowerCaseKeys[$outputNicName].Value.ToString() | ConvertFrom-Json
    $ip = $data.ipConfigurations[0].Properties.privateIPAddress   
    
    # Build output for console
    $toOutput += ($outputVmName.PadRight($longpadspace,'-') + $ip.Trim().PadRight($longpadspace,'-') + $username.PadRight($longpadspace,'-') + $password) + "`r`n"

    # Build output for CSV file
    $toCSV = $outputVmName + ',' + $($ip.Trim()) + ',' + $username + ',' + $password
    Out-File -FilePath $csvfilepath -Append -InputObject $toCSV -Encoding unicode # Save output to CSV file
}

# Display VM name, private IP address, local admin username, and local admin password on the console
$toOutput

#endregion