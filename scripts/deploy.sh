#!/bin/bash

# Load configuration
CONFIG_DIR="./config"
ENVIRONMENT_FILE="$CONFIG_DIR/environment.yaml"
APP_REG_FILE="$CONFIG_DIR/app-registrations.yaml"
OUTPUT_FILE="deployment-output.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Parse YAML (enhanced version)
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

# Initialize output file
init_output() {
    echo "Azure Resource Deployment Output" > $OUTPUT_FILE
    echo "Generated on: $(date)" >> $OUTPUT_FILE
    echo "=======================================" >> $OUTPUT_FILE
    echo "" >> $OUTPUT_FILE
}

# Function to clean up existing resources before deployment
cleanup_existing_resources() {
    log_step "Cleaning up existing resources to prevent conflicts..."
    
    local apps=("mahi-connector-app" "mahi-api-access" "mahi-teams-app")
    
    for app_name in "${apps[@]}"; do
        local full_name="$APP_PREFIX-$ENVIRONMENT-$app_name"
        
        # Check if app registration exists
        local existing_app_id=$(az ad app list --display-name "$full_name" --query "[0].appId" -o tsv)
        
        if [ ! -z "$existing_app_id" ] && [ "$existing_app_id" != "null" ]; then
            log_warn "Found existing app registration: $full_name"
            
            if confirm_action "Do you want to delete the existing app registration: $full_name?"; then
                # Delete service principal first
                local sp_id=$(az ad sp list --display-name "$full_name" --query "[0].id" -o tsv)
                if [ ! -z "$sp_id" ] && [ "$sp_id" != "null" ]; then
                    log_info "Deleting existing service principal: $sp_id"
                    az ad sp delete --id $sp_id
                fi
                
                # Delete app registration
                log_info "Deleting existing app registration: $full_name"
                az ad app delete --id $existing_app_id
                
                # Wait for deletion to complete
                sleep 5
            else
                log_warn "Skipping deletion of $full_name - this may cause conflicts"
            fi
        fi
    done
    
    # Check and clean up bot registration
    local bot_name="$APP_PREFIX-$ENVIRONMENT-mahi-teams-bot"
    local bot_exists=$(az bot show --resource-group $RESOURCE_GROUP --name $bot_name --query name -o tsv 2>/dev/null)
    
    if [ ! -z "$bot_exists" ]; then
        log_warn "Found existing bot registration: $bot_name"
        
        if confirm_action "Do you want to delete the existing bot registration: $bot_name?"; then
            log_info "Deleting existing bot registration: $bot_name"
            az bot delete --resource-group $RESOURCE_GROUP --name $bot_name
            sleep 5
        fi
    fi
}

# Function to confirm action
confirm_action() {
    local message=$1
    read -p "$message (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    fi
    return 1
}

# Main deployment function
deploy_resources() {
    log_step "Starting Azure resource deployment..."
    
    # Initialize output file
    init_output
    
    # Parse environment configuration
    eval $(parse_yaml $ENVIRONMENT_FILE "env_")
    
    RESOURCE_GROUP=$env_environment_resource_group
    LOCATION=$env_environment_location
    APP_PREFIX=$env_environment_application_prefix
    ENVIRONMENT=$env_environment_name
    TENANT_ID=$env_environment_tenant_id
    
    log_info "Environment: $ENVIRONMENT"
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Tenant ID: $TENANT_ID"
    
    # Ask if user wants to clean up existing resources
    echo ""
    if confirm_action "Do you want to clean up existing resources to prevent conflicts?"; then
        cleanup_existing_resources
    fi
    
    # Step 1: Create Resource Group
    create_resource_group
    
    # Step 2: Create App Registrations
    create_app_registrations
    
    # Step 3: Create Enterprise Applications
    create_enterprise_applications
    
    # Step 4: Create Bot Registration
    create_bot_registration
    
    # Step 5: Configure Teams App
    configure_teams_app
    
    log_step "Deployment completed successfully!"
    log_info "Check $OUTPUT_FILE for detailed output"
}

