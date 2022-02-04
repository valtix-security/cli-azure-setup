#!/bin/bash

storageacct=""
resourcegroup="ValtixRG"
webhook_endpoint=""
location=""

usage() {
    echo "Usage: $0 [args]"
    echo "-h This help message"
    echo "-s <storage account> - Storage account name to create"
    echo "-w <webhook_endpoint> - Your Webhook Endpoint"
    echo "-l <location> - Your storage account location"
    exit 1
}

while getopts "h:s:w:l:" optname; do
    case "${optname}" in
        h)
            usage
            ;;
        s)
            storageacct=${OPTARG}
            ;;
        w)
            webhook_endpoint=${OPTARG}
            ;;
        l)
            location=${OPTARG}
            ;;
    esac
done

if [ "$(az group exists --name $resourcegroup)" == "false" ]; then
    echo "creating resource group $resourcegroup"
    az group create --location $location --name $resourcegroup
fi
if [ "$(az group exists --name $resourcegroup)" != "true" ]; then
    echo "The resource group doesn't exist"
    exit 1;
fi
storageacct_check=$(az storage account check-name --name $storageacct)
if [ "$(echo $storageacct_check | jq -r .nameAvailable)" == "false" ]; then
    echo "$(echo $storageacct_check | jq -r .reason): $(echo $storageacct_check | jq -r .message)"
    exit 1;
fi

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
    az account set --subscription ${id_list[$sub_selection]} --only-show-errors
    account_info=$(az account show -s ${id_list[$sub_selection]})
    sub_name=$(echo $account_info | jq -r .name)
    sub_id=$(echo $account_info | jq -r .id)
    unset IFS
fi

EVENT_SUB_NAME=vtxcontroller-discovery-$location
STORAGE_ACCT_NAME=$storageacct

echo "Storage Account Name: ${STORAGE_ACCT_NAME}"
echo "Resource Group      : ${resourcegroup}"
echo "Location            : ${location}"
echo "Webhook Endpoint    : ${webhook_endpoint}"
echo "Subscription ID     : ${sub_id}"

read -p "Continue creating? [y/n] " -n 1
echo ""
if [[ "$REPLY" != "y" ]]; then
    exit 1
fi

echo "create storage account $STORAGE_ACCT_NAME"
storageacct_id=$(az storage account create --name $STORAGE_ACCT_NAME --resource-group $resourcegroup --location $location | jq -r .id)

echo "Enabling microsoft.insights in Resource Providers"
az provider register --namespace 'microsoft.insights' --subscription $sub_id

echo "Enabling network watcher for $location"
az network watcher configure -g $resourcegroup -l $location --enabled true

#echo "Creating NSG Flow Log"
#az network watcher flow-log create --location $location --resource-group $resourcegroup --name MyFlowLog --nsg MyNetworkSecurityGroupName --storage-account $STORAGE_ACCT_NAME

echo "Creating event subscription"
az eventgrid event-subscription create \
  --source-resource-id "/subscriptions/$sub_id/resourceGroups/$resourcegroup/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCT_NAME" \
  --name $EVENT_SUB_NAME \
  --endpoint "$webhook_endpoint"

#TODO: delete script
cleanup_file="delete-discovery-$location-$sub_id.sh"
echo "Create uninstaller script in the current directory '$cleanup_file'"

cat > $cleanup_file <<- EOF
echo Delete Event Subscription $EVENT_SUB_NAME for the subscription $sub_id
az eventgrid event-subscription delete --source-resource-id /subscriptions/${sub_id} --name $EVENT_SUB_NAME
echo Delete storage account $STORAGE_ACCT_NAME from $resourcegroup
az storage account delete --name $STORAGE_ACCT_NAME --resource-group $resourcegroup
rm $cleanup_file
EOF
chmod +x $cleanup_file

echo
echo "----------------------------------------------------------------------------------"
echo "Storage Account: $storageacct_id"
echo "----------------------------------------------------------------------------------"
echo
