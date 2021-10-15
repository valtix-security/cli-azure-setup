#! /bin/bash

PREFIX=$1

if [ "$PREFIX" = "" ]; then
    echo "Usage: $0 <prefix>"
    echo "<prefix>-valtix-controller-app and <prefix>-valtix-controller-role are created"
    exit 1
fi

APP_NAME=$PREFIX-valtix-controller-app
ROLE_NAME=$PREFIX-valtix-controller-role

account_info=$(az account show)
sub_id=$(echo $account_info | jq -r .id)
tenant_id=$(echo $account_info | jq -r .tenantId)

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

echo "Create AD App Registration"
app_output=$(az ad app create --display-name $APP_NAME)
app_id=$(echo $app_output | jq -r .appId)
echo "Create App Service Prinicipal"
sp_object_id=$(az ad sp create --id $app_id | jq -r .objectId)
echo "Create App Secret"
secret=$(az ad app credential reset --id $app_id --credential-description 'valtix-secret' --years 5 2>/dev/null | jq -r .password)

echo "Create IAM Role"
az role definition create --role-definition /tmp/role.json &> /dev/null
echo "Assign the Role to the App"
az role assignment create --assignee-object-id $sp_object_id --assignee-principal-type ServicePrincipal --role $ROLE_NAME &> /dev/null

echo "Accept Marketplace agreements for Valtix Gateway Image"
az vm image terms accept --publisher valtix --offer datapath --plan valtix_dp_image --subscription $sub_id -o none

cleanup_file=delete-azure-setup.sh
echo "Create uninstaller script in the current directory '$cleanup_file'"
echo "echo Delete Role Assignment" > $cleanup_file
echo "az role assignment delete --assignee $sp_object_id --role $ROLE_NAME" >> $cleanup_file
echo "echo Delete IAM Role" >> $cleanup_file
echo "az role definition delete --name $ROLE_NAME" >> $cleanup_file
echo "echo Delete AD App Registration" >> $cleanup_file
echo "az ad app delete --id $app_id" >> $cleanup_file
echo "rm $cleanup_file" >> $cleanup_file
chmod +x $cleanup_file

echo ""
echo "Tenant/Directory: $tenant_id"
echo "Subscription: $sub_id"
echo "App: $app_id"
echo "Secret: $secret"
echo ""
