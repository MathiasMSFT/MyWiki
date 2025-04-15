# Enable Monthly Active User

## Recommendation
Microsoft recommends enabling Monthly Active Users (MAU) to gain several benefits:
- You will be no longer limited to a 1:5 ratio
- First 50 000 MAU users are free
- You pay only for what you use

This applies to both workforce tenants and external tenants.

## What does "Active" mean ?
"Active" means that a user has authenticated during the month.
For example:
- If you have 60,000 guest accounts, but only 1,000 guest accounts sign in to your tenant, you will pay nothing.
- If you have 60,000 guest accounts and 55,000 guest accounts sign in to your tenant, you will pay for 5,000 guest accounts.


# Enable MAU

1. Register the resource provider in Azure
- Install az module
```
Install-Module -Name Az -AllowClobber -Scope AllUsers -Force
```

- Connect to Azure and register the resource provider
```
Connect-AzAccount
Register-AzResourceProvider -ProviderNamespace Microsoft.AzureActiveDirectory
```

2. Create a Resource Group
```
az group create --name rg-MAU --location eastus
```

3. Link to the subscription
- Use the following script

```
$tenantName = "contoso.onmicrosoft.com"
$tenantId = "<tenantId>"
$subscriptionId="<subId>"
$resourceGroup="<ResourceGroup>"
$locationName="United States"

az rest --method put --url https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.AzureActiveDirectory/guestUsages/${tenantName}?api-version=2020-05-01-preview --body "{'location': '$locationName', 'name': '$tenantName', 'type': 'Microsoft.AzureActiveDirectory/GuestUsages', 'properties': {'tenantId': '$tenantId'}}"

```
Source: https://learn.microsoft.com/en-us/entra/external-id/external-identities-pricing#link-your-azure-ad-tenant-to-a-subscription


# Disable MAU

To disable MAU, simply delete the “Guest usage” resource type with your domain name.

<p align="center" width="100%">
    <img width="70%" src="./images/Disable-MAU.png">
</p>


