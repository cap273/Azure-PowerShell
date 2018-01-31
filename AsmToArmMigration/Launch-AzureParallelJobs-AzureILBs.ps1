<#

.NAME
	Launch-AzureParallelJobs-AzureILBs
	
.DESCRIPTION 
    Calls the script Migrate-AzureInternalLoadBalancers to begin several ASM to ARM migration jobs.
    The number of migration jobs are retrieved from the CSV file specified in $csvFilePath.

    *NOTE*:  The current working directory must contain the script Migrate-AzureInternalLoadBalancers.ps1

.PARAMETER csvFilePath
    The file path of the CSV file that contains information on the ASM Load Balancers (implicit inside of ASM Cloud Services) that will be migrated
    from ASM to ARM.

.PARAMETER statusFilePath
    The file path of the CSV file where the output of each migration job will be written.
    Every time Launch-AzureParallelJobs-AzureIlbs is executed, a new CSV file at $statusFilePath will be created, and any pre-existing
    file at $statusFilePath will be deleted.

.NOTES
    AUTHOR: Carlos Patiño
    LASTEDIT: January 30, 2018
    LEGAL DISCLAIMER:
        This script is not supported under any Microsoft standard program or service. This script is
        provided AS IS without warranty of any kind. Microsoft further disclaims all
        implied warranties including, without limitation, any implied warranties of mechantability or
        of fitness for a particular purpose. The entire risk arising out of the use of performance of
        this script and documentation remains with you. In no event shall Microsoft, its authors, or 
        anyone else involved in the creation, production, or delivery of this script be liable
        for any damages whatsoever (including, without limitation, damages for loss of
        business profits, business interruption, loss of business information, or other
        pecuniary loss) arising out of the use of or inability to use this script or docummentation, 
        even if Microsoft has been advised of the possibility of such damages.
#>
  
param(

    # CSV file containing information on Cloud Services and ILBs to migrate
    [String] $csvFilePath = "C:\Users\carpat\Desktop\ILBstoMigrate.csv",

    # Full file name and path of the CSV file to be created for reporting
    [String] $statusFilePath = "C:\Users\carpat\Desktop\IlbMigrationStatus.csv"

)

cls
$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

###################################################################################################
#                       AZURE PARALLEL JOBS FUNCTION DEFINITION
###################################################################################################

