<#

.NAME
	Give-FullControlOverDir
	
.DESCRIPTION 
    Assign the specified user accounts full control over the specified directories.
    Inheritance flags are set, so that assigned users will also receive full access to any subdirectories

.PARAMETER identities
	An array containing the list of accounts to be given full control permissions over the
    specified folders. Specify each account in the format "DOMAIN\USER"

.PARAMETER directories
	An array containing the list of directories over which the specified users will have
    full control permissions. Specify each directory with its full path (e.g. "C:\testfolder")

    Wildcards are supported. E.g. to assign users full control over all of the folders in the E: drive, specify:
    $directories = @("E:\*")

    Giving users full control over any root drive (e.g. C:\ or E:\) is not supported:
    https://social.technet.microsoft.com/Forums/windowsserver/en-US/87679d43-04d5-4894-b35b-f37a6f5558cb/solved-how-to-take-ownership-and-change-permissions-for-blocked-files-and-folders-in-powershell?forum=winserverpowershell

.NOTES
    AUTHOR: Carlos Patiño
    LASTEDIT: November 29, 2016
#>
param(
    [string[]]
    $identities = @("DOMAIN\user1",
                    "DOMAIN\user2"),
    
    [string[]]
    $directories = @("C:\test1",
                     "C:\test2")
)

# Define the properties of the Access Rule
$fileSystemRights = [System.Security.AccessControl.FileSystemRights]::FullControl
$inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ObjectInherit -bor `
                    [System.Security.AccessControl.InheritanceFlags]::ContainerInherit
$propagationFlags = [System.Security.AccessControl.PropagationFlags]::None
$accessControlType = [System.Security.AccessControl.AccessControlType]::Allow

#Initialize an array to contain the access rules. A separate access rule is created per user.
$accessRulesArray = @($false) * ($identities | Measure).Count

# Create the access rules, one for each user.
for($i = 0; $i -lt ($identities | Measure).Count; $i++) {

    $accessRulesArray[$i] = New-Object System.Security.AccessControl.FileSystemAccessRule( `
                        $identities[$i], `
                        $fileSystemRights, `
                        $inheritanceFlags, `
                        $propagationFlags, `
                        $accessControlType `
                )

}

# Loop through all Access Rules (one per user)
for($j = 0; $j -lt ($accessRulesArray | Measure).Count; $j++) {

    # Loop through all directories
    for ($k = 0; $k -lt ($directories | Measure).Count; $k++) {

        # For each directory and for each user, add an Access Control List (ACL)
        # giving the user full control over the directory.
        $acl = Get-Acl -Path $directories[$k]
        $acl.SetAccessRule($accessRulesArray[$j])
        Set-Acl -Path $directories[$k] -AclObject $acl
    }

}
