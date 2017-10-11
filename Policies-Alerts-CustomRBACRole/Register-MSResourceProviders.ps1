<#

When a subscription is first created, Azure resource providers are by default not registered. 
These resource providers must be registered before certain actions are taken. 
For example, the resource provider “Microsoft.Compute” must be registered before a VM can be created. 

However, by default, only the Subscription Admin can register resource providers. 
So when a user with RBAC permissions tries to be the first user to deploy a VM, 
even though s/he is an RBAC owner of a resource group, 
authorization fails because the resource provider has not been registered.

Once the subscription admin first creates a resource, 
the relevant resource provider is automatically registered, and other users may then create their own resources without problems.

You can register all the Microsoft providers via this script and resolve this issue.
#>

# Register all Microsoft resource providers
Get-AzureRmResourceProvider -ListAvailable | `
          Where-Object {$_.ProviderNamespace -like "Microsoft.*"} | Register-AzureRmResourceProvider | Out-Null