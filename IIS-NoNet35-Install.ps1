Install-WindowsFeature -ConfigurationFilePath IISDeploymentConfigTemplate.xml `
                       -Source "\\contoso.com\Source\dotnet35source\sxs\"

New-NetFirewallRule -DisplayName "HTTPS-TCP-443" -Direction Inbound -Profile Domain,Private,Public `
                    -Action Allow -Protocol TCP -LocalPort 443 -RemoteAddress Any | Out-Null