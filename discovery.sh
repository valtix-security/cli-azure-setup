#!/bin/bash

storageacct="himatejtestac"
resourcegroup="eastrg"
subscription="5e042c15-8e3e-41a6-8dfc-05b1fc703aa7"
location="eastus"
tenant=""
controller=""

echo "create storage account $storageacct"
az storage account create --name  --resource-group $resourcegroup

echo "Enabling microsoft.insights in Resource Providers"
az provider register --namespace 'microsoft.insights' --subscription $subscription

echo "Enabling network watcher for $location"
az network watcher configure -g $resourcegroup  -l $location --enabled true

#echo "Creating NSG Flow Log"
#az network watcher flow-log create --location $location --resource-group $resourcegroup --name MyFlowLog --nsg MyNetworkSecurityGroupName --storage-account $storageacct

echo "Creating event subscription"
az eventgrid event-subscription create \
  --source-resource-id "/subscriptions/$subscription/resourceGroups/$resourcegroup/providers/Microsoft.Storage/storageAccounts/$storageacct" \
  --name valtixcontroller \
  --endpoint "$controller/webhook/$tenant/azure"