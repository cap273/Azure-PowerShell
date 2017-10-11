<#
    This script creates a task for Windows Task Scheduler to execute a PowerShell script.
   
    # The script below will run as the specified user (you will be prompted for credentials)
    # and is set to be elevated to use the highest privileges.
    # In addition, the task will run every 5 minutes or however long specified in $executionIntervalMins.

#>
param(

    $pathOfScriptToExecute = "C:\Users\carpat\Desktop\Check-RouteTables.ps1",

    $executionInterval = (New-TimeSpan -Minutes 1),

    $jobname = 'Check for UDR tables'
)

# Initializations
$ErrorActionPreference = 'Stop'

$action = New-ScheduledTaskAction –Execute "$pshome\powershell.exe" -Argument  "$pathOfScriptToExecute; quit" # Create task action

# Create task trigger
$duration = ([timeSpan]::maxvalue)
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval $executionIntervalMins -RepetitionDuration $duration
 
 # Create schedule task settings
#$msg = "Enter the username and password that will run the task"; 
#$credential = $Host.UI.PromptForCredential("Task username and password",$msg,"$env:userdomain\$env:username",$env:userdomain)
#$username = $credential.UserName
$username = 'NORTHAMERICA\carpat'
#$password = $credential.GetNetworkCredential().Password
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
 
# Register task
#Register-ScheduledTask -TaskName $jobname -Action $action -Trigger $trigger -RunLevel Highest -User $username -Password $password -Settings $settings
Register-ScheduledTask -TaskName $jobname -Action $action -Trigger $trigger -RunLevel Highest -User $username -Settings $settings