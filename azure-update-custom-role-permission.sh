#! /bin/bash

app_id=""
sub_id=""
usage() {
    echo "Usage: $0 [args]"
    echo "-h This help message"
    echo "-a <app_id> - Your App ID"
    echo "-s <sub_id> - Your Subscription ID"
    exit 1
}

while getopts "ha:s:" optname; do
    case "${optname}" in
        h)
            usage
            ;;
        a)
            app_id=${OPTARG}
            ;;
        s)
            sub_id=${OPTARG}
            ;;
    esac
done

echo "Listing current role assignments for app id $app_id in subscription $sub_id"

# Display role assignments in table format
echo ""
echo "=== ALL ROLE ASSIGNMENTS FOR APPLICATION ==="
az role assignment list --assignee $app_id --subscription $sub_id --output table

echo ""
echo "Searching for controller roles "

# Get role assignments in JSON format
role_assignments=$(az role assignment list --assignee $app_id --subscription $sub_id --output json)

# Extract all role names
all_roles=($(echo "$role_assignments" | jq -r '.[].roleDefinitionName'))

# Function to check if a role is custom
check_if_custom_role() {
    local role_name="$1"
    local role_type=$(az role definition list --name "$role_name" --subscription $sub_id --output json | jq -r '.[0].roleType // "Unknown"')
    echo "$role_type"
}

# Function to create a new custom role
create_custom_role() {
    local role_name="ciscomcd-controller-role"
    
    echo "Creating custom role definition JSON..."
    
    cat > /tmp/new_custom_role.json <<- EOF
{
    "Name": "$role_name",
    "Description": "Custom role for Cisco Multicloud Defense Controller to manage Azure resources",
    "IsCustom": true,
    "Actions": [
        "Microsoft.ApiManagement/service/*",
        "Microsoft.Compute/disks/*",
        "Microsoft.Compute/images/read",
        "Microsoft.Compute/sshPublicKeys/read",
        "Microsoft.Compute/virtualMachines/*",
        "Microsoft.ManagedIdentity/userAssignedIdentities/read",
        "Microsoft.ManagedIdentity/userAssignedIdentities/assign/action",
        "Microsoft.Network/loadBalancers/*",
        "Microsoft.Network/natGateways/*",
        "Microsoft.Network/networkinterfaces/*",
        "Microsoft.Network/networkSecurityGroups/*",
        "Microsoft.Network/publicIPAddresses/*",
        "Microsoft.Network/routeTables/*",
        "Microsoft.Network/virtualNetworks/*",
        "Microsoft.Network/virtualNetworks/subnets/*",
        "Microsoft.Resources/subscriptions/resourcegroups/*",
        "Microsoft.Storage/storageAccounts/blobServices/*",
        "Microsoft.Storage/storageAccounts/listkeys/action",
        "Microsoft.Network/networkWatchers/*",
        "Microsoft.Network/applicationSecurityGroups/*",
        "Microsoft.Compute/diskEncryptionSets/read",
        "Microsoft.Insights/Metrics/Read",
        "Microsoft.Network/locations/serviceTagDetails/read",
        "Microsoft.Network/locations/serviceTags/read",
        "Microsoft.CognitiveServices/*/read",
        "Microsoft.CognitiveServices/accounts/listkeys/action",
        "Microsoft.Network/virtualHubs/*",
        "Microsoft.Network/virtualHubs/hubRouteTables/*",
        "Microsoft.MarketplaceOrdering/offertypes/publishers/offers/plans/agreements/*"
    ],
    "NotActions": [],
    "DataActions": [],
    "NotDataActions": [],
    "AssignableScopes": [
        "/subscriptions/$sub_id"
    ]
}
EOF

    echo "Creating custom role '$role_name'..."
    create_result=$(az role definition create --role-definition /tmp/new_custom_role.json --subscription $sub_id 2>&1)
    
    if [ $? -eq 0 ]; then
        echo " Custom role '$role_name' created successfully!"
    else
        echo "Failed to create custom role '$role_name'"
        echo "Error details: $create_result"
        
        # Check if role already exists
        if [[ "$create_result" == *"already exists"* ]]; then
            echo " Role already exists, continuing..."
        else
            echo "Exiting due to role creation failure."
            rm -f /tmp/new_custom_role.json
            exit 1
        fi
    fi
    
    # Cleanup temporary file
    rm -f /tmp/new_custom_role.json
}

