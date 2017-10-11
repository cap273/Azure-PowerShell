<#

.NAME
	Pre-SQL-Installation-Config
	
.DESCRIPTION 
    Configures a newly-provisioned VM for a clean SQL Server installation.
    The following features are configured, according to user input and SQL Server
    best practices and typical conventions:
    - Physical Disks are Initialized and Formatted into Volumes
    - Each Volume is associated with a particular SQL file type, which are:
        System Databases (SQLSys)
        User Databases (SQLData)
        User Database Logs and TempDB Logs (SQLLog)
        TempDB databases (TempDB)
    - Each volume is appropriately formatted
    - Appropriate directories are created in each new volume.
    - .NET Framework 3.5 is installed.
    - AD DS and AD LDS Tools, and Failover Clustering, is installed.
    - Certain firewall rules are created.

    PRECONDITION: several Azure data disks have already been attached to the VM. These data disks
        already have the desired Cache setting configured ('None' for disks intended for SQL Server Log 
        files, and 'Read Only' for disks intended for all other types of files)

.NOTES
    AUTHOR: Carlos Patiño
    LASTEDIT: April 1, 2016
#>

param (
    [String]
    $DotNet35SourcePath = "\\destinationVM\Source\dotnet35source\sxs\",

    [int]
    $SQLServerPort = 1433,

    [int]
    $SQLListenerPort = 1434,

    [int]
    $ILBProbePort = 59999
    )

##############################################
# Define function to prompt user for input
########################################
<# In PowerShell, functions must be defined before
   they are invoked. #>

Function Prompt-User {
    <#
    .NAME
        Prompt-User

    .DESCRIPTION
        Prompt-User can be leveraged to get input from the user

    .PARATEMETER PromptQuestion
        The text to display for the user.

    .PARAMETER maxint
        Usually this function prompts the user for input in the form of an integer.
        If an integer is given, the input is considered invalid if that integer is
        bigger than maxint

    #>
    param(
        $PromptQuestion,
        $DefaultAnswer = $null,
        [switch]$allowNulls,
        $matchstring = $null,
        $maxint
    )

    $qcount = 0;
    do{
        cls
        if ($qcount -gt 0){
            Write-Host "I'm sorry, you must answer the question correctly..." -BackgroundColor Black -ForegroundColor Red
        }
        
        $qcount++
        $isnull = $false
        $ismatch = $false
        $answered = $false
        $inmax = $false
        if ($DefaultAnswer -ne $null -and $qcount -lt 1){
            $PromptQuestion = $PromptQuestion + " [$DefaultAnswer]"
        }
        
        $result = Read-Host -Prompt $PromptQuestion
        #get test results
        if ($result -eq $null -or $result -eq ""){
            $isnull = $true
            $result = $null
        }
        if ($DefaultAnswer -ne $null -and $isnull -eq $true){
            $result = $DefaultAnswer
            $isnull = $false
        }
        if (($matchstring -ne $null) -and ($result -match $matchstring)){
            $ismatch = $true
        }
        if ($maxint -ne $null -and [int]$result -lt [int]$maxint){
            $inmax = $true
        }

        if ($allowNulls -eq $true){
            if ($isnull -eq $true){
                $answered = $true
            }
            elseif ($matchstring -ne $null -and $ismatch -eq $true){
                $answered = $true
            }
            elseif($matchstring -eq $null){
                $answered = $true
            }
        }
        else{
            if ($matchstring -ne $null -and $ismatch -eq $true){
                $answered = $true
            }
            elseif ($isnull -eq $false -and $matchstring -eq $null -and $maxint -eq $null){
                $answered = $true
            }
            elseif ($inmax -eq $true -and $isnull -eq $false){
                $answered = $true
            }
        }
    }while($answered -eq $false)
    return $result
}

