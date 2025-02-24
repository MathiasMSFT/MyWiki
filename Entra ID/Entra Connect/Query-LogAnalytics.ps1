## Variables
$Time = Get-date -Format "yyyy-MM-dd_HH-mm-ss"
$WorkspaceId = ""
$TenantId = ""

## Connexion Azure
az login --tenant $TenantId | Out-Null

## Récupération du token
$Token = az account get-access-token --resource https://api.loganalytics.io | ConvertFrom-Json
$AccessToken = $Token.accessToken

## Query Log Analytics
$query = @{ query = "AuditLogs `
| where TimeGenerated > ago(7d) `
| mv-expand TargetResources `
| extend UPN = tostring(TargetResources.userPrincipalName) `
| where ActivityDisplayName == 'Update user' `
| join kind=inner (IdentityInfo) on `$left.UPN == `$right.AccountUPN"
} | ConvertTo-Json -Depth 3

## URL de l'API Log Analytics
$Url = "https://api.loganalytics.io/v1/workspaces/$WorkspaceId/query"

## En-têtes de la requête
$Headers = @{
    "Authorization" = "Bearer $AccessToken"
    "Content-Type"  = "application/json"
}

## Exécution de la requête
$Response = Invoke-RestMethod -Method Post -Uri $Url -Headers $Headers -Body $query

## Vérification et extraction des résultats
If ($Response.tables.Count -gt 0) {
    ## Prend la première table
    $Table = $Response.tables[0]
    ## Liste des noms de colonnes
    $Columns = $Table.columns.name
    ## Données sous forme de tableau
    $Rows = $Table.rows

    ## Définir les colonnes à exporter
    $SelectedColumns = @("TimeGenerated", "ActivityDisplayName", "userPrincipalName", "AccountUPN")
    
    ## Affichage des résultats sous forme d'objets PowerShell
    $FormattedResults = $Rows | ForEach-Object {
        $Row = $_
        $obj = @{}
        ## Toutes les colonnes
        # for ($i = 0; $i -lt $Columns.Count; $i++) {
            #$obj[$Columns[$i]] = $Row[$i]
        ## Colonnes sélectionnées - Commenté ligne 54 à 58 si tu utilises la ligne 51 et 52
        ForEach ($Col in $SelectedColumns) {
            $index = $Columns.IndexOf($Col)
            if ($index -ne -1) {
                $obj[$col] = $Row[$index]
            }
        }
        [PSCustomObject]$obj
    }

    ## Définir le chemin du fichier CSV
    $csvPath = ".\Datas_LA_$Time.csv"
    ## Exporter au format CSV
    $FormattedResults | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

    ## Afficher les résultats
    $FormattedResults | Format-Table -AutoSize
} Else {
    Write-Host "Aucune data retournée."
}
