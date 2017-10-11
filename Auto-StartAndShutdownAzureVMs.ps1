<#
.NAME
	Auto-StartAndShutdownAzureVMs
	
.DESCRIPTION 
    Starts and shutdown VMs in the target subscription based on the shutdown schedule specified as 
    Tags on resource groups and/or VMs.

    Virtual Machines (VMs) and resource groups can be Tagged. If a tag with the value "AutoShutdownSchedule"
    is found in any VM or resource group, this runbook will assess whether that VM should be in a "Running" or in
    a "Deallocated" state. VMs will be started or stopped accordingly.

    This runbook runs as a PowerShell Workflow in order to execute activities on all subscription VMs in parallel.

    This runbook leverages the tag structure of another runbook called "Assert-AutoShutdownSchedule". Detailed 
    documentation on the tag structure can be found here: https://automys.com/library/asset/scheduled-virtual-machine-shutdown-startup-microsoft-azure

.PARAMETER AzureCredentialName
    Specify the name of the Credential Asset to use.
    Set this parameter as "Use *Default Automation Credential* Asset" in order to use the credential asset named
    "Default Automation Credential"

.PARAMETER  AzureSubscriptionName
    Specify the name of the Variable asset to use from which to retrieve the name of the Azure subscription.
    Set this parameter as "Use *Default Azure Subscription* Variable Value" in order to use the variable asset named
    "Default Azure Subscription"

#>

