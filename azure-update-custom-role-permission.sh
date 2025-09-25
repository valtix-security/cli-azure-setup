    #! /bin/bash

    app_id=""
    sub_id=""
    new_actions=""

    usage() {
        echo "Usage: $0 [args]"
        echo "-h This help message"
        echo "-a <app_id> - Your App ID"
        echo "-s <sub_id> - Your Subscription ID"
        echo "-p <permissions> - Comma-separated Azure permissions to add (e.g., 'Microsoft.Compute/virtualMachines/*,Microsoft.Storage/storageAccounts/*')"
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
                new_actions=${OPTARG}
                ;;
        esac
    done

    # Check if all required parameters are provided
    if [[ -z "$app_id" || -z "$sub_id" || -z "$new_actions" ]]; then
        echo "Error: Missing required parameters"
        echo ""
        usage
    fi

    # Parse comma-separated permissions into an array
    IFS=',' read -ra permissions_array <<< "$new_actions"
    
    echo "Adding permissions to custom role for app id $app_id in subscription $sub_id:"
    for permission in "${permissions_array[@]}"; do
        echo "  - $permission"
    done

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

    # Define your role definition ID and the new permission

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
echo "Permissions to add:"
for permission in "${permissions_array[@]}"; do
    echo "  - $permission"
done
echo ""
echo "Displaying current role permissions:"
existing_actions=$(echo "$current_role_def" | jq -r '.[0].permissions[0].actions[]? // .[0].actions[]?' 2>/dev/null | sort)
echo "$existing_actions"

echo ""
echo "Checking permissions..."

# Get current actions as array for comparison
current_actions_array=()
while IFS= read -r line; do
    [[ -n "$line" ]] && current_actions_array+=("$line")
done <<< "$existing_actions"

# Check which permissions already exist and which are new
existing_permissions=()
new_permissions=()

for permission in "${permissions_array[@]}"; do
    # Trim whitespace from permission
    permission=$(echo "$permission" | xargs)
    
    echo "Checking permission: $permission"
    
    # Check if permission already exists
    permission_exists=false
    for current in "${current_actions_array[@]}"; do
        if [[ "$current" == "$permission" ]]; then
            permission_exists=true
            break
        fi
    done
    
    if [[ "$permission_exists" == true ]]; then
        echo "  - Permission already exists: $permission"
        existing_permissions+=("$permission")
    else
        echo "  - Permission will be added: $permission"
        new_permissions+=("$permission")
    fi
done

# Report summary
echo ""
echo "Summary:"
echo "  - Existing permissions: ${#existing_permissions[@]}"
echo "  - New permissions to add: ${#new_permissions[@]}"

# Exit if no new permissions to add
if [ ${#new_permissions[@]} -eq 0 ]; then
    echo ""
    echo "No new permissions to add. All specified permissions already exist in the role."
    echo "No updates needed."
    exit 0
fi

echo ""
echo "Adding ${#new_permissions[@]} new permissions..."

# Add new permissions to existing actions
all_actions=("${current_actions_array[@]}" "${new_permissions[@]}")

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
echo "Creating updated role definition with new permissions..."
echo "Preserving existing permissions and adding ${#new_permissions[@]} new permission(s)..."

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
    echo "Added ${#new_permissions[@]} new permission(s) to the role:"
    for permission in "${new_permissions[@]}"; do
        echo "  - $permission"
    done

else
    echo "Failed to update role '$selected_role'"
    echo "Error details:"
    echo "$update_result"
fi

# Cleanup temporary file
rm -f /tmp/updated_role.json

echo ""
echo "Role update process completed."