Function Get-AvailablePhysicalDisks {
    <#

    .NAME
	    Get-AvailablePhysicalDisks.
	
    .SYNOPSIS 
        Get a list of all available physical disk

    .PARAMETER physicalDisks
        Contains information on ALL the physical disks attached to this VM
        An array of Objects, where each Object contains information
        about a single physical disk. The form of this variable is:
        physicalDisks[$i].FriendlyName
        physicalDisks[$i].SizeInGB
        physicalDisks[$i].InUse
        physicalDisks[$i].OriginalIndex
        physicalDisks[$i].SQLFileType

        InUse is a boolean that is $true when the user has already selected this
        disk to be used by a particular SQL file type. False otherwise.

        OriginalIndex, for the purposes of the $physicalDisks variable, is useless. However,
        another variable, which will become a subset of $physicalDisks, will
        use this index to identify a Physical Disks location in the $physicalDisks
        array.

        SQLFileType is the SQL file type to be associated with each disk. This is $false
        if the user has not made a choice yet.

    #>

    param (
            $physicalDisks
           )
    
    # Find the NUMBER of available physical disks
    $numAvailableDisks = 0
    for ($j=0; $j -lt ($physicalDisks | Measure).Count; $j++) 
    {

        if (  $physicalDisks[$j].InUse -eq $false   )
        {
            $numAvailableDisks++
        }
    }

    # Initialize an array with the number of available disks
    $availablePhysicalDisks = @($false) * $numAvailableDisks

    <# Loop through the entire list of physical disks again
       to copy each available disk's object into $availablePhysicalDisks #>
    $k = 0;
    for ($j=0; $j -lt ($physicalDisks | Measure).Count; $j++)
    {

        if (  $physicalDisks[$j].InUse -eq $false   )
        {
            
            # Copy properties over, preserving the structure of each Object in the physicalDisks array
            $properties = @{
                                            FriendlyName = $physicalDisks[$j].FriendlyName
                                            SizeInGB = $physicalDisks[$j].SizeInGB
                                            InUse = $physicalDisks[$j].InUse
                                            OriginalIndex = $false
                                            SQLFileType = $physicalDisks[$j].SQLFileType
                          }

            
            $availablePhysicalDisks[$k] = New-Object -TypeName PSObject -Property $properties


            # Record the index of this disk in $physicalDisks
            # This index will be necessary so that the InUse property 
            # in $physicalDisks can be updated.
            $availablePhysicalDisks[$k].OriginalIndex = $j

            # Update counter
            $k++
        }
    }


    return $availablePhysicalDisks
}

