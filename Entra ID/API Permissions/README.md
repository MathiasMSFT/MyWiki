# App Inventory — Export app permissions & consents (PowerShell)

## Script
Purpose
- Export service principals (Enterprise Apps), their application permissions (app role assignments) and delegated consents (oauth2PermissionGrants), flatten the results (one row per permission/consent), and optionally export a CSV for Power BI.

Prerequisites
- PowerShell: `pwsh` / PowerShell 7+ recommended.
- Module: `MSAL.PS` (script attempts to install it if missing).
- Graph permissions (application permissions recommended): e.g. `ServicePrincipal.Read.All`, `Application.Read.All`, `Directory.Read.All`.
- Authentication: script uses client credentials via `Get-MsalToken`. Set `ClientId` and `TenantId` in the script (or modify to pass them).

Files
- `AppInventory.ps1` — main script that collects, normalizes and exports permissions/consents.
- Output CSV example: `Results\GraphAppInventory.csv` when using `-ExportCsv`.

How it works (high level)
- Retrieves `servicePrincipals` with pagination.
- For each service principal (SP):
  - Collects owners and group/role memberships.
  - Collects application permissions (app role assignments) from multiple endpoints and paginates.
  - Collects delegated grants by querying `oauth2PermissionGrants` separately for `clientId` and `resourceId`, paginates and deduplicates.
  - Normalizes and expands permissions into a flattened list (one row per permission/consent).
- Optionally writes a UTF‑8 CSV for Power BI.

Script parameters
- `-IncludeBuiltin` : Include built‑in / integrated apps (default `false` in the script). Use this to include all Enterprise Apps.
- `-ExportCsv` : Export results to CSV.
- `-ExportCsvPath` : Output path for CSV (example: `Results\GraphAppInventory.csv`).
- `-TenantId` : tenantid or tenantname

Usage examples
- Include built-ins and export CSV:
  - `pwsh .\AppInventory.ps1 -IncludeBuiltin -ExportCsv -ExportCsvPath .\Results\GraphAppInventory.csv -TenantId contoso.onmicrosoft.com`
- Export without built-ins:
  - `pwsh .\AppInventory.ps1 -ExportCsv -ExportCsvPath C:\Temp\appinventory.csv -TenantId contoso.onmicrosoft.com`

CSV columns (flattened — one row per permission/consent)
- **ApplicationId**: application (appId) GUID.
- **ApplicationName**: display name of the application.
- **Publisher**: `PublisherName` if present.
- **SPName**: service principal `displayName`.
- **ObjectId**: service principal object id.
- **Type**: service principal type.
- **CreatedOn**: creation timestamp.
- **Enabled**: `AccountEnabled` boolean.
- **Owners**: owner UPNs (semicolon separated).
- **MemberOfGroups**: group memberships.
- **MemberOfRoles**: directory roles.
- **Verified**: verified publisher info.
- **Homepage**: homepage URL.
- **PermissionType**: `Application` or `Delegated`.
- **Resource**: target resource (e.g., `Microsoft Graph`).
- **Permission**: permission/role name (e.g., `Group.Read`, `Chat.Read`).
- **ConsentedBy**: who consented (`All users (admin consent)`, UPNs, or `An administrator (application permissions)`).
- **ConsentType**: `Admin consent` or `User consent`.
- **ValidUntil**: expiration date for delegated grants (if present).

Important notes & limitations
- Declared vs consented: script reports effective consents/assignments. An app may declare scopes/appRoles on its `application` object without those being consented in your tenant — such declarations are not always visible from the local `servicePrincipal`.
- If columns are empty, confirm the token has required Graph permissions.
- The `oauth2PermissionGrants` entity set does not accept complex `or` filters; the script queries `clientId` and `resourceId` separately.
- The script makes many Graph calls (owners, memberOf, grants, appRole endpoints). Expect long runs for large tenants and watch for throttling.

Troubleshooting
- Missing expected permission:
  - Manually run REST checks used by the script (replace `$spId`):
    - `Invoke-RestMethod -Headers $authHeader -Uri "https://graph.microsoft.com/beta/servicePrincipals/$spId/appRoleAssignments" | Select-Object -ExpandProperty value`
    - `Invoke-RestMethod -Headers $authHeader -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=clientId eq '$spId'" | Select-Object -ExpandProperty value`
    - `Invoke-RestMethod -Headers $authHeader -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=resourceId eq '$spId'" | Select-Object -ExpandProperty value`
- No results: check `-IncludeBuiltin`, token permissions, and that SP exists in this tenant.


## Power BI

Prerequisites
- download Power BI desktop

How it works
- Open the pbix file and update the source path of the csv file
- Read the description
- Play with the filter


# Credit

Mathias Dumont

GitHub Copilot and Claude Opus 4.5