function New-AzureParallelJobs 
{
    Param($csv,$statusFilePath)
           
        # Variable initialization
        $i = 1 # Index for jobs to be executed
        $offset = 1
        $count = ($csv | measure).Count # Number of total jobs to execute, based on information in CSV file
        $arrayOfRunningJobs = New-Object System.Collections.ArrayList # Array to contain only the index of the currently-running jobs
        $arrayOfCloudServiceNames = New-Object System.Collections.ArrayList # Array to contain the VM name of each currently-running job

        if ($count -lt 1) 
        {
            Write-Output "Could not find items in CSV file. Exiting..."
            throw "Could not find items in CSV file. Exiting..."
        }

        foreach ($listOfJobParameters in $csv)
        {
        
            # Define the script block that will be executed in each block
            $scriptBlock = 
            { 

                # Define the paratemers to be passed to this script block
                Param($listOfJobParameters) 
                
                try
                {
                   .\Migrate-AzureInternalLoadBalancers.ps1 -originalASMSubscriptionName $listOfJobParameters.originalASMSubscriptionName `
                                                          -targetARMSubscriptionName $listOfJobParameters.targetARMSubscriptionName `
                                                          -asmCloudServiceName $listOfJobParameters.asmCloudServiceName `
                                                          -targetResourceGroup $listOfJobParameters.targetResourceGroup `
                                                          -location $listOfJobParameters.location `
                                                          -vnetResourceGroupName $listOfJobParameters.vnetResourceGroupName `
                                                          -virtualNetworkName $listOfJobParameters.virtualNetworkName `
                                                          -subnetName $listOfJobParameters.subnetName
                }
                catch 
                {
                    $ErrorMessage = $_.Exception.Message
                    Write-Output "Job initiation failed with the following message:"
                    Write-Output "$ErrorMessage"
                    throw "$ErrorMessage"
                }
            } 
        
            # Create a new PowerShell object and store it in a variable
            New-Variable -Name "psSessionRem-$i" -Value ([PowerShell]::Create())

            # Add the script block to the PowerShell session, and add the parameter values
            (Get-Variable -Name "psSessionRem-$i" -ValueOnly).AddScript($scriptBlock).AddArgument($listOfJobParameters) | Out-Null

            Write-Output "Starting job on Cloud Service $($listOfJobParameters.asmCloudServiceName)..."
    
            # Start the execution of the script block in the newly-created PowerShell session, and save its execution in a new variable as job
            New-Variable -Name "jobRem-$i" -Value ((Get-Variable -Name "psSessionRem-$i" -ValueOnly).BeginInvoke())

            # Add this currently-running job index to an array for tracking purposes
            $arrayOfRunningJobs.Add($i) | Out-Null

            # Add the corresponding VM Name of this currently-running job to an array for tracking purposes
            $arrayOfCloudServiceNames.Add($listOfJobParameters.asmCloudServiceName) | Out-Null
             
            $i++
        }

        # Logic waiting for the jobs to complete
        $jobsRunning=$true 
        while($jobsRunning)
        {
        
            # Reset counter for number of jobs still running
            $runningCount=0 
 
            # Loop through all currently-running jobs
            for ($k = 0; $k -lt ($arrayOfRunningJobs | Measure).Count; $k++)
            { 
                
                $j = $arrayOfRunningJobs[$k] # This job index
                $thisCloudServiceName = $arrayOfCloudServiceNames[$k] # The name of the VM corresponding to this job
            
                # If the job has been marked as completed
                if(  (Get-Variable -Name "jobRem-$j" -ValueOnly).IsCompleted  ) 
                {

                    try{
                        # Store the results of the job in the psSession variable, and then 
                        # release all resources of the PowerShell object
                        (Get-Variable -Name "psSessionRem-$j" -ValueOnly).EndInvoke((Get-Variable -Name "jobRem-$j" -ValueOnly)) | Out-Null
                        (Get-Variable -Name "psSessionRem-$j" -ValueOnly).Dispose() | Out-Null
                    }
                    catch{
                        $ErrorMessage = $_.Exception.Message

                        # If there is an error, remove only the variables associated with this job
                        Remove-Variable -Name "psSessionRem-$j" -ErrorAction SilentlyContinue
                        Remove-Variable -Name "jobRem-$j" -ErrorAction SilentlyContinue

                        # Do not throw an error. Report failure to console.
                        Write-Host "`nJob failure on Cloud Service: [$thisCloudServiceName]. Error message:"
                        Write-Host "$ErrorMessage"
                        Write-Host "Reported to CSV status file. Continuing with monitoring other jobs...`n"

                        # Add to CSV status file
                        $toCSV = "$j" + ',' + "Failed" + ',' + $thisCloudServiceName + ',' + $ErrorMessage
                        Out-File -FilePath $statusFilePath -Append -InputObject $toCSV -Encoding unicode

                        # Remove job from list of running jobs
                        $arrayOfRunningJobs.Remove($j) | Out-Null
                        $arrayOfCloudServiceNames.Remove($thisCloudServiceName) | Out-Null

                        Continue
                    }

                    # If no errors, report this job as complete
                    Write-Host "`nJob complete for Cloud Service: [$thisCloudServiceName]`n"

                    Remove-Variable -Name "psSessionRem-$j" -ErrorAction SilentlyContinue
                    Remove-Variable -Name "jobRem-$j" -ErrorAction SilentlyContinue

                    # Add to CSV status file
                    $toCSV = "$j" + ',' + "Succeeded" + ',' + $thisCloudServiceName + ',' + "NoErrors"
                    Out-File -FilePath $statusFilePath -Append -InputObject $toCSV -Encoding unicode

                    # Remove job from list of running jobs
                    $arrayOfRunningJobs.Remove($j) | Out-Null
                    $arrayOfCloudServiceNames.Remove($thisCloudServiceName) | Out-Null
                } 
            }

            # Recount how many jobs are still running
            $runningCount = ($arrayOfRunningJobs | Measure).Count
            Write-Output "Jobs remaining: $runningCount out of $count"
        
            # If there are no more running jobs, set while-loop flag to end. Otherwise, sleep for 30 seconds.
            if ($runningCount -eq 0)
            { 
                $jobsRunning=$false 
            }
            else{
                Start-Sleep -Seconds 30
            }

        } #end of while-loop


        # After all jobs are complete, completely ensure that all the variables holding jobs and PowerShell sessions have been deleted
        foreach ($k in $offset..$count)
        {
            Remove-Variable -Name "psSessionRem-$k" -ErrorAction SilentlyContinue
            Remove-Variable -Name "jobRem-$k" -ErrorAction SilentlyContinue
        }

}#New-AzureParallelJobs


# Get time at which runbook started
$runbookStartTime = (Get-Date).ToUniversalTime()
Write-Output "Runbook start time in UTC: [$runbookStartTime]"

###################################################################################################
#                       MAIN SCRIPT EXECUTION
###################################################################################################


# Check for Azure PoweShell version
$modlist = Get-Module -ListAvailable -Name 'AzureRM.Resources'
if (($modlist -eq $null) -or ($modlist.Version.Major -lt 5)){
    throw "Please install the Azure Powershell module, version 5.0.0 or above."
}

# Explicitly import Azure modules
Import-Module Azure
Import-Module AzureRM.Profile

# Force that working directory of the console session is also the working directory of the PowerShell process
[System.Environment]::CurrentDirectory = $PWD

# Ensure that the current working directory contains the script Migrate-AzureMs.ps1
if ( !(Test-Path -Path "$pwd\Migrate-AzureInternalLoadBalancers.ps1") ) {
    throw "Error: the file [Migrate-AzureInternalLoadBalancers.ps1] is not in the current working directory [$pwd]"
}


Write-Host "Please authenticate to ARM..."
Login-AzureRmAccount | Out-Null

Write-Host "Please authenticate to ASM..."
Add-AzureAccount | Out-Null


Write-Output "Starting parallel migration jobs."


# Import CSV file with information on VMs to migrate
$csvFile = Import-Csv -Path $csvFilePath

# Delete any pre-existing CSV status file
if (Test-Path $statusFilePath) {
    Remove-Item $statusFilePath -Force
}

# Add a new CSV file with a header
$toCSV = "JobIndex,JobStatus,CloudServiceName,ErrorMessage"
Out-File -FilePath $statusFilePath -Append -InputObject $toCSV -Encoding unicode

# Execute function to start parallel jobs
New-AzureParallelJobs -csv $csvFile -statusFilePath $statusFilePath

$runbookEndTime = (Get-Date).ToUniversalTime()
Write-Output "Runbook end time in UTC: [$runbookEndTime]"