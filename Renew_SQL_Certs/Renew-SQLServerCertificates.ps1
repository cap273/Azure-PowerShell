param(
    
    #These are the list of all the VMs in the same SQL Server AlwaysOn Availability Group (SSAOAG)
    #Use the FQDN of target VMs
    $vmNames = @("comp1.com"
		 "comp2.com"
                 ),

    # The storage account name
    $storageAccountName = "stordevstde2usptobkp",
    
    # The storage account key
    $storageAccountKey = "storagekeyhere",

    # Credential
    $cred
)


###############
# Initializations
##############

$ErrorActionPreference = 'Stop'

##############
# Initial error checking
##############

# Check for the directory in which this script is running.
# All supporting scripts will be retrieved from this directory
if ( [string]::IsNullOrEmpty($PSScriptRoot) ) {
    throw "Please save this script before executing it."
}

# Ensure that all the VM names are in lower case (otherwise AzCopy might fail)
$numVMs = ($vmNames | Measure).Count

for ($i = 0; $i -lt $numVMs; $i++) {

    $vmNames[$i] = ($vmNames[$i]).ToString().ToLower()
}

################
# Constants
################

$certificateName = 'AutoBackup_Certificate'
$certificateSubject = 'Automatic Backup Certificate'

$oldCertificateFileName = 'Old_AutoBackup_Certificate'

$AzCopyPath = "C:\Program Files (x86)\Microsoft SDKs\Azure\AzCopy\AzCopy.exe"
$localCertificatePath = "E:\SQLBackup"

$certificatePassword = "W3lc0me0"

# The names of the three T-SQL scripts to execute on the target VMs
$dropOldCertScriptName = 'SQL_Drop_Old_Cert.sql' # Execute on all VMs
$createNewCertScriptName = 'SQL_Create_New_Cert.sql' # Execute on just 1 VM
$useExistingCertScriptName = 'SQL_Use_Existing_Cert.sql' # Execute on all but 1 VM

$sqlScriptsRootFolderTargetVM = "C:\MicrosoftScripts"


###############
# Give the account running this script full permissions over target directories
###############

# Parameters for Give-FullControlOverDir.ps1
$identities = @($cred.UserName)
$directories = @($localCertificatePath)


foreach ($vm in $vmNames) {

    try {

        Write-Host "Giving full control to current user $($cred.UserName) on directory holding backup certificates for VM: $vm..."

        Invoke-Command -ComputerName $vm `
                       -Credential $cred `
                       -FilePath "$PSScriptRoot\Give-FullControlOverDir.ps1" `
                       -ArgumentList $identities,`
                                     $directories #`
                       #-ErrorAction SilentlyContinue

        Write-Host "Permissions assigned."

    } catch {

        $ErrorMessage = $_.Exception.Message
    
        Write-Host "Give-FullControlOverDir.ps1 failed on VM: $vm."
        Write-Host "Error message:"
        throw "$ErrorMessage"
    }
}

###############
# Rename the backups of the existing certificates, and upload backups to Azure storage accounts
###############


