# How to manage notification with Logic App
[![fr](https://img.shields.io/badge/lang-fr-blue.svg)](README-fr.md)

You may have Logic Apps to monitor or analyze workloads and send notifications. Currently, you implement an action to send an email in each Logic App. However, did you know you can call a nested Logic App?

For instance, if a secret or certificate of your application is expiring or has expired, a Logic App can notify the relevant party. The goal is to call this Logic App whenever you need to send an email, eliminating the need to implement this in each Logic App.

Your Managed Identity needs Mail.Send permission, that means it will be able to send an email from anyone. To secure this part, you will use an Application Access Policy in Exchange Online to allow only this MI to send an email from only one mailbox.

## Setup
Create a Logic App Consumption

1. **Create a Consumption Logic App**: Deploy the ARM templates to your Azure Subscription using the provided link below:

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMathiasMSFT%2FMyWiki%2Frefs%2Fheads%2Fmain%2FLogic-App%2FNotifications%2Fazuredeploy-notifications.json" target="_blank">
  <img src="https://aka.ms/deploytoazurebutton"/>
</a>


2. **Managed Identity**: A system-assigned Managed Identity will be created. Note down the name and the appID (not the objectID).


3. **Assign permissions to your Managed Identity**: Use this script.

```
$TenantID = "<your tenantid>"
$GraphAppId = "00000003-0000-0000-c000-000000000000"
$DisplayNameMI = "<name of Logic App>"
$GraphPermission = "Mail.Send"

Connect-MgGraph -Scopes Application.Read.All,AppRoleAssignment.ReadWrite.All

$IdMI = Get-MgServicePrincipal -Filter "DisplayName eq '$DisplayNameMI'"

## Get assigned roles
Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $IdMI.Id

## Get Graph roles
$GraphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'"
$AppRole = $GraphServicePrincipal.AppRoles | Where-Object {$_.Value -eq $GraphPermission -and $_.AllowedMemberTypes -contains "Application"}

$AppRole

$params = @{
	principalId = $IdMI.Id
	resourceId = $GraphAppId
    appRoleId = $($AppRole.Id)
}

## Add permission to Managed Identity
New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $IdMI.Id -ResourceId $GraphServicePrincipal.Id -PrincipalId $IdMI.Id -AppRoleId $AppRole.Id

## Get assigned roles
Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $IdMI.Id
```


4. **Mail-Enabled Security Group and Email Account**: Create an email account and add it to your group
<p align="center" width="100%">
    <img width="70%" src="./images/Create-Mail-EnabledSG.png">
</p>


5. **Application Access Policy**:
Create an Application Access Policy in Exchange Online

- AppId: Application Id of your Mnanaged Identity
- PolicyScopeGroupId: email of your mail-enabled security group

```
# Install-Module ExchangeOnlineManagement
Connect-ExchangeOnline -UserPrincipalName <UserPrincipalName>

New-ApplicationAccessPolicy `
    -AppId <AppId Of MI> `
    -PolicyScopeGroupId <emailaddress of mail-enabled security group> `
    -AccessRight RestrictAccess `
    -Description "Restrict IGA-Notifications managed identity"
```

## Call your Logic App
In your main Logic App, use the Logic App to call one you have created.

<p align="center" width="100%">
    <img width="70%" src="./images/Call-LogicApp-1.png">
</p>

<p align="center" width="100%">
    <img width="70%" src="./images/Call-LogicApp-2.png">
</p>

<p align="center" width="100%">
    <img width="70%" src="./images/Call-LogicApp-3.png">
</p>

https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-http-endpoint?tabs=consumption

