# Lookup for Arc machines by name to get RG, location, status and AAPLS information
# The properties.privateLinkScopeResourceId on microsoft.hybridcompute/machines is always the Arc Private Link Scope (Microsoft.HybridCompute/privateLinkScopes). This controls the Arc agent (himds) connectivity.
az graph query -q "Resources 
| where type == 'microsoft.hybridcompute/machines' 
| where name in~ ('MACHINE-A','MACHINE-B','MACHINE-C') 
| project name, resourceGroup, subscriptionId, location, status=tostring(properties.status), privateLinkScope=tostring(properties.privateLinkScopeResourceId)" \
  --query "data[].{Name:name, ResourceGroup:resourceGroup, Location:location, Status:status, PrivateLinkScope:privateLinkScope}" \
  -o table

# The same but splitting PLS resource ID so that we get only PLS name
az graph query -q "Resources 
| where type == 'microsoft.hybridcompute/machines' 
| where name in~ ('MACHINE-A','MACHINE-B','MACHINE-C') 
| project name, resourceGroup, location, status=tostring(properties.status), plsName=tostring(split(properties.privateLinkScopeResourceId,'/')[8])" \
  --query "data[].{Name:name, ResourceGroup:resourceGroup, Location:location, Status:status, PrivateLinkScope:plsName}" \
  -o table
