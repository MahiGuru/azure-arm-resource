#!/bin/bash

# Configuration
RESOURCE_GROUP="rg-myapp-dev"
APP_PREFIX="myapp"
ENVIRONMENT="dev"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

cleanup_resources() {
    log_info "Starting cleanup process..."
    
    # Delete app registrations
    log_info "Deleting app registrations..."
    
    local apps=("mahi-connector-app" "mahi-api-access" "mahi-teams-app")
    
    for app_name in "${apps[@]}"; do
        local full_name="$APP_PREFIX-$ENVIRONMENT-$app_name"
        local app_id=$(az ad app list --display-name "$full_name" --query "[0].appId" -o tsv)
        
        if [ ! -z "$app_id" ]; then
            az ad app delete --id $app_id
            log_info "Deleted app registration: $full_name"
        fi
    done
    
    # Delete resource group
    log_warn "Deleting resource group: $RESOURCE_GROUP"
    read -p "Are you sure you want to delete the resource group? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        az group delete --name $RESOURCE_GROUP --yes --no-wait
        log_info "Resource group deletion initiated"
    else
        log_info "Resource group deletion cancelled"
    fi
}

cleanup_resources