# cli-azure-setup
Create Azure AD App and Custom IAM Role. Multicloud Defense Controller uses the App to manage to your Azure Subscription

# Usage
```
bash azure-setup.sh -h
Usage: azure-setup.sh [args]
-h This help message
-p <prefix> - Prefix to use for the App and IAM Role, defaults to ciscomcd
```

The script creates AD App with \<prefix\>-controller-app and a custom IAM Role \<prefix\>-controller-role. It uses the default subscription to setup the scopes for the role. If you need to setup the scopes for a different subscription, change it on your shell before running the script.

The following commands can be used to change the active subscription

```
az account list --output table
az account set --subscription "subscription-name-from-the-above-output"
```

# Output
The script outputs the information required by the Multicloud Defense Controller for onboarding your Azure account

# Cleanup
A cleanup/uninstall script `delete-azure-setup.sh` is created by the setup script. Run this script if you want to delete the role and the app

# Manual Cleanup
1. Go to your subscription, search for the role and and delete the assignments and then the role
1. Go to Azure AD, App registrations, search for the app and delete it
