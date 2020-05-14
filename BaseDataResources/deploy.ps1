$rgName='RG-test08'
$location= "eastus2"

New-AzResourceGroup -Name $rgName -Location $location

New-AzResourceGroupDeployment -ResourceGroupName $rgName `
                              -TemplateFile .\azuredeploy.json `
                              -TemplateParameterFile .\azuredeploy-param.json `
                              -dataFactoryName "carlosdatafactory4729" `
                              -storageAccountDataLakeGen2Name "carlosstorageacc4729" `
                              -sqlManagedInstanceName "carlosmanagedinstance4729" `
                              -sqlManagedInstanceAdminLogin 'charliebrown' `
                              -sqlManagedInstancePassword (ConvertTo-SecureString "STRONGPASSWORDHERE" -AsPlainText -Force)

<#
Note that sqlManagedInstancePassword:
- must be at least 16 characters in length
- must be no more than 128 characters in length
- must contain characters from three of the following categories:
-- English uppercase letters,
-- English lowercase letters,
-- numbers (0-9),
-- non-alphanumeric characters (!,$,#,%,etc.)
- cannot contain all of part of the login name. Part of a login name is defined as three
or more consecutive alphanumeric characters
#>