# Client Id of the user assigned identity
$UMI = "8a1b757e-71d4-4e2c-ac90-d929de4511c7"
 
# Client Id of the app registration in your main tenant
$AppRegIdMainTenant = "f004bd68-34a1-4840-977b-1142e0f2251f"
 
# Tenant Id of your main tenant
$MainTenantId = "ee942b75-82c7-42bc-9585-ccc5628492d9"
 
# Tenant Id of the resource tenant you want to access
$TargetTenantId = "076894ec-4485-4768-9702-8269c43a2030"
 
# Get an Access Token for the User Assigned Identity in the Main Tenant
$AccessToken = Invoke-RestMethod $env:IDENTITY_ENDPOINT -Method 'POST' -Headers @{
    'Metadata'          = 'true'
    'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER
} -ContentType 'application/x-www-form-urlencoded' -Body @{
    'resource'  = 'api://AzureADTokenExchange'
    'client_id' = $UMI
}
if(-not $AccessToken.access_token) {
    Write-Output "Failed to get an access token"
} else {
    Write-Output "Successfully get an access token for main tenant"
}


# Get an Access Token for the Target Tenant using the App Registration in the Main Tenant
$AccessTokenTargetTenant = Invoke-RestMethod "https://login.microsoftonline.com/$TargetTenantId/oauth2/v2.0/token" -Method 'POST' -Body @{
    client_id             = $AppRegIdMainTenant
    scope                 = 'https://graph.microsoft.com/.default'
    grant_type            = "client_credentials"
    client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
    client_assertion      = $AccessToken.access_token
}



$mgRequest = Invoke-MgGraphRequest -Uri 'https://graph.microsoft.com/v1.0/users?$top=1' -OutputType HttpResponseMessage -Method 'POST' -Body @{
    client_id             = $AppRegIdMainTenant
    scope                 = 'https://graph.microsoft.com/.default'
    grant_type            = "client_credentials"
    client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
    client_assertion      = $AccessToken.access_token
}

