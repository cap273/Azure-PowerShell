<#

.NAME
	AzureVMAgentAudit
	
.DESCRIPTION 
    Retrieves the properties of all the VMs in all subscriptions associated with a particular user, and outputs
    the status of each VM's Azure VM Agent in a CSV file.

.PARAMETER csvFilePath
	The path in where to store the CSV file. Example: $csvFilePath = "C:\temp\agentAudit.csv"
#>

param(
    # Specify the location of the audit file
    $csvFilePath = "C:\temp\agentAudit.csv"
)

cls
# Make all errors terminating
$ErrorActionPreference = 'Stop'


# Checking whether user is logged in to Azure
Write-Host "Validating Azure Accounts..."
try{
    $subscriptionList = Get-AzureRmSubscription | Sort SubscriptionName
}
catch {
    Write-Host "Reauthenticating..."
    Login-AzureRmAccount | Out-Null
    $subscriptionList = Get-AzureRmSubscription | Sort SubscriptionName
}

# If a previous audit file already exists, remove it
if (Test-Path $csvFilePath) {

    Remove-Item -Path $csvFilePath
}

# Loop through all subscriptions
foreach($subscription in $subscriptionList) {

    # Select the current subscription
    Select-AzureRmSubscription -SubscriptionId $subscription.SubscriptionId | Out-Null

    Write-Output "`n Working on subscription: $($subscription.SubscriptionName) `n"

    # Get all the VMs in the subscription
    $vms = Get-AzureRmVM -WarningAction Ignore

    # Loop through all VMs in the subscription
    foreach ($vm in $vms) {

        # Get the name of this VM
        $vmName = $vm.Name

        Write-Output "Processing VM: $vmName..."

        # Get only the instance level view of this VM
        $vmStatus = Get-AzureRmVM -ResourceGroupName $vm.ResourceGroupName `
                                  -Name $vmName `
                                  -Status `
                                  -WarningAction Ignore


        # Get the OS type of this VM
        $osType = $vm.StorageProfile.OsDisk.OsType

        # Get VM Agent Version
        $vmAgentVersion = $vmStatus.VMAgent.VmAgentVersion

        # Get the state of the VM
        $vmState = $vmStatus.Statuses[1].DisplayStatus

        try{
            # Get the VM Agent Display Status
            $vmAgentDisplayStatus = $vmStatus.VMAgent.Statuses[0].DisplayStatus
        }
        catch{
            $vmAgentDisplayStatus = ""
        }

        try{
            # Get the VM Agent Message
            $vmAgentMessage = $vmStatus.VMAgent.Statuses[0].Message
        }
        catch{
            $vmAgentMessage = ""
        }

        # Store all data points into PowerShell Object
        $output = New-Object -TypeName PSCustomObject `
                             -Property @{
                                            VMName = $vmName;
                                            OSType = $osType;
                                            VMAgentVersion = $vmAgentVersion;
                                            VMAgentDisplay = $vmAgentDisplayStatus;
                                            VMAgentMessage = $vmAgentMessage;
                                            VMState = $vmState;

                                        }

        # Store data from PowerShell object into CSV file
        $output | Export-Csv -Path $csvFilePath -Append -NoTypeInformation
    }
}

Write-Output "`n `n Azure VM Agent audit complete. CSV file stored in: $csvFilePath"