# Function to assign role to application
assign_role_to_app() {
    local role_name="$1"
    
    echo "Assigning role '$role_name' to application '$app_id'..."
    
    # Get service principal object ID
    sp_object_id=$(az ad sp show --id $app_id --query id --output tsv 2>/dev/null)
    
    if [ -z "$sp_object_id" ]; then
        echo "Could not find service principal for app ID: $app_id"
        echo "Please ensure the application exists and you have permissions to access it."
        exit 1
    fi
    
    echo "Service Principal Object ID: $sp_object_id"
    
    # Assign role with retry logic
    for i in {1..5}; do
        assign_result=$(az role assignment create \
            --subscription $sub_id \
            --scope "/subscriptions/$sub_id" \
            --assignee-object-id $sp_object_id \
            --assignee-principal-type ServicePrincipal \
            --role "$role_name" 2>&1)
        
        if [ $? -eq 0 ]; then
            echo "Role '$role_name' assigned successfully to application!"
            break
        else
            if [[ "$assign_result" == *"already exists"* ]]; then
                echo "Role assignment already exists."
                break
            elif [ $i -eq 5 ]; then
                echo "Failed to assign role after 5 attempts"
                echo "Error details: $assign_result"
                exit 1
            else
                echo "Attempt $i failed, retrying in 10 seconds..."
                sleep 10
            fi
        fi
    done
}

# Filter only custom roles
echo "Filtering custom roles only..."
custom_roles=()
for role in "${all_roles[@]}"; do
    role_type=$(check_if_custom_role "$role")
    if [[ "$role_type" == "CustomRole" ]]; then
        custom_roles+=("$role")
        echo "Custom role found: $role"
    else
        echo "Skipping built-in role: $role"
    fi
done

# Find first custom role containing 'controller-role'
controller_role=""
for role in "${custom_roles[@]}"; do
    if [[ "$role" == *controller-role* ]]; then
        controller_role="$role"
        echo "Found custom controller-role: $controller_role"
        break
    fi
done

selected_role=""