workflow Auto-StartAndShutdownAzureVMs
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

    # Get time at which runbook started
    $workbookStartTime = (Get-Date).ToUniversalTime()
    
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
            $subscription = Select-AzureRmSubscription -SubscriptionName $AzureSubscriptionName
            Write-Output "Specified subscription name/ID: [$AzureSubscriptionName]"
        }
        else
        {
            throw "No subscription name was specified, and no variable asset with name 'Default Azure Subscription' was found. Either specify an Azure subscription name or define the default using a variable setting"
        }
    }
    else{
        $subscription = Select-AzureRmSubscription -SubscriptionName $AzureSubscriptionName 
    }


    ###################################
    # Main Content
    ###################################

    # Get a list of all virtual machines in subscription
    $resourceManagerVMList = InlineScript 
            {
                Get-AzureRmResource | where {$_.ResourceType -like "Microsoft.*/virtualMachines"} | sort Name
            }

    # Get resource groups that are tagged for automatic shutdown of resources
    $taggedResourceGroups = InlineScript 
        {
            Get-AzureRmResourceGroup | where {$_.Tags.Count -gt 0 -and $_.Tags.Name -contains "AutoShutdownSchedule"}
        }
    $taggedResourceGroupNames = InlineScript 
        {
            $taggedResourceGroups | select -ExpandProperty ResourceGroupName
        }
    Write-Output "Found [$($taggedResourceGroups.Count)] schedule-tagged resource groups in subscription"	

    # For each VM, determine
    #  - Is it directly tagged for shutdown or member of a tagged resource group
    #  - Is the current time within the tagged schedule 
    # Then assert its correct power state based on the assigned schedule (if present)
    Write-Output "Processing [$($resourceManagerVMList.Count)] virtual machines found in subscription"
    foreach -parallel ($vm in $resourceManagerVMList)
    {
        $schedule = $null

        # Check for direct tag or group-inherited tag
        if($vm.ResourceType -eq "Microsoft.Compute/virtualMachines" -and $vm.Tags -and $vm.Tags.Name -contains "AutoShutdownSchedule")
        {
            # VM has direct tag (possible for resource manager deployment model VMs). Prefer this tag schedule.
            $schedule = ($vm.Tags | where Name -eq "AutoShutdownSchedule")["Value"]
            Write-Output "[$($vm.Name)]: Found direct VM schedule tag with value: $schedule"
        }
        elseif($taggedResourceGroupNames -contains $vm.ResourceGroupName)
        {
            # VM belongs to a tagged resource group. Use the group tag
            $parentGroup = $taggedResourceGroups | where ResourceGroupName -eq $vm.ResourceGroupName
            $schedule = ($parentGroup.Tags | where Name -eq "AutoShutdownSchedule")["Value"]
            Write-Output "[$($vm.Name)]: Found parent resource group schedule tag with value: $schedule"
        }
        else
        {
            # No direct or inherited tag. Skip this VM.
            Write-Output "[$($vm.Name)]: Not tagged for shutdown directly or via membership in a tagged resource group. Skipping this VM."
            
        }

        # Check that tag value was succesfully obtained
        if($schedule -eq $null)
        {
            Write-Output "[$($vm.Name)]: Failed to get tagged schedule for virtual machine. Skipping this VM."
        }

        # Parse the ranges in the Tag value. Expects a string of comma-separated time ranges, or a single time range
		$timeRangeList = @($schedule -split "," | foreach {$_.Trim()})
	    
        # Check each range against the current time to see if any schedule is matched
		$scheduleMatched = $false
        $matchedSchedule = $null
		foreach($TimeRange in $timeRangeList)
		{

            #####################################
            # CheckScheduleEntry function
            #####################################

            # Initialize variables
	        $rangeStart = $null
            $rangeEnd = $null
            $parsedDay = $null
	        $currentTime = (Get-Date).ToUniversalTime()
            $midnight = $currentTime.AddDays(1).Date	        

	        try
	        {
	            # Parse as range if contains '->'
	            if($TimeRange -like "*->*")
	            {
	                $timeRangeComponents = $TimeRange -split "->" | foreach {$_.Trim()}
	                if($timeRangeComponents.Count -eq 2)
	                {
	                    $rangeStart = Get-Date $timeRangeComponents[0]
	                    $rangeEnd = Get-Date $timeRangeComponents[1]
	
	                    # Check for crossing midnight
	                    if($rangeStart -gt $rangeEnd)
	                    {
                            # If current time is between the start of range and midnight tonight, interpret start time as earlier today and end time as tomorrow
                            if($currentTime -ge $rangeStart -and $currentTime -lt $midnight)
                            {
                                $rangeEnd = $rangeEnd.AddDays(1)
                            }
                            # Otherwise interpret start time as yesterday and end time as today   
                            else
                            {
                                $rangeStart = $rangeStart.AddDays(-1)
                            }
	                    }
	                }
	                else
	                {
	                    Write-Output "`tWARNING: Invalid time range format. Expects valid .Net DateTime-formatted start time and end time separated by '->'" 
	                }
	            }
	            # Otherwise attempt to parse as a full day entry, e.g. 'Monday' or 'December 25' 
	            else
	            {
	                # If specified as day of week, check if today
	                if([System.DayOfWeek].GetEnumValues() -contains $TimeRange)
	                {
	                    if($TimeRange -eq (Get-Date).DayOfWeek)
	                    {
	                        $parsedDay = Get-Date "00:00"
	                    }
	                    else
	                    {
	                        # Skip detected day of week that isn't today
	                    }
	                }
	                # Otherwise attempt to parse as a date, e.g. 'December 25'
	                else
	                {
	                    $parsedDay = Get-Date $TimeRange
	                }
	    
	                if($parsedDay -ne $null)
	                {
	                    $rangeStart = $parsedDay # Defaults to midnight
	                    $rangeEnd = $parsedDay.AddHours(23).AddMinutes(59).AddSeconds(59) # End of the same day
	                }
	            }
	        }
	        catch
	        {
	            # Record any errors and return false by default
	            Write-Output "`tWARNING: Exception encountered while parsing time range. Details: $($_.Exception.Message). Check the syntax of entry, e.g. '<StartTime> -> <EndTime>', or days/dates like 'Sunday' and 'December 25'"   
	            return $false
	        }
	
	        # Check if current time falls within range
	        if($currentTime -ge $rangeStart -and $currentTime -le $rangeEnd)
	        {
	            $scheduleMatched = $true
                $matchedSchedule = $TimeRange
	        }

            ######################################
            # End of CheckScheduleEntry function
            #####################################

		} #End of foreach loop to check each range against the current time

        # Enforce desired state for group resources based on result. 
		if($scheduleMatched)
		{
            # Schedule is matched. Shut down the VM if it is running. 
		    Write-Output "[$($vm.Name)]: Current time [$currentTime] falls within the scheduled shutdown range [$matchedSchedule]"
            $DesiredState = "StoppedDeallocated"
		    
		}
		else
		{
            # Schedule not matched. Start VM if stopped.
		    Write-Output "[$($vm.Name)]: Current time falls outside of all scheduled shutdown ranges."
		    $DesiredState = "Started"
		}

        #####################################
        # AssertVirtualMachinePowerState function
        #####################################

        # Get VM with current status
        $vmRgName = $vm.ResourceGroupName
        $vmName = $vm.Name
        $currentStatus = InlineScript 
        {
            $vmStatus = Get-AzureRmVM -ResourceGroupName $using:vmRgName -Name $using:vmName -Status
            $vmStatus = $vmStatus.Statuses | where Code -like "PowerState*"
            $vmStatus = $vmStatus.Code -replace "PowerState/",""

            Write-Output "$vmStatus"
        }

        # If should be started and isn't, start VM
	    if($DesiredState -eq "Started" -and $currentStatus -notmatch "running")
	    {

            Write-Output "[$($vm.Name)]: Starting VM"
            $null = $vm | Start-AzureRmVM #Assign to $null to suppress output as an alternative to Out-Null
           
	    }
		
	    # If should be stopped and isn't, stop VM
	    elseif($DesiredState -eq "StoppedDeallocated" -and $currentStatus -ne "deallocated")
	    {

            Write-Output "[$($vm.Name)]: Stopping VM"
            $null = $vm | Stop-AzureRmVM -Force #Assign to $null to suppress output as an alternative to Out-Null
            
	    }

        # Otherwise, current power state is correct
        else
        {
            Write-Output "[$($vm.Name)]: Current power state [$currentStatus] is correct."
        }

        #####################################
        # End of AssertVirtualMachinePowerState function
        #####################################

    } # end of foreach -parallel

    Write-Output "Finished processing virtual machine schedules"

    Write-Output "Runbook finished (Duration: $(("{0:hh\:mm\:ss}" -f ((Get-Date).ToUniversalTime() - $workbookStartTime))))"
}