# Function to create resource group
create_resource_group() {
    log_step "Creating resource group: $RESOURCE_GROUP"
    
    az group create \
        --name $RESOURCE_GROUP \
        --location "$LOCATION" \
        --tags Environment=$ENVIRONMENT Project=AB Owner=Mahipal CreatedBy=azure-cli-templates
    
    if [ $? -eq 0 ]; then
        log_info "Resource group created successfully"
        echo "Resource Group: $RESOURCE_GROUP" >> $OUTPUT_FILE
        echo "Location: $LOCATION" >> $OUTPUT_FILE
        echo "" >> $OUTPUT_FILE
    else
        log_error "Failed to create resource group"
        exit 1
    fi
}

# Function to create app registrations
create_app_registrations() {
    log_step "Creating app registrations..."
    
    # App 1: Mahi Connector App
    create_app_registration "mahi-connector-app" "web" "https://$APP_PREFIX-$ENVIRONMENT-app1.azurewebsites.net/signin-oidc"
    
    # App 2: Mahi API Access (with exposed API)
    create_app_registration "mahi-api-access" "web" "https://$APP_PREFIX-$ENVIRONMENT-app2.azurewebsites.net/signin-oidc" true
    
    # App 3: Mahi Teams App
    create_app_registration "mahi-teams-app" "spa" "https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net/auth/callback"
}

# Enhanced function to create app registration
create_app_registration() {
    local app_name=$1
    local app_type=$2
    local redirect_uri=$3
    local expose_api=${4:-false}
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
    
    # Configure redirect URIs and enable tokens based on app type
    if [ "$app_type" == "web" ]; then
        az ad app update \
            --id $app_id \
            --web-redirect-uris "$redirect_uri" \
            --enable-id-token-issuance true \
            --enable-access-token-issuance true
    elif [ "$app_type" == "spa" ]; then
        az ad app update \
            --id $app_id \
            --public-client-redirect-uris "$redirect_uri" "https://token.botframework.com/.auth/web/redirect" \
            --enable-id-token-issuance true \
            --enable-access-token-issuance true
    fi
    
    # Configure API permissions
    configure_api_permissions $app_id $app_name
    
    # Expose API if required
    if [ "$expose_api" == "true" ]; then
        expose_api_scopes $app_id $app_name
    fi
    
    # Create service principal (check if it already exists)
    local sp_id=$(az ad sp list --display-name "$full_name" --query "[0].id" -o tsv)
    
    if [ -z "$sp_id" ] || [ "$sp_id" == "null" ]; then
        sp_id=$(az ad sp create \
            --id $app_id \
            --query id -o tsv)
        
        if [ $? -eq 0 ]; then
            log_info "Created service principal for $full_name (SP ID: $sp_id)"
        else
            log_warn "Service principal may already exist, trying to get existing one"
            sp_id=$(az ad sp list --display-name "$full_name" --query "[0].id" -o tsv)
        fi
    else
        log_info "Service principal already exists for $full_name (SP ID: $sp_id)"
    fi
    
    # Create client secret (use correct syntax for current Azure CLI)
    local secret=$(az ad app credential reset \
        --id $app_id \
        --append \
        --display-name "Auto-generated secret" \
        --query password -o tsv)
    
    log_info "Generated client secret for $full_name"
    
    # Save configuration to output file
    echo "=== App Registration: $full_name ===" >> $OUTPUT_FILE
    echo "App ID: $app_id" >> $OUTPUT_FILE
    echo "Service Principal ID: $sp_id" >> $OUTPUT_FILE
    echo "Client Secret: $secret" >> $OUTPUT_FILE
    echo "Redirect URI: $redirect_uri" >> $OUTPUT_FILE
    echo "Type: $app_type" >> $OUTPUT_FILE
    echo "" >> $OUTPUT_FILE
}

