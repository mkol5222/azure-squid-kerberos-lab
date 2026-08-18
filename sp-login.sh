#!/bin/bash

set -euo pipefail

echo "Logging in to Azure using Service Principal credentials from .env file..."

REQUIRED_VARS=(TF_VAR_appId TF_VAR_password TF_VAR_tenant TF_VAR_subscriptionId)
# id not present or empty, exit with error
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "$(dotenvx get "$var")" ]; then
    echo "Error: $var is not set or empty. Please set it in your .env file."
    echo "Create and store Azure Service Principal credentials first."
    exit 1
  fi
done

az login --service-principal -u $(dotenvx get TF_VAR_appId) -p $(dotenvx get TF_VAR_password) --tenant $(dotenvx get TF_VAR_tenant) -o table
az account set --subscription $(dotenvx get TF_VAR_subscriptionId)

echo
echo "Logged in successfully. Current subscription details:"
az account show -o table
echo
