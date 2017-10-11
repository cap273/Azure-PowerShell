#https://gallery.technet.microsoft.com/scriptcenter/63fd1c0d-da57-4fb4-9645-ea52fc4f1dfb
function Use-RunAs
{   
    # Check if script is running as Adminstrator and if not use RunAs
    # Use Check Switch to check if admin
    
    param([Switch]$Check)
    
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()`
        ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
        
    if ($Check) { return $IsAdmin }    

    if ($MyInvocation.ScriptName -ne "")
    { 
        if (-not $IsAdmin) 
        { 
			Write-Warning "Must be launched with admin privileges. Attempting to restart..."
            try
            { 
                $arg = "-file `"$($MyInvocation.ScriptName)`""
                Start-Process "$psHome\powershell.exe" -Verb Runas -ArgumentList $arg -ErrorAction 'stop' 
            }
            catch
            {
                Write-Warning "Error - Failed to restart script with runas" 
                break              
            }
            exit # Quit this session of powershell
        } 
    } 
    else 
    { 
        Write-Warning "Error - Script must be saved as a .ps1 file first" 
        break 
    } 
}

#create a location to store the log file and PowerShell script
$DOCDIR = [Environment]::GetFolderPath("MyDocuments")
$TARGETDIR = Join-Path -path $DOCDIR 'AzurePowerShellUpdater'
$TargetFile= Join-Path $TARGETDIR 'AzurePowerShellUpdater.ps1'
$url = "https://api.github.com/repos/Azure/azure-powershell/releases"
$currVer="0"
$AzurePowerShell="C:\Program Files (x86)\Microsoft SDKs\Azure\PowerShell\ServiceManagement\Azure\Azure.psd1"

if(!(Test-Path -Path $TARGETDIR )){
    New-Item -ItemType directory -Path $TARGETDIR
}

#put a copy of the running script in the folder for use by the scheduled task
if(!(Test-Path $TargetFile))
{
	Write-Host "Script not found in $TARGETDIR - copying over"
	Copy-Item $MyInvocation.MyCommand.Path $TargetFile -Force
}

#check to see if the scheduled task already exists
$targettask='Update Azure PowerShell cmdlets'
$task = Get-ScheduledTask | Select TaskName | ? {$_.TaskName -eq $targettask}
If ($task -eq $Null)
{
  	Write-Host "Scheduled task $task doesn't exist - creating"
	#define the scheduled task action
	$targetscript="-file $TargetFile"
	$sta = New-ScheduledTaskAction –Execute "powershell.exe" -Argument $targetscript
	#define the scheduled task trigger
	$stt = New-ScheduledTaskTrigger -Daily -At '14:00'
	Register-ScheduledTask –TaskName $targettask -Action $sta –Trigger $stt 
}

Write-Host "$(Get-Date) - Checking to see if Azure cmdlets need upgraded..."
"$(Get-Date) - Checking to see if Azure cmdlets need upgraded..." | Out-File -FilePath "$TARGETDIR\History.txt" -Append

#go get the current version on GitHub
$results= (Invoke-RestMethod $url)
$gitVer = $results[0].name
$gitVerSimple=$gitVer.Replace(".","")
Write-Host "Latest version on GitHub is $gitVer"
"Latest version on GitHub is $gitVer" | Out-File -FilePath "$TARGETDIR\History.txt" -Append

#get the local version
#if the module isn't installed, we will end up with the default of 0
if (Test-Path $AzurePowerShell)
{
	Import-Module $AzurePowerShell
	$currVer = (Get-Module Azure).Version.ToString()
	Write-Host "Current version is $currVer"
	"Current version is $currVer" | Out-File -FilePath "$TARGETDIR\History.txt" -Append
}
else
{
	Write-Host "Azure PowerShell not currently installed"
	"Azure PowerShell not currently installed" | Out-File -FilePath "$TARGETDIR\History.txt" -Append
}


#if GitHub > local, then update kick off the WebPI installer 
If ($gitVerSimple -gt $currVer.Replace(".","")) 
	{
		Write-Host "Local version needs upgraded. Starting upgrade..."
		"Local version needs upgraded. Starting upgrade..." | Out-File -FilePath "$TARGETDIR\History.txt" -Append
		#WebPI needs to be run with admin mode, so exit and relaunch if not 
		Use-RunAs
		[reflection.assembly]::LoadWithPartialName("Microsoft.Web.PlatformInstaller") | Out-Null
		$ProductManager = New-Object Microsoft.Web.PlatformInstaller.ProductManager
		$ProductManager.Load()
		#NOTE: Here's a handy way to visually see all the possibilities
		#$product = $ProductManager.Products | Where-Object { $_.ProductId -like "*PowerShell*" } | Select Title, ProductID | Out-GridView
		#As of June 2015, this changed from WindowsAzurePowerShellOnly to WindowsAzurePowerShell
		$product=$ProductManager.Products | Where { $_.ProductId -eq "WindowsAzurePowerShell" }
		$InstallManager = New-Object Microsoft.Web.PlatformInstaller.InstallManager
		$c = get-culture
		$Language = $ProductManager.GetLanguage($c.TwoLetterISOLanguageName)
		$installertouse = $product.GetInstaller($Language)
		 
		$installer = New-Object 'System.Collections.Generic.List[Microsoft.Web.PlatformInstaller.Installer]'
		$installer.Add($installertouse)
		$InstallManager.Load($installer)
		 
		$failureReason=$null
		foreach ($installerContext in $InstallManager.InstallerContexts) {
		    $downloadresult=$InstallManager.DownloadInstallerFile($installerContext, [ref]$failureReason)
			Write-Host "Download result for $($installerContext.ProductName) : $downloadresult"
			"Download result for $($installerContext.ProductName) : $downloadresult" | Out-File -FilePath "$TARGETDIR\History.txt" -Append
			$InstallManager.StartSynchronousInstallation()
			if ($installerContext.ReturnCode.Status -eq "Success")
			{
				Write-Host "Upgrade complete. Log can be found at $($installerContext.LogFileDirectory)" -ForegroundColor Yellow
				"Upgrade Complete. Log can be found at $($installerContext.LogFileDirectory)" | Out-File -FilePath "$TARGETDIR\History.txt" -Append
			}
			else
			{
				Write-Host "Install failed with error $($installerContext.ReturnCode.Status). Log can be found at $($installerContext.LogFileDirectory)" -ForegroundColor Red
				"Install failed with error $($installerContext.ReturnCode) Log can be found at $($installerContext.LogFileDirectory)" | Out-File -FilePath "$TARGETDIR\History.txt" -Append
			}
		}
	}
