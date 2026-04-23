

# Variables à adapter
$tenantIdCible = "076894ec-4485-4768-9702-8269c43a2030" # external tenant
$tenantIdSource = "ee942b75-82c7-42bc-9585-ccc5628492d9" # Main tenant
$clientId = "8a1b757e-71d4-4e2c-ac90-d929de4511c7"
$scope = "api://AzureADTokenExchange"

# Si tu es sur Azure (VM, App Service, etc.), récupère le token de la Managed Identity locale
#$miToken = Invoke-RestMethod -Headers @{Metadata="true"} -Method GET -Uri "https://login.microsoftonline.com/$tenantIdSource/oauth2/v2.0/token?api-version=2018-02-01&resource=$scope"
#$assertion = $miToken.access_token

<#$miToken = Invoke-WebRequest -Uri "https://login.microsoftonline.com/$tenantIdSource/oauth2/v2.0/token" -Method 'POST' -Headers @{
    'Metadata'          = 'true'
} -ContentType 'application/x-www-form-urlencoded' -Body @{
    'scope'  = 'api://AzureADTokenExchange'
    'client_id' = $clientId
}
$assertion = $miToken.access_token#>


$response = Invoke-WebRequest -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=api%3A%2F%2FAzureADTokenExchange' `
                              -Headers @{Metadata="true"}
$content =$response.Content | ConvertFrom-Json
$assertion = $content.access_token

Write-Host "AccessToken: $assertion"


# Demande un token d'accès sur le tenant cible via l'endpoint OIDC (federated credential)
$body = @{
    client_id = $clientId
    scope = $scope
    client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
    client_assertion = $assertion
    grant_type = "client_credentials"
} 

$response = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$tenantIdCible/oauth2/v2.0/token" -Body $body -ContentType "application/x-www-form-urlencoded"
$accessToken = $response.access_token

Write-Host "MI: $miToken"
Write-Host "AccessToken: $assertion"

# Utilise $accessToken pour tes appels REST sur le tenant cible
#>