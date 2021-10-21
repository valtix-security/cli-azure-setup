#! /bin/bash

PREFIX="valtix"

usage() {
    echo "Usage: $0 [args]"
    echo "-h This help message"
    echo "-p <prefix> - Prefix to use for the App and IAM Role, defaults to valtix"
    exit 1
}

while getopts "hp:" optname; do
    case "${optname}" in
        h)
            usage
            ;;
        p)
            PREFIX=${OPTARG}
            ;;
    esac
done

test=$(az account list | jq '.[] | .name')
printf "Select your subscription:\n"
IFS=$'\n'
num=0
subscription=($test)
for i in $test
do
        echo "($num) $i"
        num=$(( $num + 1 ))
done
num=$(($num-1))
read -p "Enter number from 0 - $num.  " yn
printf "You selected ${subscription[$yn]}\n"

echo "az account set --subscription ${subscription[$yn]} --only-show-errors"
az account show

APP_NAME=$PREFIX-vtxcontroller-app
ROLE_NAME=$PREFIX-vtxcontroller-role

account_info=$(az account show)
sub_name=$(echo $account_info | jq -r .name)
sub_id=$(echo $account_info | jq -r .id)
tenant_id=$(echo $account_info | jq -r .tenantId)

echo Using the subscription \"$sub_name / $sub_id\"
echo Create AD App Registraion $APP_NAME
echo Create Custom IAM Role $ROLE_NAME

read -p "Continue creating? [y/n] " -n 1 -r
echo ""
if [[ "$REPLY" != "y" ]]; then
    exit 1
fi

cat > /tmp/role.json <<- EOF
{
    "Name": "$ROLE_NAME",
    "Scope": "/subscriptions/$sub_id",
    "Actions": [
      "Microsoft.ApiManagement/service/*",
      "Microsoft.Compute/disks/*",
      "Microsoft.Compute/images/read",
      "Microsoft.Compute/sshPublicKeys/read",
      "Microsoft.Compute/virtualMachines/*",
      "Microsoft.ManagedIdentity/userAssignedIdentities/read",
      "Microsoft.ManagedIdentity/userAssignedIdentities/assign/action",
      "Microsoft.Network/loadBalancers/*",
      "Microsoft.Network/networkinterfaces/*",
      "Microsoft.Network/networkSecurityGroups/*",
      "Microsoft.Network/publicIPAddresses/*",
      "Microsoft.Network/routeTables/*",
      "Microsoft.Network/virtualNetworks/*",
      "Microsoft.Network/virtualNetworks/subnets/*",
      "Microsoft.Resources/subscriptions/resourcegroups/*",
      "Microsoft.Storage/storageAccounts/blobServices/*"
    ],
    "assignableScopes": [
        "/subscriptions/$sub_id"
    ]
}
EOF

echo "Create AD App Registration $APP_NAME"
app_output=$(az ad app create --display-name $APP_NAME)
app_id=$(echo $app_output | jq -r .appId)
echo "Create App Service Prinicipal $APP_NAME"
sp_object_id=$(az ad sp create --id $app_id | jq -r .objectId)
echo "Create App Secret"
secret=$(az ad app credential reset --id $app_id --credential-description 'valtix-secret' --years 5 2>/dev/null | jq -r .password)

echo "Create IAM Role $ROLE_NAME under subscription scope $sub_name"
az role definition create --role-definition /tmp/role.json &> /dev/null
echo "Assign the Role $ROLE_NAME to the App $APP_NAME"
az role assignment create --assignee-object-id $sp_object_id --assignee-principal-type ServicePrincipal --role $ROLE_NAME &> /dev/null

echo "Accept Marketplace agreements for Valtix Gateway Image"
az vm image terms accept --publisher valtix --offer datapath --plan valtix_dp_image --subscription $sub_id -o none

cleanup_file=delete-azure-setup.sh
echo "Create uninstaller script in the current directory '$cleanup_file'"
echo "echo Delete Role Assignment $ROLE_NAME for the AD app $APP_NAME" > $cleanup_file
echo "az role assignment delete --assignee $sp_object_id --role $ROLE_NAME" >> $cleanup_file
echo "echo Delete IAM Role $ROLE_NAME" >> $cleanup_file
echo "az role definition delete --name $ROLE_NAME" >> $cleanup_file
echo "echo Delete AD App Registration $APP_NAME" >> $cleanup_file
echo "az ad app delete --id $app_id" >> $cleanup_file
echo "rm $cleanup_file" >> $cleanup_file
chmod +x $cleanup_file

echo "################################################################################"
echo "## Below information will be needed to onboard subscription to Valtix Controller"
echo "################################################################################"
echo "Tenant/Directory: $tenant_id"
echo "Subscription: $sub_id"
echo "App: $app_id"
echo "Secret: $secret"
echo "################################################################################"
echo ""