Function Create-FirewallRule {
    <#
    .NAME
        Create-FirewallRule

    .DESCRIPTION
        Create a new Allow Inbound firewall rule with a specified Name, Port, and Protocol.
        Only create the rule if it does not already exist.

    .PARATEMETER firewallPort
        The firewall port to open up.

    .PARAMETER firewallRuleName
        The display name of the new firewall rule.

    .PARAMETER protocol
        The transport layer protocol to be used for the new firewall rule. Only TCP or UDP allowed.

    #>
    param(
        
        [int]
        $firewallPort = "",

        [string]
        $firewallRuleName = "",

        [string]
        [ValidateSet('TCP','UDP')]
        $protocol = ""
    )

    Write-Host "Checking for $firewallRuleName firewall rule now...."
    if ( $(  Get-NetFirewallRule | Where {$_.DisplayName -eq $firewallRuleName } ) )
    {
        Write-Host "Firewall rule $firewallRuleName already exists, not creating new rule."
    }
    else
    {
        Write-Host "Firewall rule $firewallRuleName does not already exist, creating new rule now..."

        New-NetFirewallRule -DisplayName $firewallRuleName -Direction Inbound -Profile Domain,Private,Public `
                            -Action Allow -Protocol $protocol -LocalPort $firewallPort -RemoteAddress Any | Out-Null

        Write-Host "Firewall rule $firewallRuleName on $protocol port $firewallPort created successfully."
    }

}

########################################
# Initialize variables
########################################

# It appears that Try/Catch/Finally and Trap in PowerShell only works with terminating errors.
# Make all errors terminating
$ErrorActionPreference = "Stop"; 

# Define names for each type of SQL files
$sqlFileType = @(
                  "SQLSys",
                  "SQLData",
                  "SQLLog",
                  "TempDB"
                 )

<# 
Define an array of Objects. Each Object holds information about one SQL file type, in
     particular:
     1) The allowable volume letters that can be associated with each SQL file type.
     2) The allowable Volume File System Labels for eah SQL file type.
     3) The directory paths that can be created for each SQL file type
     4) The maximum number of volumes allowed for each SQL file type 
#>
$sqlFileTypeInfo = @(
                    New-Object -TypeName PSObject -Prop @{
                        # SQLSys
                        FileType = $sqlFileType[0]
                        Letter = "E"
                        Label = @("SQLSys")
                        MaxVolumes = 1
                     }

                    New-Object -TypeName PSObject -Prop @{
                        # SQLData
                        FileType = $sqlFileType[1]
                        Letter = @("F", "G", "H", "I")
                        Label = @("SQLData",
                                   "SQLData2",
                                   "SQLData3",
                                   "SQLData4")
                        MaxVolumes = 4
                     }

                    New-Object -TypeName PSObject -Prop @{
                        # SQLLog
                        FileType = $sqlFileType[2]
                        Letter = @("J","K", "L")
                        Label = @("SQLLog",
                                  "SQLLog2",
                                  "SQLLog3")
                        MaxVolumes = 3
                      }

                    New-Object -TypeName PSObject -Prop @{
                        # TempDB
                        FileType = $sqlFileType[3]
                        Letter = @("T", "U", "V")
                        Label = @("TempDB",
                                  "TempDB2",
                                  "TempDB3")
                        MaxVolumes = 3
                       }
                   )

# Allocation Unit (also known as Cluster Unit) Size (in Bytes)
$allocationUnitSize = 65536 # 64KB

# Number of dashes with which to pad output tables to the user (for aesthetic purposes)
$shortpadspace = 7

try{
    # Get the full list of Physical Disks available to be Initialized
    $unprocessedPhysicalDisks = Get-PhysicalDisk -CanPool $true | Sort FriendlyName

}catch {

    throw "There are no available Physical Disks. Check that VM has Azure data disks attached."

}

# Check to see if there are at least 4 available disks (at least 1 disk for each SQL file type)
if ( ($unprocessedPhysicalDisks | Measure).Count -lt 4 ) {
    
    throw "There are less than 4 available physical disks. Please verify that this VM has at least 4 data disks attached, and that these disks have not yet been initialized."
}

<# Initialize an array of Objects
    Each Object holds the following information about each Physical Disk:
    1. The Friendly Name of the Physical Disk
    2. The size of the Physical Disk
    3. Whether the user has already selected for a Physical Disk to be associated
        with a SQL file type or not.
    4. An index. For the purposes of this variable, this index is useless. However,
        another variable, which will become a subset of $physicalDisks, and will
        use this index to identify a Physical Disks location in the $physicalDisks
        array.
    5. The SQL file type to be associated with each disk.
#>
$physicalDisks = @($false) * ($unprocessedPhysicalDisks | Measure).Count 

# Loop through every Physical Disk
for ($i=0; $i -lt ($unprocessedPhysicalDisks | Measure).Count; $i++) 
{ 
    # Assign all the properties of this physicalDisks object in a hash table
    $properties = @{
        FriendlyName = $unprocessedPhysicalDisks[$i].FriendlyName
        SizeInGB = $unprocessedPhysicalDisks[$i].Size / 1GB
        InUse = $false
        OriginalIndex = $false
        SQLFileType = $false
    }

    # Assign the properties to an Object in the physicalDisks array
    $physicalDisks[$i] = New-Object -TypeName PSObject -Property $properties
}

####################################################################
# Get user to select which disks to assign to which SQL file types
####################################################################

<# 
Overarching logic:
    Loop through each SQL file type.

    For each file type, display the list of available disks, and have the user
    select the disks to be associated with that file type.
#>

# Loop through each file type
for ($i=0; $i -lt ($sqlFileType | Measure).Count; $i++)   
{

    # Prompt the user for how many disks to the associated with this SQL file type
    $question = "How many disks should be associated with $($sqlFileType[$i]) files?"
    $numDisksForFileType = Prompt-User -PromptQuestion $question -maxint 4

    # User cannot select 0 disks to attach. Throw error.
    if ($numDisksForFileType -lt 1)
    {
        throw "Error: must associate at least 1 physical disk per SQL file type."
    }


    # Loop through each disk to be associated with this SQL file type
    for ($j=0; $j -lt $numDisksForFileType; $j++) 
    {

        # Get or update a list of all available physical disks
        $availablePhysicalDisks = Get-AvailablePhysicalDisks `
                                    -physicalDisks $physicalDisks

        # Header of the list of available disks
        $question = "`tAvailable Disks`r`n------------------------------`r`n"

        # Loop through all available disks to create list to display to user
        for ($k = 0;$k -lt ($availablePhysicalDisks | Measure).Count; $k++)
        {
            # Append a row with the disk name and size
            $question += ($k.ToString().PadRight($shortpadspace,'-') + `
                            $availablePhysicalDisks[$k].FriendlyName + `
                            " (" + $availablePhysicalDisks[$k].SizeInGB + `
                            " GB)" + "`r`n")
        }

        $question += "Select disk to associate with $($sqlFileType[$i]) files "
        $question += "($j disks already associated with this SQL file type)."

        # Retrieve number selection from user
        $diskNumber = Prompt-User -PromptQuestion $question -maxint ($availablePhysicalDisks | Measure).Count 

        #####################################
        # Update the variable $physicalDisks
        #####################################

        # Get the 
        $originalIndex = $availablePhysicalDisks[$diskNumber].OriginalIndex
        $physicalDisks[$originalIndex].InUse = $true
        
        # Type of SQL file associated with this disk.   
        $physicalDisks[$originalIndex].SQLFileType = $sqlFileType[$i]
    
    }
}

clear

####################################################################
# Initialize the disks and create volumes
####################################################################

# Define a set of counters, one for each SQL file type
$counters = @(
                   New-Object -TypeName PSObject -Property @{
                          FileType = $sqlFileType[0]
                          Counter = 0
                   }
                   New-Object -TypeName PSObject -Property @{
                          FileType = $sqlFileType[1]
                          Counter = 0
                   }
                   New-Object -TypeName PSObject -Property @{
                          FileType = $sqlFileType[2]
                          Counter = 0
                   }
                   New-Object -TypeName PSObject -Property @{
                          FileType = $sqlFileType[3]
                          Counter = 0
                   }
              )

# Stops the Hardware Detection Service to prevent the Format Disk prompt window from popping up
Stop-Service -Name ShellHWDetection

# If the CD or DVD drive is configured on the E drive, move it to the Z drive
if ((New-Object System.IO.DriveInfo "E").DriveType -ne "NoRootDirectory") {

    $drv = Get-WmiObject win32_volume -filter 'DriveLetter = "E:"'
    $drv.DriveLetter = "Z:"
    $drv.Put() | Out-Null
}


<# Loop through each SQL file type. For every physical disk assigned to that
   file type, initialize that disk and create a volume. Additionally, also
   create a directory in each volume.#>
 for ($i=0; $i -lt ($sqlFileType | Measure).Count; $i++) 
 {
    # For each SQL file type, loop through all physical disks
    for ($j=0; $j -lt ($physicalDisks | Measure).Count; $j++) 
    {
        # If the file type associated with this physical disk matches
        # the current SQL file type, initialize disk and create volume
        if (  $physicalDisks[$j].SQLFileType -eq $sqlFileType[$i]  ) 
        {
            # Get the current counter for this file type
            $counter = $counters[$i].Counter

            # Get the corresponding label to be assigned
            $label = $sqlFileTypeInfo[$i].Label[$counter]

            # Get the corresponding letter to be assigned
            $letter = $sqlFileTypeInfo[$i].Letter[$counter]
            
            Write-Host "Creating volume $letter for file type $($sqlFileType[$i])..."

            ##################################################################
            <# Initialize the disk and create a volume.
                Using the PassThru switch to pass the returned disk object
                down the pipeline to the New-Partition command #>
            ##################################################################

            # Extract the logical disk number from the friendly name of the physical disk
            $diskNumber = [int]($physicalDisks[$j].FriendlyName).Substring(($physicalDisks[$j].FriendlyName).Length-1)

            # Get the logical disk associated with this Physical Disk
            $disk = Get-Disk -Number $diskNumber

            # Initialize disk, create volume, format
            $disk `
            | Initialize-Disk -PartitionStyle GPT `
                              -PassThru `
            | New-Partition   -DriveLetter $letter -UseMaximumSize `
            | Format-Volume   -AllocationUnitSize $allocationUnitSize `
                              -FileSystem NTFS `
                              -NewFileSystemLabel $label `
                              -Confirm:$false -Force | Out-Null

            #############################
            # Create file directories
            ############################

            switch ($sqlFileType[$i])
            {
                "SQLSys"
                {
                    $pathsToCreate = @( "$($letter):\SQLSys",
                                        "$($letter):\SQLBackup",
                                        "$($letter):\DBA_Logs")

                    foreach ($path in $pathsToCreate) {
                        if (!(Test-Path $path)) {
                            New-Item -ItemType directory -Path $path | Out-Null
                        }
                    }
                }
                
                "SQLData"
                {
                    if ( $counter -eq 0 ) {

                        $pathsToCreate = @( "$($letter):\SQLData")
                    }
                    else {    
                         $pathsToCreate = @( "$($letter):\SQLData$($counter+1)")

                    }

                    foreach ($path in $pathsToCreate) {
                        if (!(Test-Path $path)) {
                            New-Item -ItemType directory -Path $path | Out-Null
                        }
                    }
                }

                "SQLLog"
                {
                    if ( $counter -eq 0 ) {

                        $pathsToCreate = @( "$($letter):\SQLLog",
                                            "$($letter):\TempDBLog")
                    }
                    else {
                        
                         $pathsToCreate = @( "$($letter):\SQLLog$($counter+1)",
                                            "$($letter):\TempDBLog$($counter+1)")

                    }

                    foreach ($path in $pathsToCreate) {
                        if (!(Test-Path $path)) {
                            New-Item -ItemType directory -Path $path | Out-Null
                        }
                    }
                }
                
                "TempDB"
                {
                    if ( $counter -eq 0 ) {

                        $pathsToCreate = @( "$($letter):\TempDB")
                    }
                    else {
                        
                         $pathsToCreate = @( "$($letter):\TempDB$($counter+1)")
                    }

                    foreach ($path in $pathsToCreate) {
                        if (!(Test-Path $path)) {
                            New-Item -ItemType directory -Path $path | Out-Null
                        }
                    }
                }
            }
            
            #Update counter 
            $counter++
            $counters[$i].Counter = $counter
        }
    }
 }

# Starts the Hardware Detection Service again
Start-Service -Name ShellHWDetection

Write-Host "Creating volumes and directories complete"
 

########################################
# Install .NET Framework 3.5, AD DS and
# AD LDS Tools, and Failover Clustering
########################################

Write-Host "Installing .NET Framework 3.5..."

Install-WindowsFeature -Name Net-Framework-Core -source $DotNet35SourcePath | Out-Null

if (  (Get-WindowsFeature -Name Net-Framework-Core).InstallState -eq 'Installed'  ) {

    Write-Host ".NET Framework 3.5 successfully installed."

}else {
 
    throw "Error: .NET Framework 3.5 failed to install. Check the path of the .NET Framework 3.5 source files."
}

Write-Host "Installing AD DS and AD LDS Tools..."
Install-WindowsFeature -Name RSAT-AD-Tools | Out-Null

Write-Host "Installing Failover Clustering..."
Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools | Out-Null

########################################
# Create Firewall Rules
########################################

# Customized firewall rules
Create-FirewallRule -firewallRuleName "SQLServer-TCP-$SQLServerPort" -firewallPort $SQLServerPort -protocol TCP
Create-FirewallRule -firewallRuleName "SQLListener-TCP-$SQLListenerPort" -firewallPort $SQLListenerPort -protocol TCP
Create-FirewallRule -firewallRuleName "ILBProbePort-TCP-$ILBProbePort" -firewallPort $ILBProbePort -protocol TCP

# Typical TCP firewall rules
Create-FirewallRule -firewallRuleName "SQLAlwaysOn-TCP-5022" -firewallPort 5022 -protocol TCP
Create-FirewallRule -firewallRuleName "SQL-DAC-TCP-1434" -firewallPort 1434 -protocol TCP

# Typical UDP firewall rules
Create-FirewallRule -firewallRuleName "SQLBrowser-UDP-1434" -firewallPort 1434 -protocol UDP
Create-FirewallRule -firewallRuleName "ClusterAdmin-UDP-137" -firewallPort 137 -protocol UDP
Create-FirewallRule -firewallRuleName "WindowsClusterService-UDP-3343" -firewallPort 3343 -protocol UDP

Write-Host "Firewall rules successfully created"