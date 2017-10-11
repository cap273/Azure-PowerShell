<#
    Definitions:
    
    - Local VM: The VM from which this PowerShell script is running. This will become 
                a CredSSP client.

    - Target VM: The VM into which PowerShell code will be remotely executed using
                 Invoke-Command. This VM will become a CredSSP server.
#>

param(
    
    # Define the FQDN of the target VM
    $vm

)

# Make all errors terminating so that try/catch blocks may work in PowerShell
$ErrorActionPreference = 'Stop'

# Prompt the user for a domain credential that will have access to the target VM
$cred = Get-Credential

<#
Function to disable CredSSP authentication
This will be run either as a clean-up activity at the end of the script,
or will be run if any errors are thrown during the script execution.
#>
function Disable-CredSSP {
    
    param(
        [string] $vm,
        $cred
    )

    # Disable Util server as the CredSSP Client
    Write-Host "Disabling current VM as CredSSP client...."
    Disable-WSManCredSSP -Role Client

    # Disable the target VM as the CredSSP Server
    Write-Host "Disabling target VM as CredSSP server..."
    Invoke-Command -ComputerName $vm `
                   -Credential $cred `
                   -SessionOption (New-PSSessionOption -IdleTimeout 120000) `
                   -ScriptBlock { Disable-WSManCredSSP -Role Server }
}


<#
Configuring local and target VM for CredSSP authentication

Double-hop authentication is, by default, not allowed using Kerberos authentication.
Use CredSSP authentication so that the target VM can use the user's credentials 
to authenticate to another remote computer.
#>
try {

    # Enable Util server as the CredSSP Client
    Write-Host "Setting local VM as CredSSP Client..."
    Enable-WSManCredSSP -Role Client -DelegateComputer $vm -Force | Out-Null

    # Enable the target VM as the CredSSP Server
    # Use IdleTimeout of 120,000 milliseconds (2 mins)
    Write-Host "Setting target VM as CredSSP Server..."
    Invoke-Command -ComputerName $vm `
                   -Credential $cred `
                   -SessionOption (New-PSSessionOption -IdleTimeout 120000) `
                   -ScriptBlock { Enable-WSManCredSSP -Role Server -Force | Out-Null }

} catch {

    $ErrorMessage = $_.Exception.Message
    
    Write-Host "Configuring CredSSP authentication between local and target VM failed with error message:"
    throw "$ErrorMessage"

}




####################################
# MAIN PART OF SCRIPT
####################################

# Define the code that will run on target VM
# Instead of defining code here, you could reference another PowerShell script
$codeBlock = {

    param(

        [string]$testParam
    )

    Write-Host "The parameter is: $testParam"
}

# Actually try and execute remote PowerShell commands using CredSSP as the authentication option
try{

    $testParam = "testValue"

    Invoke-Command -ComputerName $vm `
                   -Credential $cred `
                   -Authentication Credssp `
                   -ScriptBlock $codeBlock `
                   -ArgumentList $testParam

} catch {

    $ErrorMessage = $_.Exception.Message
    
    Write-Host "Execution of remote PowerShell commands on target VM failed."

    # Run the function to disable CredSSP on the local and target VM, to make sure
    # this setting is not mistakenly forgotten.
    Disable-CredSSP -vm $vm -cred $cred

    Write-Host "Error message:"
    throw "$ErrorMessage"
}



####################################
# Cleanup
####################################

# After any activities are complete, disable CredSSP on local and target VM
Disable-CredSSP -vm $vm -cred $cred