# Function to configure API permissions
configure_api_permissions() {
    local app_id=$1
    local app_name=$2
    
    log_info "Configuring API permissions for $app_name"
    
    # Get Microsoft Graph API ID
    local graph_api_id="00000003-0000-0000-c000-000000000000"
    
    # Define permissions based on app type
    case $app_name in
        "mahi-connector-app")
            # Add User.Read permission
            az ad app permission add \
                --id $app_id \
                --api $graph_api_id \
                --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope
            
            # Add User.ReadBasic.All permission
            az ad app permission add \
                --id $app_id \
                --api $graph_api_id \
                --api-permissions b340eb25-3456-403f-be2f-af7a0d370277=Scope
            ;;
        "mahi-api-access")
            # Add User.Read permission
            az ad app permission add \
                --id $app_id \
                --api $graph_api_id \
                --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope
            ;;
        "mahi-teams-app")
            # Add User.Read permission
            az ad app permission add \
                --id $app_id \
                --api $graph_api_id \
                --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope
            
            # Add Team.ReadBasic.All permission
            az ad app permission add \
                --id $app_id \
                --api $graph_api_id \
                --api-permissions 485be79e-c497-4b35-9400-0e3fa7f2a5d4=Scope
            ;;
    esac
    
    # Wait for permissions to propagate
    sleep 10
    
    # Grant admin consent with error handling
    log_info "Granting admin consent for $app_name"
    az ad app permission admin-consent --id $app_id 2>/dev/null || {
        log_warn "Admin consent failed for $app_name - this may need to be done manually in Azure Portal"
    }
}

# Function to expose API scopes
expose_api_scopes() {
    local app_id=$1
    local app_name=$2
    
    log_info "Exposing API scopes for $app_name"
    
    # Set application ID URI
    local app_id_uri="api://$app_id"
    az ad app update --id $app_id --identifier-uris $app_id_uri
    
    # Wait for app to be ready
    sleep 5
    
    # Generate UUIDs for scopes and roles
    local scope_access_id=$(uuidgen)
    local scope_read_id=$(uuidgen)
    local scope_write_id=$(uuidgen)
    local role_user_id=$(uuidgen)
    local role_admin_id=$(uuidgen)
    
    # Create a temporary JSON file for OAuth2 permissions
    cat > /tmp/oauth2_permissions.json << EOF
[
    {
        "adminConsentDescription": "Access to API endpoints",
        "adminConsentDisplayName": "API Access",
        "id": "$scope_access_id",
        "isEnabled": true,
        "type": "User",
        "userConsentDescription": "Access to API endpoints",
        "userConsentDisplayName": "API Access",
        "value": "api.access"
    },
    {
        "adminConsentDescription": "Read access to API",
        "adminConsentDisplayName": "API Read",
        "id": "$scope_read_id",
        "isEnabled": true,
        "type": "User",
        "userConsentDescription": "Read access to API",
        "userConsentDisplayName": "API Read",
        "value": "api.read"
    },
    {
        "adminConsentDescription": "Write access to API",
        "adminConsentDisplayName": "API Write",
        "id": "$scope_write_id",
        "isEnabled": true,
        "type": "Admin",
        "userConsentDescription": "Write access to API",
        "userConsentDisplayName": "API Write",
        "value": "api.write"
    }
]
EOF
    
    # Create a temporary JSON file for app roles
    cat > /tmp/app_roles.json << EOF
[
    {
        "allowedMemberTypes": ["User"],
        "description": "Users who can access the API",
        "displayName": "ApiUser",
        "id": "$role_user_id",
        "isEnabled": true,
        "value": "ApiUser"
    },
    {
        "allowedMemberTypes": ["User"],
        "description": "Administrators who can manage the API",
        "displayName": "ApiAdmin",
        "id": "$role_admin_id",
        "isEnabled": true,
        "value": "ApiAdmin"
    }
]
EOF
    
    # Update app with OAuth2 permissions using file
    az ad app update --id $app_id --set api.oauth2PermissionScopes@/tmp/oauth2_permissions.json
    
    # Wait for permissions to propagate
    sleep 5
    
    # Update app with app roles using file
    az ad app update --id $app_id --set appRoles@/tmp/app_roles.json
    
    # Clean up temporary files
    rm -f /tmp/oauth2_permissions.json /tmp/app_roles.json
    
    log_info "API scopes exposed for $app_name"
}

