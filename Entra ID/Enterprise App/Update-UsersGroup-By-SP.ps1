# Config
$tenantId = "ee942b75-82c7-42bc-9585-ccc5628492d9"
$clientId = "5bcb95dd-9428-4a55-bc23-3fb9abf19f95" # sp-automation-update-UsersGroups
$clientSecret = "xxxxxxxxxxxxxxxxx"
$scope = "https://graph.microsoft.com/.default"
$graphUrl = "https://graph.microsoft.com/v1.0"

# Authenticate
$tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body @{
   client_id     = $clientId
   scope         = $scope
   client_secret = $clientSecret
   grant_type    = "client_credentials"
} -ContentType 'application/x-www-form-urlencoded'

$accessToken = $tokenResponse.access_token

# Target group id  and enterprise app object id
$groupId = "8853c9a7-6042-4c1c-9f6f-6b5d31914166" # AAD-DYN-Dept1
$spId = "9e068cca-daeb-4a9a-bcba-9879550a1bc5" # JWT Client

# Specify the app role id (in the enterprise app's app registration)
$appRoleId = "3b879099-9bc7-41e5-b49d-3b33bca31a5a"

# Assign group to the app via appRoleAssignments
$body = @{
   principalId = $groupId
   resourceId  = $spId
   appRoleId   = $appRoleId
} | ConvertTo-Json

Invoke-RestMethod -Method POST -Uri "$graphUrl/groups/$groupId/appRoleAssignments" -Headers @{ Authorization = "Bearer $accessToken"; 'Content-Type' = 'application/json' } -Body $body
