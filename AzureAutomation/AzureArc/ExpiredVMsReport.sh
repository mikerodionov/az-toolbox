# This scripts generates a list of AzureArc machines with Expired status and their agent version

# Allow dynamic install of preview extensions to install resource-graph extension
az config set extension.dynamic_install_allow_preview=true
az config set extension.use_dynamic_install=yes_without_prompt

# CSV file path
OUTPUT_CSV="expired_machines_report.csv"

# Initialize CSV with headers
echo "MACHINE_NAME,MACHINE_STATUS,MACHINE_AGENT_VERSION" > "$OUTPUT_CSV"

# Run Azure Graph query to retrieve list of Expired VMs and save it to CSV file
az graph query -q 'resources
| where type == "microsoft.hybridcompute/machines" 
| where properties.status == "Expired" 
| project VMName = name, VMStatus = properties.status, AgentVersion = properties.agentVersion' --query "data" -o json --first 1000 \
| jq -r '.[] | [.VMName, .VMStatus, .AgentVersion] | @csv' >> "$OUTPUT_CSV"