# Check if we have any custom roles
if [ ${#custom_roles[@]} -eq 0 ]; then
    echo ""
    echo "No custom roles found for this application."
    echo "Only built-in roles are assigned, which cannot be modified."
    echo ""
    read -p "Do you want to create a new custom role 'ciscomcd-controller-role' and assign it to this application? [y/n] " -n 1
    echo ""
    
    if [[ "$REPLY" == "y" || "$REPLY" == "Y" ]]; then
        echo "Creating new custom role: ciscomcd-controller-role"
        
        # Create new custom role
        create_custom_role
        
        # Assign the new role to the application
        assign_role_to_app "ciscomcd-controller-role"
        
        echo "Successfully created and assigned custom role 'ciscomcd-controller-role'"
        echo "You can now run this script again to update the role permissions."
        exit 0
    else
        echo "No custom role created. Exiting."
        echo "To proceed, you need to either:"
        echo "  1. Create a custom role manually and assign it to the application"
        echo "  2. Run this script again and choose 'y' to create the role"
        exit 1
    fi
    
elif [ -z "$controller_role" ]; then
    echo ""
    echo "No custom role containing 'controller-role' found."
    echo ""
    read -p "Do you want to create a new custom role 'ciscomcd-controller-role'? [y/n] " -n 1
    echo ""
    
    if [[ "$REPLY" == "y" || "$REPLY" == "Y" ]]; then
        echo "Creating new custom role: ciscomcd-controller-role"
        
        # Create new custom role
        create_custom_role
        
        # Assign the new role to the application
        assign_role_to_app "ciscomcd-controller-role"
        
        selected_role="ciscomcd-controller-role"
        echo " Created and selected new custom role: $selected_role"
    else
        # Show existing custom roles for selection
        if [ ${#custom_roles[@]} -gt 0 ]; then
            echo "Available custom roles for selection:"
            echo ""
            for i in "${!custom_roles[@]}"; do
                echo "($i) ${custom_roles[$i]}"
            done
            echo ""
            read -p "Enter the number of the custom role you want to update (0-$((${#custom_roles[@]}-1))): " role_selection
            
            if [[ "$role_selection" =~ ^[0-9]+$ ]] && [ "$role_selection" -ge 0 ] && [ "$role_selection" -lt "${#custom_roles[@]}" ]; then
                selected_role="${custom_roles[$role_selection]}"
                echo "Selected custom role for update: $selected_role"
            else
                echo "Invalid selection. Exiting."
                exit 1
            fi
        else
            echo "No custom roles available. Exiting."
            exit 1
        fi
    fi
fi

# Skip role selection if we already have a selected role from new role creation
if [ -z "$selected_role" ] && [ -n "$controller_role" ]; then
    echo ""
    echo "Found custom role containing 'controller-role': $controller_role"
    echo ""
    read -p "Do you want to update this custom role? [y/n] " -n 1
    echo ""
    
    if [[ "$REPLY" == "y" || "$REPLY" == "Y" ]]; then
        selected_role="$controller_role"
        echo "Selected custom role for update: $selected_role"
    else
        echo "Showing all available custom roles for selection:"
        echo ""
        for i in "${!custom_roles[@]}"; do
            echo "($i) ${custom_roles[$i]}"
        done
        echo ""
        read -p "Enter the number of the custom role you want to update (0-$((${#custom_roles[@]}-1))): " role_selection
        
        if [[ "$role_selection" =~ ^[0-9]+$ ]] && [ "$role_selection" -ge 0 ] && [ "$role_selection" -lt "${#custom_roles[@]}" ]; then
            selected_role="${custom_roles[$role_selection]}"
            echo "Selected custom role for update: $selected_role"
        else
            echo "Invalid selection. Exiting."
            exit 1
        fi
    fi
elif [ -z "$selected_role" ]; then
    echo ""
    echo "No custom role containing 'controller-role' found."
    echo ""
    if [ ${#custom_roles[@]} -gt 0 ]; then
        echo "Available custom roles for selection:"
        echo ""
        for i in "${!custom_roles[@]}"; do
            echo "($i) ${custom_roles[$i]}"
        done
        echo ""
        read -p "Enter the number of the custom role you want to update (0-$((${#custom_roles[@]}-1))): " role_selection
        
        if [[ "$role_selection" =~ ^[0-9]+$ ]] && [ "$role_selection" -ge 0 ] && [ "$role_selection" -lt "${#custom_roles[@]}" ]; then
            selected_role="${custom_roles[$role_selection]}"
            echo "Selected custom role for update: $selected_role"
        else
            echo "Invalid selection. Exiting."
            exit 1
        fi
    else
        echo "No custom roles found for this application. Exiting."
        exit 1
    fi
fi

echo ""
echo "Role selected for update: $selected_role"
echo ""

# Get current role definition
echo "Retrieving current role definition..."
current_role_def=$(az role definition list --name "$selected_role" --subscription $sub_id --output json)
role_id=$(echo "$current_role_def" | jq -r '.[0].id')
role_description=$(echo "$current_role_def" | jq -r '.[0].description')
assignable_scopes=$(echo "$current_role_def" | jq -r '.[0].assignableScopes[]')
type=$(echo "$current_role_def" | jq -r '.[0].type // "Unknown"')

echo "Current role ID: $role_id"
echo "Current role description: $role_description"

# Create updated role definition JSON file
echo "Creating updated role definition with new permissions..."

cat > /tmp/updated_role.json <<- EOF
{
    "roleName": "$selected_role",
    "Id": "$role_id", 
    "Description": "$role_description",
    "RoleType": "CustomRole",
    "Actions": [
        "Microsoft.ApiManagement/service/*",
        "Microsoft.Compute/disks/*",
        "Microsoft.Compute/images/read",
        "Microsoft.Compute/sshPublicKeys/read",
        "Microsoft.Compute/virtualMachines/*",
        "Microsoft.ManagedIdentity/userAssignedIdentities/read",
        "Microsoft.ManagedIdentity/userAssignedIdentities/assign/action",
        "Microsoft.Network/loadBalancers/*",
        "Microsoft.Network/natGateways/*",
        "Microsoft.Network/networkinterfaces/*",
        "Microsoft.Network/networkSecurityGroups/*",
        "Microsoft.Network/publicIPAddresses/*",
        "Microsoft.Network/routeTables/*",
        "Microsoft.Network/virtualNetworks/*",
        "Microsoft.Network/virtualNetworks/subnets/*",
        "Microsoft.Resources/subscriptions/resourcegroups/*",
        "Microsoft.Storage/storageAccounts/blobServices/*",
        "Microsoft.Storage/storageAccounts/listkeys/action",
        "Microsoft.Network/networkWatchers/*",
        "Microsoft.Network/applicationSecurityGroups/*",
        "Microsoft.Compute/diskEncryptionSets/read",
        "Microsoft.Insights/Metrics/Read",
        "Microsoft.Network/locations/serviceTagDetails/read",
        "Microsoft.Network/locations/serviceTags/read",
        "Microsoft.CognitiveServices/*/read",
        "Microsoft.CognitiveServices/accounts/listkeys/action",
        "Microsoft.Network/virtualHubs/*",
        "Microsoft.Network/virtualHubs/hubRouteTables/*",
        "Microsoft.MarketplaceOrdering/offertypes/publishers/offers/plans/agreements/*"
    ],
    "AssignableScopes": [
        "/subscriptions/$sub_id"
    ]
}
EOF

echo ""
echo "Updating role '$selected_role' with new permissions..."

# Update the role definition
update_result=$(az role definition update --role-definition /tmp/updated_role.json --subscription $sub_id 2>&1)

if [ $? -eq 0 ]; then
    echo "Role '$selected_role' has been successfully updated!"
   
    
else
    echo "Failed to update role '$selected_role'"
    echo "Error details:"
    echo "$update_result"
fi

# Cleanup temporary file
rm -f /tmp/updated_role.json

echo ""
echo "Role update process completed."

