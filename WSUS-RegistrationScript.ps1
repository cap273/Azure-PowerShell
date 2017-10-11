param(
    # Define the path of the log file where any errors will be recorded.
    $logfile = "C:\WSUS-Registry-ErrorLogFile.log",

    # Define the location of the registry file to be added to target computer
    $registryFile = "\\repo\WSUS-Settings.reg",

    # Array of the names of VMs to be registered with WSUS server
    $VMNames = @("comp1.domain.com",
		 "comp2.domain.com")
)

#####################
# Initializations
#####################

$ErrorActionPreference = 'Stop'

<#
# Alternatively, get a list of *ALL* of the VM names in the Clients Organizational Unit (OU)
$VMNames = Get-ADComputer -SearchBase 'OU=Clients,DC=Cloud,DC=com' `
                          -Filter 'ObjectClass -eq "Computer" -and Name -like "hazr*"' | `
                          Select -Expand DNSHostName
#>

# Define the function to be used to write errors to log file
Function LogWrite
{
    Param ([string]$logstring)

    Add-Content $Logfile -Value $logstring
}

# Define the code block to be run locally (through Invoke-Command) on each target VM
$codeBlock = {

    <#
    Silently add the registry entry to the target computer
    Note that the registry file should have already been copied 
    to the location below before attemtping to run this line
    #>
    regedit /s "C:\Windows\Temp\WSUS-Settings.reg"

    # Restart the Windows Update service
    Restart-Service wuauserv -Force

    sleep 2

    # Force target computer to register now with the WSUS Server
    wuauclt /detectnow
}

#############################
# Main Body
#############################

# Prompt the user for a domain credential that will have access to all of the VMs
$cred = Get-Credential

# Loop through all VMs.
foreach ($vm in $VMNames){
    echo "`n Processing $vm"
    
    try {
	
        # Copy the registry entry file into the destination VM.
        Copy-Item -Path $registryFile `
                  -Destination "\\$vm\c$\Windows\Temp\WSUS-Settings.reg" -Force
        
        # Get the name of the computer from its Fully Qualified Domain Name
        $vm = $vm.split(".")[0]

        # Run the block of code to add the registry entry
        Invoke-Command -ComputerName $vm -Credential $cred -ScriptBlock $codeBlock
    }
    catch {
        <#
            If any errors are found, display to the user
            and record the error in a log file
        #>

        $errormessage = $_.Exception.Message
        $faileditem = $_.Exception.ItemName

        LogWrite "Computer $vm failed with error message: $errormessage"
        # Write-Host "Computer $vm failed with error message: $errormessage"

        $errormessage
    }
}