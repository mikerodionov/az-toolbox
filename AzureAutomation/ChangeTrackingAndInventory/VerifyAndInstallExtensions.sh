# Script checks installation of AzureMonitorWindowsAgent and ChangeTracking-Windows extensions and installs those if they are not installed iterating through VMs list

# Set target VMs variables - list of target VMs and their location
RESOURCE_GROUP="VMs_RESOURCE_GROUP"
SUBSCRIPTION="VMs_SUBSCRIPTION"
LOCATION="NORTHEUROPE" # e.g. northeurope
MACHINE_NAMES=("VM_1" "VM_2" "VM_N")

# Define color codes using tput
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
NC=$(tput sgr0) # No Color

# Configure the Azure CLI to automatically and silently install any required extensions without prompting the user
az config set extension.use_dynamic_install=yes_without_prompt 2>/dev/null

# Iterate through VMs list
for MACHINE_NAME in "${MACHINE_NAMES[@]}"; do
  # Capture the output and exit code for provisioning state, suppress output on error
  PROVISIONING_OUTPUT=$(az connectedmachine show --name "$MACHINE_NAME" --resource-group "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION" --query "provisioningState" --output tsv 2>/dev/null)
  PROVISIONING_EXIT_CODE=$?

  # Capture the output and exit code for status, suppress output on error
  STATUS_OUTPUT=$(az connectedmachine show --name "$MACHINE_NAME" --resource-group "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION" --query "status" --output tsv 2>/dev/null)
  STATUS_EXIT_CODE=$?

  # Check if both commands succeeded
  if [[ $PROVISIONING_EXIT_CODE -eq 0 && $STATUS_EXIT_CODE -eq 0 ]]; then
    # Extract the provisioning state and status
    PROVISIONING_STATE="$PROVISIONING_OUTPUT"
    STATUS="$STATUS_OUTPUT"

    # Proceed if provisioning state is "Succeeded" and status is not "Expired"
    if [[ "$PROVISIONING_STATE" == "Succeeded" && "$STATUS" != "Expired" && "$STATUS" != "Offline" ]]; then

      # Check for AzureMonitorWindowsAgent extension and install if not installed
      if az connectedmachine extension show --name AzureMonitorWindowsAgent --machine-name "$MACHINE_NAME" --resource-group "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION" \
        --query "{VMName: '$MACHINE_NAME', Location: location, ExtensionName: name, ResourceGroup: resourceGroup}" --output tsv >/dev/null 2>&1; then
        echo -e "${GREEN}AzureMonitorWindowsAgent extension is installed on $MACHINE_NAME.${NC}"
      else
        #echo -e "${RED}AzureMonitorWindowsAgent extension is not installed. Installing...${NC}"
        az connectedmachine extension create \
          --name AzureMonitorWindowsAgent \
          --publisher Microsoft.Azure.Monitor \
          --type AzureMonitorWindowsAgent \
          --machine-name "$MACHINE_NAME" \
          --resource-group "$RESOURCE_GROUP" \
          --location "$LOCATION" \
          --enable-auto-upgrade true \
          --subscription "$SUBSCRIPTION"
      fi

      # Check for ChangeTracking-Windows extension and install if not installed
      if az connectedmachine extension show --name ChangeTracking-Windows --machine-name "$MACHINE_NAME" --resource-group "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION" \
        --query "{VMName: '$MACHINE_NAME', Location: location, ExtensionName: name, ResourceGroup: resourceGroup}" --output tsv >/dev/null 2>&1; then
        echo -e "${GREEN}ChangeTracking-Windows extension is installed on $MACHINE_NAME.${NC}"
      else
        echo -e "${RED}ChangeTracking-Windows extension is not installed. Installing...${NC}"
        az connectedmachine extension create \
          --name ChangeTracking-Windows \
          --publisher Microsoft.Azure.ChangeTrackingAndInventory \
          --type ChangeTracking-Windows \
          --machine-name "$MACHINE_NAME" \
          --resource-group "$RESOURCE_GROUP" \
          --location "$LOCATION" \
          --enable-auto-upgrade true \
          --subscription "$SUBSCRIPTION"
      fi

    else
      echo -e "${RED}Machine $MACHINE_NAME provisioning state: $PROVISIONING_STATE, status: $STATUS. Skipping.${NC}"
    fi

  else
    # Custom error message, suppressing detailed output
    echo -e "${RED}An error occurred while checking the machine $MACHINE_NAME. Skipping. Possible reasons: machine is offline, machine not registered with Azure Arc or machine does not exist within specified resource group or subscription${NC}"
  fi

done
