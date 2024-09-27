Param (
    # Root folder of your Entra Connect configuration
    [Parameter(Mandatory)]
    $Folder
)

Function Connectors {
    Param (
        [Parameter(Mandatory)]
        $Path
    )

    # Define the directory of connectors xml files
    $ConnectorDirectory = "$Path\Connectors"

    # Create a hash table
    $HashTable = @{}

    # Get all xml files in connectors directory
    $ConnectorsXML = Get-ChildItem -Path $ConnectorDirectory -Filter *.xml

    # Loop - for each file
    foreach ($Connector in $ConnectorsXML) {
        # Get content
        [xml]$xmlContentC = Get-Content $Connector.FullName

        # Get ID and name of connector
        $IdConnector = $xmlContentC.DocumentElement.id
        $ConnectorName = $xmlContentC.DocumentElement.name

        # Verify if IdConnector already exists in hashtable
        if (-not $HashTable.ContainsKey($IdConnector)) {
            # If doesn't exist, add
            $HashTable[$IdConnector.ToLower()] = $ConnectorName
        } else {
            # If already exists, update
            $HashTable[$IdConnector.ToLower()] = $ConnectorName
        }
    }
    Return $HashTable
}

$HashTable = Connectors -Path $Folder

# Define the directory of rules xml files
$RuleDirectory = "$Folder\SynchronizationRules"

# Get all xml files in rule directory
$RulesXML = Get-ChildItem -Path $RuleDirectory -Recurse -Filter *.xml

# Loop - for each file
foreach ($Rule in $RulesXML) {
    # Get content
    [xml]$xmlContentR = Get-Content $Rule.FullName
    Write-Host "File: $($Rule.Name)" -ForegroundColor Yellow

    # Get name and ID of rule
    $RuleName = $xmlContentR.DocumentElement.name
    Write-Host "    Name: $RuleName" -ForegroundColor Green
    $RuleIdConnecteur = $xmlContentR.DocumentElement.connector
    Write-Host "    ID: $RuleIdConnecteur" -ForegroundColor Green

    # Replace ID by name
    $ConnectorName = $HashTable[$RuleIdConnecteur]
    if ($null -ne $ConnectorName) {
        # Define new name
        $NewFileName = "$RuleName--$ConnectorName.xml"

        # Rename
        Rename-Item -Path $Rule.FullName -NewName $NewFileName
    } else {
        # If ID is not find in hashtable
        Write-Host "Aucune association trouvée pour le connecteur : $RuleIdConnecteur"
    }
}
