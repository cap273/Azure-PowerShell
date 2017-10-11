param(
    
    # The path and file name of the CSV file to where the audit results will be stored
    $csvFilePath = "C:\temp\mcafeeaudit.csv",
     
    # An array of the computers to query for their McAfee status
    $VMNames = @("testVM1",
                 "testVM2"
                )
)



#####################
# Initializations
#####################

$ErrorActionPreference = 'Continue'

<#
# Alternatively, instead of specifying the list get a list of VMs in the $VMNames parameter, find *ALL* of the VM names 
# in a particular Organizational Unit (OU)
$VMNames = Get-ADComputer -SearchBase 'OU=testOU,DC=testDomain,DC=testHigherDomain,DC=com' `
                          -Filter 'ObjectClass -eq "Computer" -and Name -like "testNamePrefix*"' | `
                          Select -Expand DNSHostName
#>


########################################################################################
# Define the code block to be run locally (through Invoke-Command) on each target VM
#######################################################################################
$codeBlock = {


    # Get server name
    $ServerName = $env:COMPUTERNAME # Name of the local computer.

    # Define an array of the names of all the McAfee services for which to check
    $namesOfMcAfeeServices = @("McAfeeFramework",
                               "McShield",
                               "McTaskManager",
                               "mfevtp")

    # Initialize an array with the status of each of the McAfee services defined above.
    $statusOfMcAfeeServices = @("Unknown",
                                "Unknown",
                                "Unknown",
                                "Unknown")
    
    # Loop through each McAfee service
    for($i=0; $i -lt ($namesOfMcAfeeServices | Measure).Count; $i++) {

        # Get the McAfee service name, and the McAfee service object
        $mcAfeeService = $namesOfMcAfeeServices[$i]
        $service = $null
        $service = Get-Service -Name $mcAfeeService -ErrorAction SilentlyContinue
        $displayname = $service.DisplayName

        # Logic to determine the state of the McAfee service
        if ( $service -eq $null ) {
        
            $statusOfMcAfeeServices[$i] = "Nonexistent"
            Write-Host "The service $mcAfeeService does not exist in this computer."

        } elseif ( $service.Status -eq "Stopped" ) {
        
            $statusOfMcAfeeServices[$i] = "Stopped"
            Write-Host "$displayname exists, but is in a Stopped state."

        } elseif ( $service.Status -eq "Running" ) {

            $statusOfMcAfeeServices[$i] = "Running"
            Write-Host "$displayname is running."

        } else {

            $service
            Write-Host "Unknown state"
        }

    }

    # Return the state of each McAfee service as a hashtable
    New-Object -TypeName PSCustomObject `
               -Property @{
                             Host                                   =  $env:COMPUTERNAME;
                             McAfeeFrameworkStatus                  =  $statusOfMcAfeeServices[0];
                             McAfeeMcShieldStatus                   =  $statusOfMcAfeeServices[1];
                             McAfeeTaskManagerStatus                =  $statusOfMcAfeeServices[2];
                             McAfeeValidationTrustProtectionStatus  =  $statusOfMcAfeeServices[3];
                           }


}


#############################
# Main Body 
#############################

# Prompt the user for a domain credential that will have access to all of the VMs
$cred = Get-Credential

# Initialize an empty array to store the the output from each VM
$auditresults = @()

# If a previous audit file already exists in the specified location, delete it.
if (Test-Path $csvFilePath)
{
    Remove-Item -Path $csvFilePath
}


# Loop through all VMs.
foreach ($vm in $VMNames){
    echo "`n Processing $vm"

    try{
        # Check the status of McAfee on an individual VM, and add the results to an array
        $auditresults += Invoke-Command -ComputerName $vm -Credential $cred -ScriptBlock $codeBlock
    }
    catch {
        Write-Host "Connecting to this computer failed. This is probably because this VM does not exist anymore."
    }

}

Write-Host "McAfee Audit completed. Storing results to CSV file located in $csvFilePath"

# Store the results of the audit in a CSV file
$auditresults | Export-Csv -Path $csvFilePath
