# Gestion des notifications avec une Logic App
[![en](https://img.shields.io/badge/lang-en-red.svg)](README.md)

Vous pouvez avoir des Logic App pour surveiller ou analyser des charges de travail et envoyer des notifications. Actuellement, vous implémentez une action pour envoyer un e-mail dans chaque Logic App. Saviez-vous que vous pouvez appeler une Logic App imbriquée ?

Par exemple, si un secret ou un certificat de votre application est sur le point d'expirer ou a expiré, une Logic App peut notifier la partie prenante. L'objectif est d'appeler cette Logic App chaque fois que vous devez envoyer un e-mail, éliminant ainsi la nécessité de l'implémenter dans chaque Logic App.

Votre Managed Identity a besoin de la permission Mail.Send, ce qui signifie qu'elle sera capable d'envoyer un courriel de n'importe qui. Pour sécuriser cela, vous allez utiliser une politique d'accès application dans Exchange Online pour autoriser uniquement cette MI d'envoyer un courriel seulement depuis une boite.


## Setup
Créer une Logic App de type Comsumption

1. **Créer une Consumption Logic App**: Déployer le template ARM dans votre souscription en utilisant le lien fourni ci-dessous:

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMathiasMSFT%2FMyWiki%2Frefs%2Fheads%2Fmain%2FLogic-App%2FNotifications%2Fazuredeploy-notifications.json" target="_blank">
  <img src="https://aka.ms/deploytoazurebutton"/>
</a>


2. **Managed Identity**: Une Managed Identité de type system sera créé. Garder le nom et l'app id (pas l'objectID).


3. **Assigner les permissions à votre Managed Identity**: Utiliser le script ci-dessous:

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


4. **Mail-Enabled Security Group and Email Account**: Créer un compte mail et ajouter le dans le groupe
<p align="center" width="100%">
    <img width="70%" src="./images/Create-Mail-EnabledSG.png">
</p>


5. **Application Access Policy**:
Créer une politique d'accès application dans Excahnge Online

- AppId: Application Id de votre Mnanaged Identity
- PolicyScopeGroupId: Email de votre groupe de sécurité

```
# Install-Module ExchangeOnlineManagement
Connect-ExchangeOnline -UserPrincipalName <UserPrincipalName>

New-ApplicationAccessPolicy `
    -AppId <AppId Of MI> `
    -PolicyScopeGroupId <emailaddress of mail-enabled security group> `
    -AccessRight RestrictAccess `
    -Description "Restrict IGA-Notifications managed identity"
```

6. **Appeler la Logic App**: Dans votre Logic App principale, utiliser Logic App pour appeler celle que vous venez de créer.

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


