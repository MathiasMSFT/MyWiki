# Deployment

Deploy through 2 steps:

1. Deploy the ARM template in your subscription
2. Go to the connectors (O365 and Key Vault), and Authorize them


After deployment, you need to give permission to your Managed Identity on your KeyVault.
<p align="center" width="100%">
    <img width="70%" src="./images/KeyVault-Forbidden-1.png">
</p>

Find objectid of MI
<p align="center" width="100%">
    <img width="70%" src="./images/ManagedIdentity-ObjectID.png">
</p>


Give permission 



## Deployment template

You can deploy the ARM templates to your Azure Subscription using the link below:

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMathiasMSFT%2FScripts%2FLogic%20Apps%2FMonitor%20secret-certificate%2Fazuredeploy.json" target="_blank">
  <img src="https://aka.ms/deploytoazurebutton"/>
</a>