# Function to create enterprise applications
create_enterprise_applications() {
    log_step "Creating enterprise applications..."
    
    # Use the enterprise application wrapper script for proper enterprise app creation
    if [ -f "scripts/create-enterprise-apps.sh" ]; then
        log_info "Using enterprise application wrapper script..."
        ./scripts/create-enterprise-apps.sh
        
        if [ $? -eq 0 ]; then
            log_info "✓ Enterprise applications created successfully"
        else
            log_warn "Enterprise application wrapper failed, using fallback method"
            create_enterprise_apps_fallback
        fi
    else
        log_warn "Enterprise application wrapper not found, using fallback method"
        create_enterprise_apps_fallback
    fi
}

# Fallback method for enterprise applications
create_enterprise_apps_fallback() {
    log_info "Using fallback method for enterprise applications..."
    
    # SAML Enterprise App (fallback)
    create_saml_enterprise_app_fallback "app-proxy-saml-app" "http://internal-saml-app.company.com" "https://saml-app-external.company.com"
    
    # Application Proxy Enterprise App (fallback)
    create_proxy_enterprise_app_fallback "chat-proxy-app" "http://internal-chat-app.company.com" "https://chat-app-external.company.com"
}

# Fallback SAML enterprise application creation
create_saml_enterprise_app_fallback() {
    local app_name=$1
    local internal_url=$2
    local external_url=$3
    local full_name="$APP_PREFIX-$ENVIRONMENT-$app_name"
    
    log_info "Creating SAML enterprise application (fallback): $full_name"
    
    # Create app registration
    local app_id=$(az ad app create \
        --display-name "$full_name" \
        --sign-in-audience "AzureADMyOrg" \
        --web-redirect-uris "$external_url/sso" \
        --identifier-uris "$external_url" \
        --query appId -o tsv)
    
    if [ -z "$app_id" ]; then
        log_error "Failed to create SAML app: $full_name"
        return 1
    fi
    
    # Create service principal
    local sp_object_id=$(az ad sp create \
        --id $app_id \
        --query objectId -o tsv)
    
    if [ -z "$sp_object_id" ]; then
        log_error "Failed to create service principal: $full_name"
        return 1
    fi
    
    # Configure for SAML SSO
    az ad sp update \
        --id $sp_object_id \
        --set preferredSingleSignOnMode=saml \
        --set tags='["Enterprise","SAML","HideApp"]'
    
    log_info "✓ Created SAML enterprise application: $full_name"
    
    # Save configuration
    echo "=== SAML Enterprise Application (Fallback): $full_name ===" >> $OUTPUT_FILE
    echo "App ID: $app_id" >> $OUTPUT_FILE
    echo "Service Principal Object ID: $sp_object_id" >> $OUTPUT_FILE
    echo "Internal URL: $internal_url" >> $OUTPUT_FILE
    echo "External URL: $external_url" >> $OUTPUT_FILE
    echo "SAML SSO URL: $external_url/sso" >> $OUTPUT_FILE
    echo "Entity ID: $external_url" >> $OUTPUT_FILE
    echo "Note: May appear under App Registrations instead of Enterprise Applications" >> $OUTPUT_FILE
    echo "" >> $OUTPUT_FILE
}

