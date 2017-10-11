$DotNet35SourcePath = "\\contoso.com\Source\dotnet35source\sxs\"

##################################
# Install .NET Framework 3.5 
##################################

Install-WindowsFeature -Name Net-Framework-Core -source $DotNet35SourcePath | Out-Null

if (  (Get-WindowsFeature -Name Net-Framework-Core).InstallState -eq 'Installed'  ) {

    Write-Host ".NET Framework 3.5 successfully installed."

}else {
 
    throw "Error: .NET Framework 3.5 failed to install. Check the path of the .NET Framework 3.5 source files."
}

##################################
# Install IIS using Config File
##################################

Install-WindowsFeature -ConfigurationFilePath IISDeploymentConfigTemplate.xml