foreach ($vm in $vmNames) {

    # If the FQDN of the VM was given, extract the VM hostname
    $pos = $vm.IndexOf(".")
    if ($pos -gt 0) {
        $hostname = $vm.Substring(0,$pos)
    } else {
        $hostname = $vm
    }

    try {

        Write-Host "Renaming the old certificate for encrypted backups on VM: $hostname..."

        $codeBlock = {

            param(
                [string] $localCertificatePath,
                [string] $certificateName,
                [string] $oldCertificateFileName
            )

            $SernerName = $env:COMPUTERNAME
            
            # Do *any* backup certificates
            if (Test-Path "$localCertificatePath\*.cer" ) {

                # If backup certificate does *not* have the server name in its certificate name
                if (Test-Path "$localCertificatePath\$certificateName.cer") {

                    Rename-Item -Path "$localCertificatePath\$certificateName.cer" `
                        -NewName "$localCertificatePath\$oldCertificateFileName.cer"

                    Rename-Item -Path "$localCertificatePath\$($certificateName)_private_key.key" `
                        -NewName "$localCertificatePath\$($oldCertificateFileName)_private_key.key"
                }

                # If the backup certificate *does* have the server name in its certificate
                if (Test-Path "$localCertificatePath\$($ServerName)_$certificateName.cer") {

                    Rename-Item -Path "$localCertificatePath\$($ServerName)_$certificateName.cer" `
                        -NewName "$localCertificatePath\$($ServerName)_$oldCertificateFileName.cer"

                    Rename-Item -Path "$localCertificatePath\$($ServerName)_$($certificateName)_private_key.key" `
                        -NewName "$localCertificatePath\$($ServerName)_$($oldCertificateFileName)_private_key.key"

                }
            }
        }

        Invoke-Command -ComputerName $vm `
                       -Credential $cred `
                       -ScriptBlock $codeBlock `
                       -ArgumentList $localCertificatePath,`
                                     $certificateName,`
                                     $oldCertificateFileName

        Write-Host "Successfully renamed old certificate for encrypted backups on VM: $hostname"

    } catch {

        $ErrorMessage = $_.Exception.Message
    
        Write-Host "Renaming old certificates failed on VM: $hostname."
        Write-Host "Error message:"
        throw "$ErrorMessage"
    }

    #### Upload old certificates to Azure using AzCopy

    try {

        Write-Host "Uploading old certificates for encrypted backups on VM: $hostname to Azure storage account..."

        # Define parameters
        $Dest = "https://$storageAccountName.blob.core.windows.net/$hostname-systemdbbkp"
        $FileToUploadCert = "$oldCertificateFileName.cer"
        $FileToUploadKey = "$($oldCertificateFileName)_private_key.key"

        # Only upload if certificates exist in the first place
        # Uploading certificate
        Invoke-Command -ComputerName $vm `
                        -Credential $cred `
                        -FilePath "$PSScriptRoot\Upload-UsingAzCopy.ps1" `
                        -ArgumentList $localCertificatePath,`
                                        $Dest,`
                                        $FileToUploadCert,`
                                        $storageAccountKey,`
                                        $AzCopyPath


        # Uploading certificate KEY
        Invoke-Command -ComputerName $vm `
                        -Credential $cred `
                        -FilePath "$PSScriptRoot\Upload-UsingAzCopy.ps1" `
                        -ArgumentList $localCertificatePath,`
                                        $Dest,`
                                        $FileToUploadKey,`
                                        $storageAccountKey,`
                                        $AzCopyPath


        # Define parameters
        $Dest = "https://$storageAccountName.blob.core.windows.net/$hostname-systemdbbkp"
        $FileToUploadCert = "$($ServerName)_$oldCertificateFileName.cer"
        $FileToUploadKey = "$($ServerName)_$($oldCertificateFileName)_private_key.key"

        # Only upload if certificates exist in the first place
        # Uploading certificate
        Invoke-Command -ComputerName $vm `
                        -Credential $cred `
                        -FilePath "$PSScriptRoot\Upload-UsingAzCopy.ps1" `
                        -ArgumentList $localCertificatePath,`
                                        $Dest,`
                                        $FileToUploadCert,`
                                        $storageAccountKey,`
                                        $AzCopyPath


        # Uploading certificate KEY
        Invoke-Command -ComputerName $vm `
                        -Credential $cred `
                        -FilePath "$PSScriptRoot\Upload-UsingAzCopy.ps1" `
                        -ArgumentList $localCertificatePath,`
                                        $Dest,`
                                        $FileToUploadKey,`
                                        $storageAccountKey,`
                                        $AzCopyPath

        Write-Host "Successfully uploaded any existing old certificates to Azure storage account for VM: $hostname"


    } catch {

        $ErrorMessage = $_.Exception.Message
    
        Write-Host "Uploading old certificates to Azure failed on VM: $hostname."
        Write-Host "Error message:"
        throw "$ErrorMessage"
    }
}


###############
# Drop old certificate from all SQL Server nodes
###############


foreach ($vm in $vmNames) {

    # If the FQDN of the VM was given, extract the VM hostname
    $pos = $vm.IndexOf(".")
    if ($pos -gt 0) {
        $hostname = $vm.Substring(0,$pos)
    } else {
        $hostname = $vm
    }

    try {

        Write-Host "Copying T-SQL script to drop old certificate to target VM: $hostname."

        Copy-Item -Path "$PSScriptRoot\$dropOldCertScriptName" -Destination "\\$vm\C$\MicrosoftScripts" -Recurse

        Write-Host "Dropping old certificate for encrypted backups on VM: $hostname..."

        $codeBlock = {

            param(
                [string] $sqlScriptsRootFolderTargetVM,
                [string] $dropOldCertScriptName,
                [string] $certificateName
            )
            
            # Location of script
            $DBScriptFile = "$sqlScriptsRootFolderTargetVM\$dropOldCertScriptName"

            # Pass the name of the certificate as a parameter to the SQL script
            $Params = "certificateName=" + "$certificateName"

            # Run script as SQLCMD
            Invoke-Sqlcmd -InputFile $DBScriptFile `
                          -ServerInstance $env:COMPUTERNAME `
                          -Database "master" `
                          -Variable $Params `
                          -QueryTimeout 120

        }

        Invoke-Command -ComputerName $vm `
                       -Credential $cred `
                       -ScriptBlock $codeBlock `
                       -ArgumentList $sqlScriptsRootFolderTargetVM,`
                                     $dropOldCertScriptName,`
                                     $certificateName

        Write-Host "Successfully dropped old certificate for encrypted backups on VM: $hostname"

    } catch {

        $ErrorMessage = $_.Exception.Message
    
        Write-Host "Dropping old certificate failed on VM: $hostname."
        Write-Host "Error message:"
        throw "$ErrorMessage"
    }
}