# Fallback Application Proxy enterprise application creation
create_proxy_enterprise_app_fallback() {
    local app_name=$1
    local internal_url=$2
    local external_url=$3
    local full_name="$APP_PREFIX-$ENVIRONMENT-$app_name"
    
    log_info "Creating Application Proxy enterprise application (fallback): $full_name"
    
    # Create app registration
    local app_id=$(az ad app create \
        --display-name "$full_name" \
        --sign-in-audience "AzureADMyOrg" \
        --web-redirect-uris "$external_url/auth" \
        --enable-id-token-issuance true \
        --enable-access-token-issuance true \
        --query appId -o tsv)
    
    if [ -z "$app_id" ]; then
        log_error "Failed to create Application Proxy app: $full_name"
        return 1
    fi
    
    # Create service principal
    local sp_object_id=$(az ad sp create \
        --id $app_id \
        --query objectId -o tsv)
    
    if [ -z "$sp_object_id" ]; then
        log_error "Failed to create service principal: $full_name"
        return 1
    fi
    
    # Configure for Application Proxy
    az ad sp update \
        --id $sp_object_id \
        --set preferredSingleSignOnMode=integrated \
        --set tags='["Enterprise","ApplicationProxy","WebApp"]'
    
    log_info "✓ Created Application Proxy enterprise application: $full_name"
    
    # Save configuration
    echo "=== Application Proxy Enterprise Application (Fallback): $full_name ===" >> $OUTPUT_FILE
    echo "App ID: $app_id" >> $OUTPUT_FILE
    echo "Service Principal Object ID: $sp_object_id" >> $OUTPUT_FILE
    echo "Internal URL: $internal_url" >> $OUTPUT_FILE
    echo "External URL: $external_url" >> $OUTPUT_FILE
    echo "Note: May appear under App Registrations instead of Enterprise Applications" >> $OUTPUT_FILE
    echo "Complete configuration required in Azure Portal" >> $OUTPUT_FILE
    echo "" >> $OUTPUT_FILE
}

# Function to create bot registration
create_bot_registration() {
    log_step "Creating bot registration..."
    
    local bot_name="$APP_PREFIX-$ENVIRONMENT-mahi-teams-bot"
    local messaging_endpoint="https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net/api/messages"
    
    # Get the Teams app registration ID
    local teams_app_name="$APP_PREFIX-$ENVIRONMENT-mahi-teams-app"
    local teams_app_id=$(az ad app list --display-name "$teams_app_name" --query "[0].appId" -o tsv)
    
    if [ -z "$teams_app_id" ]; then
        log_error "Teams app not found for bot registration"
        return 1
    fi
    
    log_info "Creating bot registration: $bot_name"
    
    # Create bot registration using Azure Bot Service
    local bot_resource_id=$(az bot create \
        --resource-group $RESOURCE_GROUP \
        --name $bot_name \
        --kind "azurebot" \
        --app-id $teams_app_id \
        --location $LOCATION \
        --messaging-endpoint $messaging_endpoint \
        --query id -o tsv)
    
    if [ -z "$bot_resource_id" ]; then
        log_error "Failed to create bot registration"
        return 1
    fi
    
    # Configure bot channels
    configure_bot_channels $bot_name
    
    # Save bot configuration
    echo "=== Bot Registration ===" >> $OUTPUT_FILE
    echo "Bot Name: $bot_name" >> $OUTPUT_FILE
    echo "Bot Resource ID: $bot_resource_id" >> $OUTPUT_FILE
    echo "Teams App ID: $teams_app_id" >> $OUTPUT_FILE
    echo "Messaging Endpoint: $messaging_endpoint" >> $OUTPUT_FILE
    echo "" >> $OUTPUT_FILE
    
    log_info "Bot registration created successfully"
}

# Function to configure bot channels
configure_bot_channels() {
    local bot_name=$1
    
    log_info "Configuring bot channels..."
    
    # Enable Microsoft Teams channel
    az bot msteams create \
        --resource-group $RESOURCE_GROUP \
        --name $bot_name \
        --enable-calling true \
        --calling-web-hook "https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net/api/calls"
    
    # Enable Web Chat channel
    az bot webchat create \
        --resource-group $RESOURCE_GROUP \
        --name $bot_name
    
    log_info "Bot channels configured"
}

# Function to configure Teams app
configure_teams_app() {
    log_step "Configuring Teams application..."
    
    local teams_app_name="$APP_PREFIX-$ENVIRONMENT-mahi-teams-app"
    local teams_app_id=$(az ad app list --display-name "$teams_app_name" --query "[0].appId" -o tsv)
    
    if [ -z "$teams_app_id" ]; then
        log_error "Teams app not found"
        return 1
    fi
    
    # Create Teams app manifest
    create_teams_manifest $teams_app_id
    
    log_info "Teams application configured"
}

