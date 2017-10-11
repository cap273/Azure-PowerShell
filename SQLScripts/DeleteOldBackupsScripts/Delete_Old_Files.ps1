## to run from command prompt use    .\delete_old_files.ps1 4 "trn"

param (
    [int] $retention_period_in_days = 3
    , [string]$file_extensions_CSV = ""
    , [string]$blobContainer = ""
 	, [string]$storageAccount = "storage_account_name"     
    , [string]$storageKey = "Primary_Storage_Key"                        
)

Push-Location
$errorCode = 0

$host_output = 'Parameters Values are:' + [char]13 + [char]10
$host_output =  $host_output + '$retention_period_in_days = ' + $retention_period_in_days.ToString() + [char]13 + [char]10
$host_output =  $host_output + '$file_extensions_CSV = ' + $file_extensions_CSV + [char]13 + [char]10
$host_output =  $host_output + '$blobContainer = ' + $blobContainer + [char]13 + [char]10
$host_output =  $host_output + '$storageAccount = ' + $storageAccount + [char]13 + [char]10
$host_output =  $host_output + '$storageKey = ' + $storageKey + [char]13 + [char]10

Write-Host $host_output

# How long backups will be retained
if (($retention_period_in_days -eq $null) -or ($retention_period_in_days -lt 1)) { 
	$retention_period_in_days = 3
    $host_output = "Retention for backup and log files =  " + $retention_period_in_days.ToString() + " days" + [char]13 + [char]10
    Write-Host $host_output
}

if (($file_extensions_CSV -eq $null) -or ($file_extensions_CSV -eq ""))
{
    $file_extensions_CSV = "bak,trn,bakdiff"
    $host_output = "Extensions for Backup files that will be removed are  " + $file_extensions_CSV + [char]13 + [char]10
    Write-Host $host_output
}

$FullComputer = Get-WmiObject -Class Win32_ComputerSystem
$Computer=$FullComputer.Name.ToLower()
if (($blobContainer -eq $null) -or ($blobContainer -eq "")) 
{   
    $blobContainer = $Computer
    $host_output = "Container name is  " + $Computer + [char]13 + [char]10
    Write-Host $host_output
}


$backupUrlContainer = "https://$storageAccount.blob.core.windows.net/$blobContainer/"

#$storageAssemblyPath = "C:\Program Files\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\Binn\Microsoft.WindowsAzure.Storage.dll"
# for company-specific SQL Server configuration:
$storageAssemblyPath = "E:\SQLSys\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\Binn\Microsoft.WindowsAzure.Storage.dll"

$isOldDate = [DateTime]::UtcNow.AddDays(-1 * $retention_period_in_days)

# Well known Restore Lease ID
$restoreLeaseId = "BAC2BAC2BAC2BAC2BAC2BAC2BAC2BAC2"


# Load the storage assembly without locking the file for the duration of the PowerShell session
$bytes = [System.IO.File]::ReadAllBytes($storageAssemblyPath)
[System.Reflection.Assembly]::Load($bytes)

$cred = New-Object 'Microsoft.WindowsAzure.Storage.Auth.StorageCredentials' $storageAccount, $storageKey

$client = New-Object 'Microsoft.WindowsAzure.Storage.Blob.CloudBlobClient' "https://$storageAccount.blob.core.windows.net", $cred

$container = $client.GetContainerReference($blobContainer)
Write-Host "Current Container is" $container.Name

#list all the blobs
$allBlobs = $container.ListBlobs() 
$deleted_blobs = 0
$bad_blobs = 0

foreach($blob in $allBlobs)
{
#   
    $blobProperties = $blob.Properties 
    $name = $blob.Name

    if($blobProperties.LastModified.UtcDateTime -lt $isOldDate)
    {
        # check proper file extension
        $dbu = $file_extensions_CSV.Split(",")
        $found = 0
        foreach ($ext in $dbu) {
            $ext1="." + $ext
 	        if ($name.EndsWith($ext1)) {
                $found = 1
            }
        }
        if ($found -eq 1)
        {
            # check files' LeaseStatus
            if($blobProperties.LeaseStatus -ne "Locked")
            {          
                try
                {
                    write-host "Deleting file " $name  
                    $blob.Delete()
                    $deleted_blobs = $deleted_blobs + 1
                }
                catch
                {
                    write-host "Could not delete file " $name
                    $errorCode = 1
                    $bad_blobs = $bad_blobs + 1
                }
            }
            else
            {
                # breaking file lease
                try
                {
                    $blob.AcquireLease($null, $restoreLeaseId, $null, $null, $null)
                    Write-Host "The lease on $($blob.Uri) is a restore lease"
                }
                catch [Microsoft.WindowsAzure.Storage.StorageException]
                {
                    if($_.Exception.RequestInformation.HttpStatusCode -eq 409)
                    {
                        Write-Host "The lease on $($blob.Uri) is not a restore lease"
                    }
                }

                Write-Host "Breaking lease on $($blob.Uri)"
                $blob.BreakLease($(New-TimeSpan), $null, $null, $null) | Out-Null

                try
                {
                    write-host "Deleting file " $name  
                    $blob.Delete()
                    $deleted_blobs = $deleted_blobs + 1
                }
                catch
                {
                    write-host "COuld not delete file " $name
                    $bad_blobs = $bad_blobs = 1
                    $errorCode = 1
                }
            
            }
        }
    }
}
write-host $deleted_blobs.ToString() " old files have been deleted"

Pop-Location

$host_output = ' '+ [char]13 + [char]10  
$host_output = $host_output + 'end of job'+ [char]13 + [char]10  
$host_output = $host_output + 'Deleteing of old backup files from server ' + $Computer + ' ended at ' + ([System.DateTime]::Now).ToString() + [char]13 + [char]10  
$host_output = $host_output + 'error code=' + $errorCode.ToString() + [char]13 + [char]10  
Write-Host $host_output

#check error code
if ($errorCode -gt 0) {
    # Exit with Return Code when NOT using PowerShell ISE
    if ($psise -eq $Null) {
		$host.SetShouldExit($errorCode)
		throw $_
    }
    else {
        throw $_
    }
}
exit $errorCode

         