##########################
# Create new certificate in one VM, and distribute to all other VMs
##########################

$numVMs = ($vmNames | Measure).Count

for($i = 0; $i -lt $numVMs; $i++) {

    # Extract current VM
    $vm = $vmNames[$i]

    # If the FQDN of the VM was given, extract the VM hostname
    $pos = $vm.IndexOf(".")
    if ($pos -gt 0) {
        $hostname = $vm.Substring(0,$pos)
    } else {
        $hostname = $vm
    }

    # If we are at the first VM, use this VM to create a new certificate
    # All other VMs will get THIS certificate
    if ($i -eq 0) {
        try {

            Write-Host "Copying T-SQL script to create new certificate to target VM: $hostname."

            Copy-Item -Path "$PSScriptRoot\$createNewCertScriptName" -Destination "\\$vm\C$\MicrosoftScripts" -Recurse

            Write-Host "Creating new certificate for encrypted backups on VM: $hostname..."

            $codeBlock = {

                param(
                    [string] $sqlScriptsRootFolderTargetVM,
                    [string] $createNewCertScriptName,
                    [string] $localCertificatePath,
                    [string] $certificatePassword
                )
            
                # Location of script
                $DBScriptFile = "$sqlScriptsRootFolderTargetVM\$createNewCertScriptName"

                # Pass the name, subject, and folder path of the certificate as a parameter to the SQL script
                $Param1 = "certificateFolder=" + "$localCertificatePath"
                $Param2 = "certificatePassword=" + "$certificatePassword"
                $Params = $Param1, $Param2

                # Run script as SQLCMD
                Invoke-Sqlcmd -InputFile $DBScriptFile `
                              -ServerInstance $env:COMPUTERNAME `
                              -Database "master" `
                              -Variable $Params `
                              -QueryTimeout 120

            }

            Invoke-Command -ComputerName $vm `
                           -Credential $cred `
                           -ScriptBlock $codeBlock `
                           -ArgumentList $sqlScriptsRootFolderTargetVM,`
                                         $createNewCertScriptName,`
                                         $localCertificatePath,`
                                         $certificatePassword

            Write-Host "Successfully created and backed up new certificate for encrypted backups on VM: $hostname"

            Write-Host "Copying certificate and its private key onto local computer"

            Copy-Item -Path "\\$vm\E$\SQLBackup\$certificateName.cer" -Destination "$PSScriptRoot"
            Copy-Item -Path "\\$vm\E$\SQLBackup\$($certificateName)_private_key.key" -Destination "$PSScriptRoot"
            
            Write-Host "Successfully copied certificate and its private key onto local computer"

        } catch {

            $ErrorMessage = $_.Exception.Message
    
            Write-Host "Creating new certificate and backing up failed on VM: $hostname."
            Write-Host "Error message:"
            throw "$ErrorMessage"
        }
    }

    # After the certificate has been created, distribute and install
    # on all other nodes
    else {
        try {

            Write-Host "Copying T-SQL script to install existing certificate to target VM: $hostname."

            Copy-Item -Path "$PSScriptRoot\$useExistingCertScriptName" -Destination "\\$vm\C$\MicrosoftScripts" -Recurse

            Write-Host "Copying existing certificate and private key..."

            Copy-Item -Path "$PSScriptRoot\$certificateName.cer" -Destination "\\$vm\E$\SQLBackup"
            Copy-Item -Path "$PSScriptRoot\$($certificateName)_private_key.key" -Destination "\\$vm\E$\SQLBackup"


            Write-Host "Installing existing certificate for encrypted backups on VM: $hostname..."

            $codeBlock = {

                param(
                    [string] $sqlScriptsRootFolderTargetVM,
                    [string] $useExistingCertScriptName,
                    [string] $localCertificatePath,
                    [string] $certificatePassword
                )
            
                # Location of script
                $DBScriptFile = "$sqlScriptsRootFolderTargetVM\$useExistingCertScriptName"

                # Pass the folder and password of the certificate as a parameter to the SQL script
                $Param1 = "certificateFolder=" + "$localCertificatePath"
                $Param2 = "certificatePassword=" + "$certificatePassword"
                $Params = $Param1, $Param2

                # Run script as SQLCMD
                Invoke-Sqlcmd -InputFile $DBScriptFile `
                              -ServerInstance $env:COMPUTERNAME `
                              -Database "master" `
                              -Variable $Params `
                              -QueryTimeout 120

            }

            Invoke-Command -ComputerName $vm `
                           -Credential $cred `
                           -ScriptBlock $codeBlock `
                           -ArgumentList $sqlScriptsRootFolderTargetVM,`
                                         $useExistingCertScriptName,`
                                         $localCertificatePath,`
                                         $certificatePassword
            
            # Clean up the extra certificates creates as backups
            Remove-Item -Path "\\$vm\E$\SQLBackup\$($certificateName)_dummy.cer"
            Remove-Item -Path "\\$vm\E$\SQLBackup\$($certificateName)_private_key_dummy.key"

            Write-Host "Successfully installed existing certificate for encrypted backups on VM: $hostname"

        } catch {

            $ErrorMessage = $_.Exception.Message
    
            Write-Host "Installing existing certificate failed on VM: $hostname."
            Write-Host "Error message:"
            throw "$ErrorMessage"
        }
    }
}

