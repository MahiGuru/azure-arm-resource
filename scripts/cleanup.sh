#!/bin/bash

# Enhanced Cleanup Script
# Removes all resources created by the deployment script

# Configuration
CONFIG_DIR="./config"
ENVIRONMENT_FILE="$CONFIG_DIR/environment.yaml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Parse YAML
parse_yaml() {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

# Function to confirm action
confirm_action() {
    local message=$1
    local default_response=${2:-"N"}
    
    if [ "$default_response" = "Y" ]; then
        read -p "$message (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            return 1
        fi
    else
        read -p "$message (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    return 0
}

# Function to cleanup app registrations
cleanup_app_registrations() {
    log_step "Cleaning up app registrations..."
    
    local apps=("mahi-connector-app" "mahi-api-access" "mahi-teams-app" "app-proxy-saml-app" "chat-proxy-app")
    
    for app_name in "${apps[@]}"; do
        local full_name="$APP_PREFIX-$ENVIRONMENT-$app_name"
        log_info "Looking for app registration: $full_name"
        
        local app_id=$(az ad app list --display-name "$full_name" --query "[0].appId" -o tsv)
        
        if [ ! -z "$app_id" ] && [ "$app_id" != "null" ]; then
            log_info "Found app registration: $full_name ($app_id)"
            
            # Delete service principal first
            local sp_id=$(az ad sp list --display-name "$full_name" --query "[0].id" -o tsv)
            if [ ! -z "$sp_id" ] && [ "$sp_id" != "null" ]; then
                log_info "Deleting service principal: $sp_id"
                az ad sp delete --id $sp_id
            fi
            
            # Delete app registration
            log_info "Deleting app registration: $full_name"
            az ad app delete --id $app_id
            
            if [ $? -eq 0 ]; then
                log_info "✓ Deleted app registration: $full_name"
            else
                log_error "✗ Failed to delete app registration: $full_name"
            fi
        else
            log_warn "App registration not found: $full_name"
        fi
    done
}

# Function to cleanup bot registrations
cleanup_bot_registrations() {
    log_step "Cleaning up bot registrations..."
    
    local bot_name="$APP_PREFIX-$ENVIRONMENT-mahi-teams-bot"
    
    log_info "Looking for bot registration: $bot_name"
    
    # Check if bot exists
    local bot_exists=$(az bot show --resource-group $RESOURCE_GROUP --name $bot_name --query name -o tsv 2>/dev/null)
    
    if [ ! -z "$bot_exists" ]; then
        log_info "Found bot registration: $bot_name"
        
        # Delete bot channels first
        log_info "Deleting bot channels..."
        az bot msteams delete --resource-group $RESOURCE_GROUP --name $bot_name 2>/dev/null
        az bot webchat delete --resource-group $RESOURCE_GROUP --name $bot_name 2>/dev/null
        
        # Delete bot registration
        log_info "Deleting bot registration: $bot_name"
        az bot delete --resource-group $RESOURCE_GROUP --name $bot_name
        
        if [ $? -eq 0 ]; then
            log_info "✓ Deleted bot registration: $bot_name"
        else
            log_error "✗ Failed to delete bot registration: $bot_name"
        fi
    else
        log_warn "Bot registration not found: $bot_name"
    fi
}

# Function to cleanup enterprise applications
cleanup_enterprise_applications() {
    log_step "Cleaning up enterprise applications..."
    
    local enterprise_apps=("app-proxy-saml-app" "chat-proxy-app")
    
    for app_name in "${enterprise_apps[@]}"; do
        local full_name="$APP_PREFIX-$ENVIRONMENT-$app_name"
        log_info "Looking for enterprise application: $full_name"
        
        # Find enterprise application by display name
        local enterprise_app_id=$(az ad app list --display-name "$full_name" --query "[0].appId" -o tsv)
        
        if [ ! -z "$enterprise_app_id" ] && [ "$enterprise_app_id" != "null" ]; then
            log_info "Found enterprise application: $full_name ($enterprise_app_id)"
            
            # Delete service principal
            local sp_id=$(az ad sp list --display-name "$full_name" --query "[0].id" -o tsv)
            if [ ! -z "$sp_id" ] && [ "$sp_id" != "null" ]; then
                log_info "Deleting enterprise service principal: $sp_id"
                az ad sp delete --id $sp_id
            fi
            
            # Delete enterprise application
            log_info "Deleting enterprise application: $full_name"
            az ad app delete --id $enterprise_app_id
            
            if [ $? -eq 0 ]; then
                log_info "✓ Deleted enterprise application: $full_name"
            else
                log_error "✗ Failed to delete enterprise application: $full_name"
            fi
        else
            log_warn "Enterprise application not found: $full_name"
        fi
    done
}

# Function to cleanup Teams app artifacts
cleanup_teams_artifacts() {
    log_step "Cleaning up Teams app artifacts..."
    
    local teams_dir="./teams-manifest"
    
    if [ -d "$teams_dir" ]; then
        log_info "Removing Teams manifest directory: $teams_dir"
        rm -rf "$teams_dir"
        log_info "✓ Removed Teams manifest directory"
    else
        log_warn "Teams manifest directory not found: $teams_dir"
    fi
    
    # Remove configuration files
    local config_files=("deployment-output.txt" "bot-teams-config.txt" "deployment-checklist.md")
    
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            log_info "Removing configuration file: $file"
            rm -f "$file"
            log_info "✓ Removed configuration file: $file"
        fi
    done
}

# Function to cleanup Application Proxy configurations
cleanup_app_proxy() {
    log_step "Cleaning up Application Proxy configurations..."
    
    log_warn "Application Proxy configurations need to be removed manually from Azure Portal"
    log_warn "Please go to Azure AD > Enterprise Applications and remove:"
    log_warn "  - $APP_PREFIX-$ENVIRONMENT-app-proxy-saml-app"
    log_warn "  - $APP_PREFIX-$ENVIRONMENT-chat-proxy-app"
    log_warn "Also remove any associated Application Proxy connector configurations"
}

# Function to cleanup resource group
cleanup_resource_group() {
    log_step "Cleaning up resource group..."
    
    if confirm_action "Are you sure you want to delete the resource group '$RESOURCE_GROUP'? This will delete ALL resources in the group."; then
        log_warn "Deleting resource group: $RESOURCE_GROUP"
        az group delete --name $RESOURCE_GROUP --yes --no-wait
        
        if [ $? -eq 0 ]; then
            log_info "✓ Resource group deletion initiated: $RESOURCE_GROUP"
            log_info "Deletion is running in the background. Check Azure Portal for status."
        else
            log_error "✗ Failed to delete resource group: $RESOURCE_GROUP"
        fi
    else
        log_info "Resource group deletion cancelled"
    fi
}

# Function to list all resources before cleanup
list_resources() {
    log_step "Listing resources that will be deleted..."
    
    echo ""
    echo "=== Resources to be deleted ==="
    echo ""
    
    # List app registrations
    echo "App Registrations:"
    local apps=("mahi-connector-app" "mahi-api-access" "mahi-teams-app" "app-proxy-saml-app" "chat-proxy-app")
    for app_name in "${apps[@]}"; do
        local full_name="$APP_PREFIX-$ENVIRONMENT-$app_name"
        local app_id=$(az ad app list --display-name "$full_name" --query "[0].appId" -o tsv)
        if [ ! -z "$app_id" ] && [ "$app_id" != "null" ]; then
            echo "  ✓ $full_name ($app_id)"
        else
            echo "  ✗ $full_name (not found)"
        fi
    done
    
    echo ""
    echo "Bot Registrations:"
    local bot_name="$APP_PREFIX-$ENVIRONMENT-mahi-teams-bot"
    local bot_exists=$(az bot show --resource-group $RESOURCE_GROUP --name $bot_name --query name -o tsv 2>/dev/null)
    if [ ! -z "$bot_exists" ]; then
        echo "  ✓ $bot_name"
    else
        echo "  ✗ $bot_name (not found)"
    fi
    
    echo ""
    echo "Resource Group:"
    local rg_exists=$(az group show --name $RESOURCE_GROUP --query name -o tsv 2>/dev/null)
    if [ ! -z "$rg_exists" ]; then
        echo "  ✓ $RESOURCE_GROUP"
        
        # List resources in the group
        echo ""
        echo "Resources in $RESOURCE_GROUP:"
        az resource list --resource-group $RESOURCE_GROUP --query "[].{Name:name,Type:type,Location:location}" -o table
    else
        echo "  ✗ $RESOURCE_GROUP (not found)"
    fi
    
    echo ""
    echo "Local Files:"
    local files=("deployment-output.txt" "bot-teams-config.txt" "deployment-checklist.md" "teams-manifest/")
    for file in "${files[@]}"; do
        if [ -e "$file" ]; then
            echo "  ✓ $file"
        else
            echo "  ✗ $file (not found)"
        fi
    done
    
    echo ""
}

# Function to perform selective cleanup
selective_cleanup() {
    log_step "Selective cleanup options..."
    
    echo ""
    echo "What would you like to clean up?"
    echo "1. App registrations only"
    echo "2. Bot registrations only"
    echo "3. Enterprise applications only"
    echo "4. Teams artifacts only"
    echo "5. Everything except resource group"
    echo "6. Everything including resource group"
    echo "7. Cancel"
    echo ""
    read -p "Select an option (1-7): " choice
    
    case $choice in
        1) cleanup_app_registrations ;;
        2) cleanup_bot_registrations ;;
        3) cleanup_enterprise_applications ;;
        4) cleanup_teams_artifacts ;;
        5) 
            cleanup_app_registrations
            cleanup_bot_registrations
            cleanup_enterprise_applications
            cleanup_teams_artifacts
            cleanup_app_proxy
            ;;
        6) 
            cleanup_app_registrations
            cleanup_bot_registrations
            cleanup_enterprise_applications
            cleanup_teams_artifacts
            cleanup_app_proxy
            cleanup_resource_group
            ;;
        7) 
            log_info "Cleanup cancelled"
            exit 0
            ;;
        *) 
            log_error "Invalid option"
            exit 1
            ;;
    esac
}

