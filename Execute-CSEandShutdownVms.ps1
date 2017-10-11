# Azure Automation workflow

workflow Execute-CSEandShutdownVms
{
    param(
    [parameter(Mandatory=$false)]
	[String] $AzureCredentialName = "Use *Default Automation Credential* Asset",
    [parameter(Mandatory=$false)]
	[String] $AzureSubscriptionName = "Use *Default Azure Subscription* Variable Value"
    )

    ###################################
    # Initializations
    ###################################

    # Get current time
    $currentTime = (Get-Date).ToUniversalTime()


    # Define the location and name of the Custom Script Extension file to execute
    $storageRgName = "powershellLearning"
    $storageAccountName = "powershelllearning8059"
    $containerName = 'customimages'
    $fileName = "testScript.ps1"

    # Define the name of the Custom Script Extension (CSE) extension (which is customizable when first deploying CSE on a new VM)
    $customScriptExtensionName = 'CustomScriptExtension'

    # Define the argument to be passed on to the script to be executed through CSE
    $fileArgument = 'test'


    
    # Get credential asset to log into Azure
    Write-Output "Specified credential asset name: [$AzureCredentialName]"
    if($AzureCredentialName -eq "Use *Default Automation Credential* asset")
    {
        # By default, look for "Default Automation Credential" asset
        $azureCredential = Get-AutomationPSCredential -Name "Default Automation Credential"
        if($azureCredential -ne $null)
        {
		    Write-Output "Attempting to authenticate as: [$($azureCredential.UserName)]"
        }
        else
        {
            throw "No automation credential name was specified, and no credential asset with name 'Default Automation Credential' was found. Either specify a stored credential name or define the default using a credential asset"
        }
    }
    else
    {
        # A different credential name was specified, attempt to load it
        $azureCredential = Get-AutomationPSCredential -Name $AzureCredentialName
        if($azureCredential -eq $null)
        {
            throw "Failed to get credential with name [$AzureCredentialName]"
        }
    }
    
    # Connect to Azure using credential asset
    try
    {
        $account = Add-AzureRmAccount -Credential $azureCredential
    }
    catch
    {
        throw "Authentication failed for credential [$($azureCredential.UserName)]. Ensure a valid Azure Active Directory user account is specified which is configured as a co-administrator (using classic portal) and subscription owner (modern portal) on the target subscription. Verify you can log into the Azure portal using these credentials."
    }

    # Retrieve subscription name from variable asset if not specified
    if($AzureSubscriptionName -eq "Use *Default Azure Subscription* Variable Value")
    {
        $AzureSubscriptionName = Get-AutomationVariable -Name "Default Azure Subscription"
        if($AzureSubscriptionName.length -gt 0)
        {
            Select-AzureRmSubscription -SubscriptionName $AzureSubscriptionName
            Write-Output "Specified subscription name/ID: [$AzureSubscriptionName]"
        }
        else
        {
            throw "No subscription name was specified, and no variable asset with name 'Default Azure Subscription' was found. Either specify an Azure subscription name or define the default using a variable setting"
        }
    }



    ###################################
    # Main Content
    ###################################

    # Get all Windows VMs in the subscription
    $vms = InlineScript 
            {
                Get-AzureRmVM | Where-Object {$_.StorageProfile.OsDisk.OsType -eq "Windows"}
            }

    # Initialize an empty Array 
    # Each element of the array will contain an index/output pair, where output is a hashtable containing VM Name, StdOut, and StdErr
    $cseOutputs = @()

    # Initialize start and end counters
    $startCount = 1
    $endCount = ($vms | Measure).Count

    # Get the key of the storage account in which Custom Script Extension script is located
    $pw = Get-AzureRmStorageAccountKey -ResourceGroupName $storageRgName -Name $storageAccountName

    
    # Loop through all Windows VMs to deploy Custom Script Extension and retrieve the script's StdOut and StdErr
    foreach -parallel ($i in $startCount..$endCount){
        
        # Get the VM object for this VM
        $vm = $vms[$i-1]
        $vmName = $vm.Name
        $rgName = $vm.ResourceGroupName
        $location = $vm.Location

        
        # Execute custom script extension
        Set-AzureRmVMCustomScriptExtension -ResourceGroupName $rgName `
                                           -VMName $vmName `
                                           -StorageAccountName $storageAccountName `
                                           -ContainerName $containerName `
                                           -FileName $fileName `
                                           -Location $location `
                                           -Name $customScriptExtensionName `
                                           -TypeHandlerVersion "1.8" `
                                           -Run $fileName `
                                           -Argument $fileArgument `
                                           -StorageAccountKey $pw.Key1


        # Get StdOut and StdErr of Custom Script Extension script execution
        $output = Get-AzureRmVMDiagnosticsExtension -ResourceGroupName $rgName `
                                                    -VMName $vmName `
                                                    -Name $customScriptExtensionName `
                                                    -Status
        
        # Get the standard output from Custom Script Extension execution
        $StdOut = InlineScript {
                            
                            $unprocessedText = ($using:output).SubstatusesText
                            $processedText = (ConvertFrom-Json -InputObject $unprocessedText)

                            Write-Output $($processedText[0].message)
            }

        # Get the standard error from Custom Script Extension execution
        $StdErr = InlineScript {

                            $unprocessedText = ($using:output).SubstatusesText
                            $processedText = (ConvertFrom-Json -InputObject $unprocessedText)

                            Write-Output $($processedText[1].message)
                    }

        # Output progress to console
        Write-Output "VM $vmName has the following StdOut: $StdOut"
        Write-Output "VM $vmName has the following StdErr: $StdErr"

        # Create hashtable with results from CSE execution for this VM
        $outputTable = @{
                            "RgName" = $rgName;
                            "VMName" = $vmName;
                            "StdOut" = $StdOut;
                            "StdErr" = $StdErr
                        }

        # Append a new item to array containing CSE StdOuts and StdErr for all VMs
        $workflow:cseOutputs += @{ $i = $outputTable }
        
    } # End of "foreach -parallel" loop to deploy CSE on VMs


    ######
    # TODO: Implement some logic whether to start/shutdown VMs based on output from CSE operations on the entire set of VMs

    Write-Output "end of CSE operations"

    # Loop through all Windows VMs to shutdown based on output of CSE
    foreach -parallel ($i in $startCount..$endCount){

        # Extract Name of Resource Group, VM, and the StdOut and StdErr of its CSE operation
        $rgName = InlineScript{
            $index = $using:i - 1
            $array = $using:cseOutputs
            $arrayElement = $array[$index].Values
            $arrayElement.Item("RgName")
        }
        $vmName = InlineScript{
            $index = $using:i - 1
            $array = $using:cseOutputs
            $arrayElement = $array[$index].Values
            $arrayElement.Item("VMName")
        }
        $StdOut = InlineScript{
            $index = $using:i - 1
            $array = $using:cseOutputs
            $arrayElement = $array[$index].Values
            $arrayElement.Item("StdOut")
        }
        $StdErr = InlineScript{
            $index = $using:i - 1
            $array = $using:cseOutputs
            $arrayElement = $array[$index].Values
            $arrayElement.Item("StdErr")
        }

        # If StdErr is null or empty, there are no errors to report
        $noError = InlineScript {
            [string]::IsNullOrEmpty($using:StdErr)
        }

        # Attempt to stop the VM if StdOut matches expectation
        if ($noError) {

            if ($StdOut -eq '1') {
                
                try{
                    # Shutdown VM
                    Stop-AzureRmVM -ResourceGroupName $rgName -Name $vmName -Force

                } catch {
                    $errorMessage = $_.Exception.Message
                    throw "Error when trying to stop VM $vmName. Error message: $errorMessage"
                }
            }

        } else {
            
            Write-Output "Custom Script Extension execution on VM $vmName reported the following error: $StdErr"
        }

    } # End of "foreach -parallel" loop to stop VMs

    Write-Output "Runbook finished (Duration: $(("{0:hh\:mm\:ss}" -f ((Get-Date).ToUniversalTime() - $currentTime))))"
}