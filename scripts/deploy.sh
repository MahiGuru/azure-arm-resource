#!/bin/bash

# Load configuration
CONFIG_DIR="./config"
ENVIRONMENT_FILE="$CONFIG_DIR/environment.yaml"
APP_REG_FILE="$CONFIG_DIR/app-registrations.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse YAML (simple approach)
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

# Main deployment function
deploy_resources() {
    log_info "Starting Azure resource deployment..."
    
    # Parse environment configuration
    eval $(parse_yaml $ENVIRONMENT_FILE "env_")
    
    RESOURCE_GROUP=$env_environment_resource_group
    LOCATION=$env_environment_location
    APP_PREFIX=$env_environment_application_prefix
    ENVIRONMENT=$env_environment_name
    
    log_info "Environment: $ENVIRONMENT"
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    
    # Step 1: Create Resource Group
    log_info "Creating resource group: $RESOURCE_GROUP"
    az group create \
        --name $RESOURCE_GROUP \
        --location "$LOCATION" \
        --tags Environment=$ENVIRONMENT Project=MyApp CreatedBy=azure-cli-templates
    
    if [ $? -eq 0 ]; then
        log_info "Resource group created successfully"
    else
        log_error "Failed to create resource group"
        exit 1
    fi
    
    # Step 2: Create App Registrations
    log_info "Creating app registrations..."
    
    # App 1: Mahi Connector App
    create_app_registration "mahi-connector-app" "web" "https://$APP_PREFIX-$ENVIRONMENT-app1.azurewebsites.net/signin-oidc"
    
    # App 2: Mahi API Access
    create_app_registration "mahi-api-access" "web" "https://$APP_PREFIX-$ENVIRONMENT-app2.azurewebsites.net/signin-oidc"
    
    # App 3: Mahi Teams App
    create_app_registration "mahi-teams-app" "spa" "https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net/auth/callback"
    
    log_info "Deployment completed successfully!"
}

# Function to create app registration
create_app_registration() {
    local app_name=$1
    local app_type=$2
    local redirect_uri=$3
    local full_name="$APP_PREFIX-$ENVIRONMENT-$app_name"
    
    log_info "Creating app registration: $full_name"
    
    # Create the app registration
    local app_id=$(az ad app create \
        --display-name "$full_name" \
        --sign-in-audience "AzureADMyOrg" \
        --query appId -o tsv)
    
    if [ -z "$app_id" ]; then
        log_error "Failed to create app registration: $full_name"
        return 1
    fi
    
    log_info "Created app registration: $full_name (App ID: $app_id)"
    
    # Configure redirect URIs based on app type
    if [ "$app_type" == "web" ]; then
        az ad app update \
            --id $app_id \
            --web-redirect-uris "$redirect_uri" \
            --enable-id-token-issuance true
    elif [ "$app_type" == "spa" ]; then
        az ad app update \
            --id $app_id \
            --public-client-redirect-uris "$redirect_uri"
    fi
    
    # Create service principal
    local sp_id=$(az ad sp create \
        --id $app_id \
        --query id -o tsv)
    
    log_info "Created service principal for $full_name (SP ID: $sp_id)"
    
    # Create client secret
    local secret=$(az ad app credential reset \
        --id $app_id \
        --append \
        --credential-description "Auto-generated secret" \
        --query password -o tsv)
    
    log_info "Generated client secret for $full_name"
    
    # Save configuration to output file
    echo "App: $full_name" >> deployment-output.txt
    echo "App ID: $app_id" >> deployment-output.txt
    echo "Service Principal ID: $sp_id" >> deployment-output.txt
    echo "Client Secret: $secret" >> deployment-output.txt
    echo "---" >> deployment-output.txt
}

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

# Run deployment
deploy_resources