param (

    # Resource Group and VMs in that resource group on which to execute Custom Script Extension
    [string] $resourcegroup = "SCCM-Testing",
    [string[]] $vmnames = @("testclient05",
                            "testclient06",
                            "testclient07",
                            "testclient08",
                            "testsqlvm01"),
    $vmLocation = "West US 2",

    <#
     Name of the Custom Script Extension (CSE) extension
     Ensure that this name matches the name of whatever CSE extension has already
     been installed on the target VMs. A name mismatch will cause CSE to fail.
     If CSE has not yet been installed on target VM, there are no restrictions on CSE name.
    #>
    $customScriptExtensionName = "Enable-Firewall-Rules",

    # Storage Account details
    [string] $PostProvisionStorageAccount = 'account',
    [string] $PostProvisionStorageKey = 'key',
    [string] $PostProvisionContainerName = 'uploadedresources'

)


$ErrorActionPreference = "Stop"

# Windows post-provisioning scripts
# Note: the addtoadmins.ps1 and Add-To-Domain.ps1 scripts have been excluded from this
# list of scripts. These should be run separately, because:
#  1) The current V2 provisioning script does NOT add the newly created VM to the Cloud domain
#  2) The Add-To-Domain.ps1 script forces the  target VM to restart
$PostProvisionWindowsScripts = @( 
      <# 
    @{
        Files = @('Install-Net35-and-IIS.ps1','IISDeploymentConfigTemplate.xml')
        Execute = 'Install-Net35-and-IIS.ps1'
      }

    
    @{
        Files = @('addtoadmins.ps1')
        Execute = 'addtoadmins.ps1'
      }
      
    #>
    @{
        Files = @('Add-To-Domain.ps1')
        Execute = 'Add-To-Domain.ps1'
    },

    @{
        Files = @('FixDNS-2.ps1')
        Execute = 'FixDNS-2.ps1'
    }<#,
    
    @{
        Files = @('FixActivation.ps1')
        Execute = 'FixActivation.ps1'
    },
    
    @{
        Files = @('EnableFirewallRules.ps1')
        Execute = 'EnableFirewallRules.ps1'
    },
    
    @{
        Files = @('SetupDSCinAzure.ps1','AzurePrivate.pfx')
        Execute = 'SetupDSCinAzure.ps1'
    }
    #>
)

foreach ($vmname in $vmnames) {
    Write-Host "Running Windows Config on $vmname"

    foreach ($script in $PostProvisionWindowsScripts){
        Write-Host ("Running " + $script['Execute'])

        # Run Custom Script Extension
        Set-AzureRmVMCustomScriptExtension `
                                -ResourceGroupName $resourcegroup `
                                -VMName $vmname `
                                -Location $vmLocation `
                                -Name $customScriptExtensionName `
                                -ContainerName $PostProvisionContainerName `
                                -StorageAccountName $PostProvisionStorageAccount `
                                -StorageAccountKey $PostProvisionStorageKey `
                                -FileName $script['Files'] `
                                -Run $script['Execute']
        
        sleep 2
    }
} 