# Function to create Teams manifest
create_teams_manifest() {
    local teams_app_id=$1
    local manifest_dir="./teams-manifest"
    
    mkdir -p $manifest_dir
    
    # Create manifest.json
    cat > $manifest_dir/manifest.json << EOF
{
    "\$schema": "https://developer.microsoft.com/en-us/json-schemas/teams/v1.16/MicrosoftTeams.schema.json",
    "manifestVersion": "1.16",
    "version": "1.0.0",
    "id": "$teams_app_id",
    "packageName": "com.company.mahiteamsapp",
    "developer": {
        "name": "Mahipal Gurjala",
        "websiteUrl": "https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net",
        "privacyUrl": "https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net/privacy",
        "termsOfUseUrl": "https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net/terms"
    },
    "icons": {
        "color": "color.png",
        "outline": "outline.png"
    },
    "name": {
        "short": "Mahi Teams App",
        "full": "Mahi Teams Application"
    },
    "description": {
        "short": "Teams application for Mahi",
        "full": "Complete Teams application for Mahi with bot capabilities"
    },
    "accentColor": "#FFFFFF",
    "bots": [
        {
            "botId": "$teams_app_id",
            "scopes": [
                "personal",
                "team",
                "groupchat"
            ],
            "supportsFiles": false,
            "isNotificationOnly": false
        }
    ],
    "permissions": [
        "identity",
        "messageTeamMembers"
    ],
    "validDomains": [
        "$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net",
        "token.botframework.com"
    ]
}
EOF
    
    # Create placeholder icons (you should replace these with actual icons)
    echo "Create actual icon files:" >> $OUTPUT_FILE
    echo "  - $manifest_dir/color.png (192x192px)" >> $OUTPUT_FILE
    echo "  - $manifest_dir/outline.png (32x32px)" >> $OUTPUT_FILE
    echo "" >> $OUTPUT_FILE
    
    log_info "Teams manifest created at $manifest_dir/manifest.json"
}

# Pre-flight checks
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if configuration files exist
    if [ ! -f "$ENVIRONMENT_FILE" ]; then
        log_error "Environment configuration file not found: $ENVIRONMENT_FILE"
        exit 1
    fi
    
    if [ ! -f "$APP_REG_FILE" ]; then
        log_error "App registration configuration file not found: $APP_REG_FILE"
        exit 1
    fi
    
    # Check if uuidgen is available
    if ! command -v uuidgen &> /dev/null; then
        log_error "uuidgen is not installed. Please install it first."
        log_error "On Ubuntu/Debian: sudo apt-get install uuid-runtime"
        log_error "On CentOS/RHEL: sudo yum install util-linux"
        exit 1
    fi
    
    # Check current Azure subscription
    local subscription=$(az account show --query name -o tsv)
    local subscription_id=$(az account show --query id -o tsv)
    log_info "Current subscription: $subscription ($subscription_id)"
    
    if ! confirm_action "Continue with this subscription?"; then
        log_info "Please run 'az account set --subscription <subscription-name>' to change subscription"
        exit 1
    fi
    
    # Check if required extensions are available
    log_info "Checking Azure CLI extensions..."
    
    # Check if bot extension is available
    if ! az extension show --name botservice &> /dev/null; then
        log_warn "Installing Azure CLI extension: botservice"
        az extension add --name botservice
    fi
    
    log_info "Prerequisites check passed"
}

# Main execution
main() {
    echo "================================================="
    echo "Azure Resource Deployment Script"
    echo "================================================="
    echo ""
    
    check_prerequisites
    deploy_resources
    
    echo ""
    echo "================================================="
    echo "Deployment Summary:"
    echo "================================================="
    echo "✓ Resource Group: $RESOURCE_GROUP"
    echo "✓ App Registrations: 3 created"
    echo "✓ Enterprise Applications: 2 created"
    echo "✓ Bot Registration: 1 created"
    echo "✓ Teams App: Configured"
    echo ""
    echo "Check $OUTPUT_FILE for detailed information"
    echo ""
    echo "Next Steps:"
    echo "1. Configure Application Proxy settings in Azure Portal"
    echo "2. Upload Teams app manifest to Teams Admin Center"
    echo "3. Configure bot messaging endpoint in your application"
    echo "4. Test all applications and integrations"
}

# Run main function
main