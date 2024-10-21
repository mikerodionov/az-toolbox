# Set variables
DCR_NAME="DATA COLECTION RULE NAME"
DCR_ASSOCIATION_NAME="DATA COLECTION RULE ASSOCIATION NAME"
DCR_RESOURCE_GROUP="DCR RESOURCE GROUP"
SUBSCRIPTION="MACHINES SUBSCRIPTION"
RESOURCE_GROUP="MACHINES RESOURCE GROUP"
MACHINE_NAMES=("MACHINE_1" "MACHINE_2" "MACHINE_N")

# Define color codes using tput
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
NC=$(tput sgr0) # No Color

# Configure the Azure CLI to automatically and silently install any required extensions without prompting the user
az config set extension.use_dynamic_install=yes_without_prompt 2>/dev/null

# Get DCR ID
DCR_ID=$(az monitor data-collection rule show --name $DCR_NAME --resource-group $DCR_RESOURCE_GROUP --subscription $SUBSCRIPTION --query "id" --output tsv)

# Iterate through machine names list and add them to DCR
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

    # Proceed if machine provisioning state is "Succeeded" and status is not "Expired"
    if [[ "$PROVISIONING_STATE" == "Succeeded" && "$STATUS" != "Expired" && "$STATUS" != "Offline" && "$STATUS" != "Disconnected" ]]; then
      echo -e "${GREEN}Adding $MACHINE_NAME to $DCR_NAME${NC}"
      MACHINE_ID=$(az connectedmachine show --name "$MACHINE_NAME" --resource-group "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION" --query "id" --output tsv)
      # Create Data Collection Rule Association and suppress output if successful
      if az monitor data-collection rule association create --rule-id "$DCR_ID" --resource "$MACHINE_ID" --association-name "$DCR_ASSOCIATION_NAME" >/dev/null 2>&1; then
        echo -e "${GREEN}Done${NC}"
      else
        echo -e "${RED}Failed to add $MACHINE_NAME to $DCR_NAME${NC}" >&2
      fi
    else
      echo -e "${RED}Machine $MACHINE_NAME provisioning state: $PROVISIONING_STATE, status: $STATUS. Skipping.${NC}"
    fi
	
  else
    # Custom error message, suppressing detailed output
    echo -e "${RED}An error occurred while checking the machine $MACHINE_NAME. Skipping. Possible reasons: machine is offline, machine not registered with Azure Arc or machine does not exist within specified resource group or subscription${NC}"
  fi

done
