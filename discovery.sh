#!/bin/bash

storageacct=""
resourcegroup=""
webhook_endpoint=""

usage() {
    echo "Usage: $0 [args]"
    echo "-h This help message"
    echo "-s <storage account> - Storage account name to create"
    echo "-g <resource group>  - Resource group name to create storage account in"
    echo "-w <webhook_endpoint> - Your Webhook Endpoint"
    exit 1
}

while getopts "h:s:g:w:" optname; do
    case "${optname}" in
        h)
            usage
            ;;
        s)
            storageacct=${OPTARG}
            ;;
        g)
            resourcegroup=${OPTARG}
            ;;
        w)
            webhook_endpoint=${OPTARG}
            ;;
    esac
done

account_info=$(az account show)
sub_name=$(echo $account_info | jq -r .name)
sub_id=$(echo $account_info | jq -r .id)

echo "Your current subscription is ${sub_name} / ${sub_id}"
read -p "Is this the subscription you want to onboard to Valtix? [y/n] " -n 1

if [ "$REPLY" == "n" ]; then
    all_sub=$(az account list)
    sub_list=$(echo $all_sub | jq -r '.[].name')
    tmp_id_list=$(echo $all_sub | jq -r '.[].id')
    id_list=($tmp_id_list)
    echo "Select your subscription:"
    IFS=$'\n'
    num=0
    for i in $sub_list; do
        echo "($num) $i / ${id_list[$num]}"
        num=$(( $num + 1 ))
    done
    num=$(($num-1))
    read -p "Enter number from 0 - $num: " sub_selection
    tmp_sub_list=($sub_list)
    echo "Setting the subscription to ${tmp_sub_list[$sub_selection]} / ${id_list[$sub_selection]}"
    # az account set --subscription ${id_list[$sub_selection]} --only-show-errors
    account_info=$(az account show -s ${id_list[$sub_selection]})
    sub_name=$(echo $account_info | jq -r .name)
    sub_id=$(echo $account_info | jq -r .id)
    unset IFS
fi

EVENT_SUB_NAME=vtxcontroller-discovery
STORAGE_ACCT_NAME=$storageacct

echo "Storage Account: ${STORAGE_ACCT_NAME}"
echo "Resource Group : ${resourcegroup}"
echo "Webhook Endpoint : ${webhook_endpoint}"
echo "Subscription ID: ${sub_id}"

read -p "Continue creating? [y/n] " -n 1
echo ""
if [[ "$REPLY" != "y" ]]; then
    exit 1
fi

echo "create storage account $STORAGE_ACCT_NAME"
az storage account create --name $STORAGE_ACCT_NAME --resource-group $resourcegroup

echo "Enabling microsoft.insights in Resource Providers"
az provider register --namespace 'microsoft.insights' --subscription $sub_id

#echo "Creating NSG Flow Log"
#az network watcher flow-log create --location $location --resource-group $resourcegroup --name MyFlowLog --nsg MyNetworkSecurityGroupName --storage-account $STORAGE_ACCT_NAME

echo "Creating event subscription"
az eventgrid event-subscription create \
  --source-resource-id "/subscriptions/$sub_id/resourceGroups/$resourcegroup/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCT_NAME" \
  --name $EVENT_SUB_NAME \
  --endpoint "$webhook_endpoint"

#TODO: delete script
cleanup_file="delete-discovery-$sub_id.sh"
echo "Create uninstaller script in the current directory '$cleanup_file'"

cat > $cleanup_file <<- EOF
echo Delete Event Subscription $EVENT_SUB_NAME for the subscription $sub_id
az eventgrid event-subscription delete --source-resource-id /subscriptions/${sub_id} --name $EVENT_SUB_NAME
echo Delete storage account $STORAGE_ACCT_NAME from $resourcegroup
az storage account delete --name $STORAGE_ACCT_NAME --resource-group $resourcegroup
rm $cleanup_file
EOF
chmod +x $cleanup_file
