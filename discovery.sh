#!/bin/bash

storageacct=""
resourcegroup=""
subscription=""
location=""
tenant=""
controller=""

usage() {
    echo "Usage: $0 [args]"
    echo "-h This help message"
    echo "-a <Storage Account> - Storage account name to create"
    echo "-g <Resource Group>  - Resource group name to create storage account in"
    echo "-s <Subscription ID> - Your Azure Subscription ID"
    echo "-l <Location>        - Location to enable Network Watcher for"
    echo "-t <Tenant>          - Your Tenant name"
    echo "-c <Controller>      - Controller Endpoint"
    exit 1
}

while getopts "h:a:g:s:l:t:c:" optname; do
    case "${optname}" in
        h)
            usage
            ;;
        a)
            storageacct=${OPTARG}
            ;;
        g)
            resourcegroup=${OPTARG}
            ;;
        s)
            subscription=${OPTARG}
            ;;
        l)
            location=${OPTARG}
            ;;
        t)
            tenant=${OPTARG}
            ;;
        c)
            controller=${OPTARG}
            ;;
    esac
done

echo "Storage Account: ${storageacct}"
echo "Resource Group : ${resourcegroup}"
echo "Subscription ID: ${subscription}"
echo "Location       : ${location}"
echo "Tenant         : ${tenant}"
echo "Controller     : ${controller}"

read -p "Continue creating? [y/n] " -n 1
echo ""
if [[ "$REPLY" != "y" ]]; then
    exit 1
fi

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