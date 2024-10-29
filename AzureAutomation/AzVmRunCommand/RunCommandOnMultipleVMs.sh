#!/bin/bash

# This script intended to execute command $COMMAND on all VMs from VM list retrieved via Azure Graph query $VM_LIST
# VM list contains VM_NAME, VM_RESOURCE_GROUP and VM_SUBSCRIPTION columns
# Scrpt produces CSV file with VM_NAME, VM_RESOURCE_GROUP, VM_SUBSCRIPTION, and COMMAND_OUTPUT columns
# You can adjust query to target VMs you need
# Adjust $COMMAND to execute command you need
# Running this script requires Contributo rights on VM

# Define the command to run on each VM
COMMAND="COMMAND YOU WANT TO EXECUTE"

# Allow dynamic install of preview extensions to install resource-graph extension
az config set extension.dynamic_install_allow_preview=true
az config set extension.use_dynamic_install=yes_without_prompt

# CSV file path
OUTPUT_CSV="vm_command_output_list.csv"

# Initialize CSV with headers
echo "VM_NAME,VM_RESOURCE_GROUP,VM_SUBSCRIPTION,COMMAND_OUTPUT" > "$OUTPUT_CSV"

# Set the number of concurrent processes
MAX_CONCURRENT=10  # Adjust this based on available resources

# Initialize the counter file
COUNTER_FILE="/tmp/vm_processing_counter.txt"
echo 0 > "$COUNTER_FILE"

# Get total VM count for progress display
TOTAL=$(az graph query -q "resources \
| where type == 'microsoft.compute/virtualmachines' \
  and tostring(properties.storageProfile.osDisk.osType) == 'Linux' \
  and tostring(properties.licenseType) == 'RHEL_BYOS' \
| summarize count()" --query "data[0].count_" -o tsv)
export TOTAL

# Azure Graph query to select target VMs and store the output in a variable - here we target Linux VMs with 
VM_LIST=$(az graph query -q "resources \
| where type == 'microsoft.compute/virtualmachines' \
  and tostring(properties.storageProfile.osDisk.osType) == 'Linux' \
  and tostring(properties.licenseType) == 'RHEL_BYOS' \
| project VM_NAME = name, VM_RESOURCE_GROUP = resourceGroup, VM_SUBSCRIPTION = subscriptionId \
" --query "data" -o json --first 1000)

# Function to process each VM
process_vm() {
  VM_NAME=$1
  VM_RG=$2
  VM_SUBSCRIPTION=$3
  COMMAND=$4

  # Check the VM's power state
  POWER_STATE=$(az vm get-instance-view \
    --resource-group "$VM_RG" \
    --name "$VM_NAME" \
    --subscription "$VM_SUBSCRIPTION" \
    --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" \
    -o tsv)

  if [[ "$POWER_STATE" == "VM running" ]]; then
    # Run the command on the current VM and capture the output
    result=$(az vm run-command invoke \
      --resource-group "$VM_RG" \
      --name "$VM_NAME" \
      --subscription "$VM_SUBSCRIPTION" \
      --command-id RunShellScript \
      --scripts "$COMMAND" -o json 2>&1)

    # Check if the result is valid JSON before parsing
    if echo "$result" | jq empty > /dev/null 2>&1; then
      # Extract, clean, and display the "message" value from the result
      message=$(echo "$result" | jq -r '.value[0].message' | sed '/^\[stdout\]/d;/^\[stderr\]/d;/^$/d;s/^Enable succeeded: //' | sed '/./,$!d')
      # Append to CSV
      echo "$VM_NAME,$VM_RG,$VM_SUBSCRIPTION,\"$message\"" >> "$OUTPUT_CSV"
    else
      echo "$VM_NAME,$VM_RG,$VM_SUBSCRIPTION,\"Error: Unable to fetch command output\"" >> "$OUTPUT_CSV"
    fi
  else
    echo "$VM_NAME,$VM_RG,$VM_SUBSCRIPTION,\"VM is offline\"" >> "$OUTPUT_CSV"
  fi

  # Update counter in the file
  (
    flock -x 200
    COUNT=$(<"$COUNTER_FILE")
    ((COUNT++))
    echo "$COUNT" > "$COUNTER_FILE"
    echo "Processed VMs: $COUNT / $TOTAL"
  ) 200>"/tmp/vm_processing.lock"
}

# Export function and variables for parallel execution
export -f process_vm
export OUTPUT_CSV
export COMMAND
export COUNTER_FILE

# Iterate over each VM in the list
echo "$VM_LIST" | jq -c '.[]' | while read vm; do
  VM_NAME=$(echo "$vm" | jq -r '.VM_NAME')
  VM_RG=$(echo "$vm" | jq -r '.VM_RESOURCE_GROUP')
  VM_SUBSCRIPTION=$(echo "$vm" | jq -r '.VM_SUBSCRIPTION')

  # Start processing VM in the background
  process_vm "$VM_NAME" "$VM_RG" "$VM_SUBSCRIPTION" "$COMMAND" &

  # Control the number of concurrent jobs
  if (( $(jobs -r | wc -l) >= MAX_CONCURRENT )); then
    wait -n  # Wait for at least one job to finish before starting a new one
  fi
done

# Wait for all background jobs to complete
wait
