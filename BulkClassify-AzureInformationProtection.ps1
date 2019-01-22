# Bulk classify files with Azure Information Protection (AIP) labels.
# Using the switch parameter -PreserveFileDetails, which leavse the date unchanged for documents labelled using this script.

param(

    # Specifies a local path, network path, or SharePoint Server URL to the files for which you want to apply the label and protection information.
    # THIS SCRIPT WILL APPLY LABELS TO ALL FILES IN THAT PATH, INCLUDING ALL SUBFOLDERS
    # Wildcards are not supported and WebDav locations are not supported.
    # For SharePoint paths: SharePoint Server 2013 and SharePoint Server 2016 are supported.
    # Examples include C:\Folder\, C:\Folder\Filename, \\Server\Folder, http://sharepoint.contoso.com/Shared%20Documents/Folder.
    # Paths can include spaces when you enclose the path value with quotes.
    [string] $path = "C:\Users\carpat\Downloads\Horizon_SZ_Reports",

    # Specifies the GUID of the AIP label that will be applied.
    [string] $labelId = "e72bb48c-1a5f-41d8-bcf0-71063fc5461b",

    # If $true, any existing AIP labels will be overriden by the specified label. If $false, existing AIP labels will not be changed.
    [boolean] $overrideExistingLabels = $false,

    # OPTIONAL
    # The justification reason for lowering the classification label, removing a label, or removing protection, if the Azure Information 
    # Protection policy requires users to supply this information. If setting a label triggers the justification and this reason is not 
    # supplied, the label is not applied. In this case, the status returned is "Skipped" with the comment "Justification required".
    [string] $justificationMessage = "Test justification"
)

#Global initializations
cls
$ErrorActionPreference = 'Stop'


# Verify that the Azure Information Protection (AIP) PowerShell module is installed
# When you install the Azure Information Protection client, PowerShell commands are automatically installed.
# https://docs.microsoft.com/en-us/azure/information-protection/rms-client/client-admin-guide-powershell
$aipModuleVersion = (Get-Module -Name AzureInformationProtection -ListAvailable).Version

# If the AIP module is installed as one user and this script is running 
# on the same computer as another user, run the cmdlet Import-Module AzureInformationProtection
if ( [string]::IsNullOrEmpty($aipModuleVersion) )
{
    Import-Module -Name AzureInformationProtection

    # Get the AIP module version again 
    $aipModuleVersion = (Get-Module -Name AzureInformationProtection -ListAvailable).Version

    # If still cannot retrieve the current AIP module version, throw an error and do not continue
    if ( [string]::IsNullOrEmpty($aipModuleVersion) )
    {
        throw "Cannot find Azure Information Protection (AIP) PowerShell module. See the following Microsoft documentation for more information: https://docs.microsoft.com/en-us/azure/information-protection/rms-client/client-admin-guide-powershell"
    }
}

Write-Host "Current Azure Information Protection (AIP) PowerShell module version:"
Write-Host "$(($aipModuleVersion).Major).$(($aipModuleVersion).Minor).$(($aipModuleVersion).Build).$(($aipModuleVersion).Revision)" -ForegroundColor Green -BackgroundColor Black
Write-Host "Latest AIP module information available here: https://docs.microsoft.com/en-us/powershell/module/AzureInformationProtection/?view=azureipps `n"

# Check the path (and all of the subfolders) to which the specified label will be applied, and require user confirmation
Write-Host "All files in the following path (including all subfolders) will have the specified AIP label applied: [$($path)]" -BackgroundColor Black
if ($overrideExistingLabels) {Write-Host "Additionally, any existing AIP labels in the files in the aforementioned path WILL be overridden.`n" -BackgroundColor Red}
else {Write-Host "However, any existing AIP labels in the files in the aforementioned path WILL NOT be overridden. `n" -BackgroundColor Black}
$confirmation = Read-Host "Are you Sure You Want To Proceed [y/n]:"
if ($confirmation -eq 'y')
{

    # Get the files to which to apply these labels, considering whether to override existing AIP labels or not.
    if ($overrideExistingLabels)
    {
        $files = Get-ChildItem -Path "$($path)\*" -File -Recurse
        if ( [string]::IsNullOrEmpty($files) ) { 
            Write-Host "`nNo files were found in path: [$($path)]" -BackgroundColor Green -ForegroundColor Black
            exit
        }
    }
    else
    {
        $files = Get-ChildItem -Path "$($path)\*" -File -Recurse | Get-AIPFileStatus | where {$_.IsLabeled -eq $False}
        if ( [string]::IsNullOrEmpty($files) ) 
        { 
            Write-Host "`nNo files without existing AIP labels were found in path: [$($path)]" -BackgroundColor Green -ForegroundColor Black
            exit
        }     
    }
    
    # Apply AIP label to relevant files. Include justification message if included in the parameters (will only apply if required by AIP policy)
    if ( [string]::IsNullOrEmpty($justificationMessage) )
    {
        $output = $files | Set-AIPFileLabel -LabelId $labelId -Verbose
        $output
    }
    else
    {
        $output = $files | Set-AIPFileLabel -LabelId $labelId -JustificationMessage $justificationMessage -Verbose
        $output
    }
    
}
else
{ 
    exit 
}
