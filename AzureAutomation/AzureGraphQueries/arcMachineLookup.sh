az graph query -q "Resources 
| where type == 'microsoft.hybridcompute/machines' 
| where name in~ ('MACHINE-A','MACHINE-B','MACHINE-C') 
| project name, resourceGroup, subscriptionId, location, status=tostring(properties.status)" \
  --first 10 \
  --query "data[].{Name:name, ResourceGroup:resourceGroup, Subscription:subscriptionId, Location:location, Status:status}" \
  -o table