# Function to perform full cleanup
full_cleanup() {
    log_step "Starting full cleanup process..."
    
    # Show what will be deleted
    list_resources
    
    if confirm_action "Proceed with cleanup?"; then
        cleanup_app_registrations
        cleanup_bot_registrations
        cleanup_enterprise_applications
        cleanup_teams_artifacts
        cleanup_app_proxy
        cleanup_resource_group
        
        log_step "Cleanup completed!"
        log_info "Some resources may take a few minutes to be fully deleted"
    else
        log_info "Cleanup cancelled"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if environment file exists
    if [ ! -f "$ENVIRONMENT_FILE" ]; then
        log_error "Environment configuration file not found: $ENVIRONMENT_FILE"
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

# Main execution
main() {
    echo "================================================="
    echo "Azure Resources Cleanup Script"
    echo "================================================="
    echo ""
    
    check_prerequisites
    
    # Parse environment configuration
    eval $(parse_yaml $ENVIRONMENT_FILE "env_")
    
    RESOURCE_GROUP=$env_environment_resource_group
    APP_PREFIX=$env_environment_application_prefix
    ENVIRONMENT=$env_environment_name
    
    log_info "Environment: $ENVIRONMENT"
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "App Prefix: $APP_PREFIX"
    echo ""
    
    # Check command line arguments
    if [ $# -eq 0 ]; then
        # Interactive mode
        echo "Cleanup Options:"
        echo "1. Full cleanup (everything)"
        echo "2. Selective cleanup"
        echo "3. List resources only"
        echo "4. Cancel"
        echo ""
        read -p "Select an option (1-4): " choice
        
        case $choice in
            1) full_cleanup ;;
            2) selective_cleanup ;;
            3) list_resources ;;
            4) log_info "Cleanup cancelled"; exit 0 ;;
            *) log_error "Invalid option"; exit 1 ;;
        esac
    else
        # Command line mode
        case $1 in
            "full") full_cleanup ;;
            "selective") selective_cleanup ;;
            "list") list_resources ;;
            "apps") cleanup_app_registrations ;;
            "bots") cleanup_bot_registrations ;;
            "enterprise") cleanup_enterprise_applications ;;
            "teams") cleanup_teams_artifacts ;;
            "rg") cleanup_resource_group ;;
            *) 
                echo "Usage: $0 [full|selective|list|apps|bots|enterprise|teams|rg]"
                echo ""
                echo "Options:"
                echo "  full        - Full cleanup (everything)"
                echo "  selective   - Interactive selective cleanup"
                echo "  list        - List resources only"
                echo "  apps        - Cleanup app registrations only"
                echo "  bots        - Cleanup bot registrations only"
                echo "  enterprise  - Cleanup enterprise applications only"
                echo "  teams       - Cleanup Teams artifacts only"
                echo "  rg          - Cleanup resource group only"
                exit 1
                ;;
        esac
    fi
}

# Run main function
main "$@"