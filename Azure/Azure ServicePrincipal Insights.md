# Deploy Azure Service Principal Insights

Source: https://github.com/JulianHayward/AzADServicePrincipalInsights

## Overview
The Azure ServicePrincipal Insights project provides scripts and instructions to gain insights into Azure Service Principals. It helps in managing and visualizing service principal data.


## Clone the Azure Governance Visualizer repository

Be sure you have Git installed.
```
git clone "https://github.com/JulianHayward/AzADServicePrincipalInsights.git"
Set-Location AzADServicePrincipalInsights
```

<p align="center" width="100%">
    <img width="70%" src="./images/Download-GitHub-Repo-SPInsight.png">
</p>


## Run

```
$pscredential = Get-Credential -UserName "a8c178f9-15fc-4f4b-9501-f98cf6a36116"
Connect-AzAccount -ServicePrincipal -TenantId "ee942b75-82c7-42bc-9585-ccc5628492d9" -Credential $pscredential
.\pwsh\AzADServicePrincipalInsights.ps1
```

Open the report
```
Set-Location -Path ".\AzADServicePrincipalInsights"
Get-ChildItem
Invoke-Item ".\AzADServicePrincipalInsights*.html"
```


## Result

<p align="center" width="100%">
    <img width="70%" src="./images/Azure Service Principal Insight Result.png">
</p>


📍Keep in mind your data are stored locally.
