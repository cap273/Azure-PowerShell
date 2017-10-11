####################
# Wrapper function around the function Renew-SQLServerCertificates.ps1
###################

param (
    
    # The full path that points to the CSV file containining the list of VMs
    $listOfObjectsPath = "C:\Users\vn51066\Desktop\Renew_SQL_Certs\ListSQLServerWithEncryptedBackup_Edited.csv"
)

# Get appropriate credentials
Write-Host "Enter the credentials that will be used to access all of the SQL Server VMs..."
$cred = Get-Credential

cls

# Get the list of objects from the CSV file
$listOfObjects = Import-Csv -Path $listOfObjectsPath

# Record the number of objects in this list
$numObjects = ($listOfObjects | Measure).Count

# Initialize variables
$previousStorageAccount = $null
$previousStorageAccountKey = $null

$thisVMName = $null
$thisStorageAccount = $null
$thisStorageAccountKey = $null

# Initialize a list to hold a single set of VMs (where a 'set' is a group of VMs doing SQL Server backups to the same storage account)
$thisArrayOfVMNames = New-Object System.Collections.Generic.List[System.Object]

for($i = 0; $i -lt $numObjects; $i++) {

    # Get the properties of this object
    $thisObject = $listOfObjects[$i]

    $thisVMName = $thisObject.Host
    $thisStorageAccount = $thisObject.StorageAccountName
    $thisStorageAccountKey = $thisObject.StorageAccountKey

    
    if( ($thisStorageAccount -eq $previousStorageAccount) -or ($i -eq 0)) {

        # If this is the first item in the list, OR if this VM is part of the previous VM set, add it to the list
        $thisArrayOfVMNames.Add($thisVMName)

    } else {

        # If this current VM marks the beginning of a new set, collect the previous set of VMs
        # and call the function Renew-SQLServerCertificates
        
        # Convert list to array
        $thisArrayOfVMNames.ToArray() | Out-Null

        # Call other function
        Write-Host "Working on VM set: $thisArrayOfVMNames `n" -ForegroundColor Cyan -BackgroundColor Black

        $ScriptPath = Split-Path $MyInvocation.InvocationName
        & "$ScriptPath\Renew-SQLServerCertificates.ps1" -vmNames $thisArrayOfVMNames `
                                                        -storageAccountName $previousStorageAccount `
                                                        -storageAccountKey $previousStorageAccountKey `
                                                        -cred $cred

        # For now, just print
        #$thisArrayOfVMNames

        Write-Host "Finished working on this VM set.`n" -ForegroundColor Green -BackgroundColor Black

        # Clear array of VMs
        $thisArrayOfVMNames = New-Object System.Collections.Generic.List[System.Object]

        # Add the current host name to the new array, representing a new VM set
        $thisArrayOfVMNames.Add($thisVMName)

    }

    # Set the properties of the last object in the list
    $previousStorageAccount = $thisStorageAccount
    $previousStorageAccountKey = $thisStorageAccountKey

}

# After the for-loop is finished, do the last set of VMs
$ScriptPath = Split-Path $MyInvocation.InvocationName
& "$ScriptPath\Renew-SQLServerCertificates.ps1" -vmNames $thisArrayOfVMNames `
                                                -storageAccountName $previousStorageAccount `
                                                -storageAccountKey $previousStorageAccountKey `
                                                -cred $cred

Write-Host "Finished working all VM sets.`n" -ForegroundColor Green -BackgroundColor Black