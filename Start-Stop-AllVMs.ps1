# Perform some action on some group of Azure resources in parallel

######################################
# USER INPUT
# Get the Azure resources on which to execute desired action
######################################
$resourceGroupName= 'RG-Testing'
$resources = Get-AzureRmVM -ResourceGroupName $resourceGroupName


$i = 1
$offset = 1
$count = ($resources | measure).Count

$ErrorActionPreference = 'Stop'

foreach ($resource in $resources){
        
    # Define the script block that will be executed in each block
    $scriptBlock = { 
        # Define the paratemers to be passed to this script block
        Param($resource) 

        try{
	    ######################################
            # USER INPUT
	    # Specify the action to perform on the resources
	    ######################################	
            Import-Module AzureRM.Compute
            $resource | Stop-AzureRmVM -Force
            #$resource | Start-AzureRmVM -Force

        } catch {
            $ErrorMessage = $_.Exception.Message
            Write-Host "Failed with the following message:" -BackgroundColor Black -ForegroundColor Red
            throw "$ErrorMessage"
        }
    } 
        
    # Create a new PowerShell object and store it in a variable
    New-Variable -Name "psSessionRem-$i" -Value ([PowerShell]::Create())

    # Add the script block to the PowerShell session, and add the parameter values
    (Get-Variable -Name "psSessionRem-$i" -ValueOnly).AddScript($scriptBlock).AddArgument($resource) | Out-Null

    Write-Host "Starting job on resource $($resource.Name)..."
    
    # Start the execution of the script block in the newly-created PowerShell session, and save its execution in a new variable as job
    New-Variable -Name "jobRem-$i" -Value ((Get-Variable -Name "psSessionRem-$i" -ValueOnly).BeginInvoke())

    $i++
}


# Logic waiting for the jobs to complete
$jobsRunning=$true 
while($jobsRunning){
        
    # Reset counter for number of jobs still running
    $runningCount=0 
 
    # Loop through all jobs
    foreach ($i in $offset..$count){ 
            
        if(   !(Get-Variable -Name "jobRem-$i" -ValueOnly).IsCompleted   ){ 
            # If the PowerShell command being executed is not completed, increase the counter for number of jobs still running
            $runningCount++ 
        } 
        else{ 
            # If the PowerShell command has been completed, store the results of the job in the psSession variable, and then 
            # release all resources of the PowerShell object
            (Get-Variable -Name "psSessionRem-$i" -ValueOnly).EndInvoke((Get-Variable -Name "jobRem-$i" -ValueOnly))
            (Get-Variable -Name "psSessionRem-$i" -ValueOnly).Dispose()
        } 
    } 
        
    # If there are no more running jobs, set while-loop flap to end
    if ($runningCount -eq 0){ 
        $jobsRunning=$false 
    } 
 
    Write-Host "Jobs remaining: $runningCount out of $count"
    Start-Sleep -Seconds 5
}


# Delete all the variables holding jobs and PowerShell sessions
foreach ($i in $offset..$count){
    
    Remove-Variable -Name "psSessionRem-$i" -ErrorAction Continue
    Remove-Variable -Name "jobRem-$i" -ErrorAction Continue
}