##########################
# Minor cleanup activities
##########################

# Clean up the extra certificates creates as backups
Remove-Item -Path "$PSScriptRoot\$certificateName.cer"
Remove-Item -Path "$PSScriptRoot\$($certificateName)_private_key.key"


##########################
# Upload the new certificates to Azure storage accounts
##########################

foreach ($vm in $vmNames) {

    # If the FQDN of the VM was given, extract the VM hostname
    $pos = $vm.IndexOf(".")
    if ($pos -gt 0) {
        $hostname = $vm.Substring(0,$pos)
    } else {
        $hostname = $vm
    }

    try {

        Write-Host "Uploading new certificates for encrypted backups on VM: $hostname to Azure storage account..."

        # Define parameters
        $Dest = "https://$storageAccountName.blob.core.windows.net/$hostname-systemdbbkp"
        $FileToUpload = "$certificateName.cer"

        # Uploading certificate
        Invoke-Command -ComputerName $vm `
                       -Credential $cred `
                       -FilePath "$PSScriptRoot\Upload-UsingAzCopy.ps1" `
                       -ArgumentList $localCertificatePath,`
                                     $Dest,`
                                     $FileToUpload,`
                                     $storageAccountKey,`
                                     $AzCopyPath

        # Define parameters
        $FileToUpload = "$($certificateName)_private_key.key"

        # Uploading certificate KEY
        Invoke-Command -ComputerName $vm `
                       -Credential $cred `
                       -FilePath "$PSScriptRoot\Upload-UsingAzCopy.ps1" `
                       -ArgumentList $localCertificatePath,`
                                     $Dest,`
                                     $FileToUpload,`
                                     $storageAccountKey,`
                                     $AzCopyPath

        Write-Host "Successfully uploaded new certificate to Azure storage account for VM: $hostname"

    } catch {

        $ErrorMessage = $_.Exception.Message
    
        Write-Host "Uploading new certificates to Azure failed on VM: $hostname."
        Write-Host "Error message:"
        throw "$ErrorMessage"
    }
}