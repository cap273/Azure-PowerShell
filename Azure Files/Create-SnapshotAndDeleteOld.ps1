param(
    $storageAccountName = "carlostestsnapshot",
    $storageAccountKey = "accountkeyhere",
    $fileShareName = "testcarlossnapshot",
    $daysBeforeDeleteSnapshot = 30
)

$ErrorActionPreference = 'Stop'

# Get storage context for this Azure storage account
$context = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey -Protocol Https

##################
# Delete files older than $daysBeforeDeleteSnapshot days
##################

# Get all shares (including main share and all of its snapshots) in the storage account that have the name specified 
# by the File Share Name
$shares = Get-AzureStorageShare -Context $context | Where-Object {$_.Name -eq $fileShareName}

# The Sort-Object command by default sorts on Ascending order. Therefore, $orderedSnapshots[0] will contain the earliest Snapshot
$orderedSnapshots = ($shares | Where-Object {$_.IsSnapshot -eq $true} | Sort-Object SnapshotTime)

$numSnapshots = ($orderedSnapshots | Measure).Count

# Initialize while-loop variables
$isTooOld = $true # Assume by default that this Snapshot is too old and should be deleted. When this Snapshot in the ordered list is *not* too old, end while-loop
$k = 0 # Index for $orderedSnapshots array

# Precondition: $orderedSnapshots is empty, OR is an array of Share objects that only consist of Snapshots. $orderedSnapshots is ordered by
# SnapshotTime in Ascending order, such that the earliest-created Shapshot (i.e. the oldest Shapshot) appears in index 0 (i.e. $orderedSnapshots[0])
while ($isTooOld)
{
    # Exit from this while-loop if all Snapshots have been examined
    if ($k -ge $numSnapshots)
    {
        break
    }
    
    # If the Snapshot contained in $orderedSnapshots[$k] is older than $daysBeforeDeleteSnapshot days, delete it, and then continue looking for the next Snapshot
    if (  $orderedSnapshots[$k].SnapshotTime -lt (Get-Date).ToUniversalTime().AddDays(-$daysBeforeDeleteSnapshot)  )
    {
        Remove-AzureStorageShare -Share $orderedSnapshots[$k]

        # Update index for $orderedSnapshots array to look for next oldest Snapshot
        $k++
    }

    # If the Snapshot contained in in $orderedSnapshots[$k] is *not* older than $daysBeforeDeleteSnapshot days, end while-loop
    else 
    {

        $isTooOld = $false
    }

}


##################
# Create a new snapshot
##################

# Check that there are less than 200 Snapshots already existing
# Reference: https://docs.microsoft.com/en-us/azure/storage/files/storage-snapshots-files#limits
# If there is, throw an error
$prunedShares = Get-AzureStorageShare -Context $context | Where-Object {$_.Name -eq $fileShareName}
$prunedSnapshots = $shares | Where-Object {$_.IsSnapshot -eq 'True'}
$numPrunedSnapshots = ($prunedSnapshots | Measure).Count

if ($numPrunedSnapshots -ge 200)
{
    throw "Too many Snapshots already exist. Number of current Snapshots: $numPrunedSnapshots. See Azure Files snapshots limits."
}

# Get the Share (which is not a Snapshot)
$share=Get-AzureStorageShare -Context $context -Name $fileShareName

# Verify that this share is indeed not itself a Snapshot
if($share.IsSnapshot -eq $true) { throw "Error: retrieved share from which to create snapshot is already a snapshot." }

# Actually create the snapshot
$snapshot=$share.Snapshot()

# Output share information
Write-Output "New snapshot successfully created. Snapshot time: $($snapshot.SnapshotTime)"
