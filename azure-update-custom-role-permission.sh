#! /bin/bash

app_id=""
sub_id=""
new_action=""

usage() {
    echo "Usage: $0 [args]"
    echo "-h This help message"
    echo "-a <app_id> - Your App ID"
    echo "-s <sub_id> - Your Subscription ID"
    echo "-p <permission> - Azure permission to add (e.g., 'Microsoft.Compute/virtualMachines/*')"
    exit 1
}

while getopts "ha:s:p:" optname; do
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
        p)
            new_action=${OPTARG}
            ;;
    esac
done

# Check if all required parameters are provided
if [[ -z "$app_id" || -z "$sub_id" || -z "$new_action" ]]; then
    echo "Error: Missing required parameters"
    echo ""
    usage
fi

echo "Adding permission '$new_action' to custom role for app id $app_id in subscription $sub_id"

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
    echo "To proceed, you need to create a custom role and assign it to the application."
    echo "You can use the azure-setup.sh script to create the required custom role."
    exit 1
fi

# Check if we found a controller role
if [ -n "$controller_role" ]; then
    echo ""
    echo "Found custom role containing 'controller-role': $controller_role"
    echo ""
    read -p "Do you want to update this controller role? [y/n] " -n 1
    echo ""
    
    if [[ "$REPLY" == "y" || "$REPLY" == "Y" ]]; then
        selected_role="$controller_role"
        echo "Selected controller role for update: $selected_role"
    else
        # Show all custom roles for selection
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
    fi
else
    echo ""
    echo "No custom role containing 'controller-role' found."
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
fi

echo ""
echo "Role selected for update: $selected_role"
echo ""

# Get current role definition
echo "Retrieving current role definition..."
current_role_def=$(az role definition list --name "$selected_role" --subscription $sub_id --output json)

# Extract all existing role properties
role_name=$(echo "$current_role_def" | jq -r '.[0].roleName')
role_id=$(echo "$current_role_def" | jq -r '.[0].id')
role_description=$(echo "$current_role_def" | jq -r '.[0].description')
role_type=$(echo "$current_role_def" | jq -r '.[0].roleType // "CustomRole"')
existing_not_actions=$(echo "$current_role_def" | jq -c '.[0].notActions // []')
existing_data_actions=$(echo "$current_role_def" | jq -c '.[0].dataActions // []')
existing_not_data_actions=$(echo "$current_role_def" | jq -c '.[0].notDataActions // []')
assignable_scopes=$(echo "$current_role_def" | jq -c '.[0].assignableScopes')

echo "Current role name: $role_name"
echo "Current role ID: $role_id"
echo "Current role description: $role_description"
echo "Current role type: $role_type"

echo ""
echo "Permission to add: $new_action"
echo ""
echo "Displaying current role permissions:"
existing_actions=$(echo "$current_role_def" | jq -r '.[0].permissions[0].actions[]? // .[0].actions[]?' 2>/dev/null | sort)
echo "$existing_actions"

echo ""
echo "Checking if permission already exists..."

# Get current actions as array for comparison
current_actions_array=()
while IFS= read -r line; do
    [[ -n "$line" ]] && current_actions_array+=("$line")
done <<< "$existing_actions"

# Check if the new action already exists
permission_exists=false
for current in "${current_actions_array[@]}"; do
    if [[ "$current" == "$new_action" ]]; then
        permission_exists=true
        break
    fi
done

if [[ "$permission_exists" == true ]]; then
    echo "Permission '$new_action' already exists in the role!"
    echo "No updates needed."
    exit 0
fi

echo "Adding new permission: $new_action"

# Add new action to existing actions
all_actions=("${current_actions_array[@]}" "$new_action")

# Create JSON array for actions
actions_json="["
for i in "${!all_actions[@]}"; do
    if [[ $i -gt 0 ]]; then
        actions_json+=","
    fi
    actions_json+='"'"${all_actions[$i]}"'"'
done
actions_json+="]"

# Create updated role definition JSON file preserving all existing properties
echo ""
echo "Creating updated role definition with new permission..."
echo "Preserving existing permissions and adding 1 new permission..."

cat > /tmp/updated_role.json <<- EOF
{
    "roleName": "$role_name",
    "Id": "$role_id", 
    "Description": "$role_description",
    "Actions": $actions_json,
    "NotActions": $existing_not_actions,
    "DataActions": $existing_data_actions,
    "NotDataActions": $existing_not_data_actions,
    "AssignableScopes": $assignable_scopes
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

