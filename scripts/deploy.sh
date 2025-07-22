#!/bin/bash

# Complete Azure Resource Deployment Script
# This script creates app registrations, enterprise applications, bot registrations, and Teams apps
# Includes all fixes for domain verification and enterprise application creation

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

# Initialize output file
init_output() {
    echo "Azure Resource Deployment Output" > $OUTPUT_FILE
    echo "Generated on: $(date)" >> $OUTPUT_FILE
    echo "=======================================" >> $OUTPUT_FILE
    echo "" >> $OUTPUT_FILE
}

# Function to cleanup existing resources before deployment
cleanup_existing_resources() {
    log_step "Cleaning up existing resources to prevent conflicts..."
    
    local apps=("mahi-connector-app" "mahi-api-access" "mahi-teams-app" "app-proxy-saml-app" "chat-proxy-app")
    
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

# Function to create resource group
create_resource_group() {
    log_step "Creating resource group: $RESOURCE_GROUP"
    
    az group create \
        --name $RESOURCE_GROUP \
        --location "$LOCATION" \
        --tags Environment=$ENVIRONMENT Project=AB Owner=Mahipal CreatedBy=azure-cli-templates
    
    if [ $? -eq 0 ]; then
        log_info "✓ Resource group created successfully"
        echo "Resource Group: $RESOURCE_GROUP" >> $OUTPUT_FILE
        echo "Location: $LOCATION" >> $OUTPUT_FILE
        echo "" >> $OUTPUT_FILE
    else
        log_error "Failed to create resource group"
        exit 1
    fi
}

# Function to create standard app registrations (not enterprise apps)
create_app_registrations() {
    log_step "Creating app registrations..."
    
    # App 1: Mahi Connector App
    create_app_registration "mahi-connector-app" "web" "https://$APP_PREFIX-$ENVIRONMENT-app1.azurewebsites.net/signin-oidc"
    
    # App 2: Mahi API Access (with exposed API)
    create_app_registration "mahi-api-access" "web" "https://$APP_PREFIX-$ENVIRONMENT-app2.azurewebsites.net/signin-oidc" true
    
    # App 3: Mahi Teams App
    create_app_registration "mahi-teams-app" "spa" "https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net/auth/callback"
}

# Function to create a single app registration
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
    
    # Configure redirect URIs based on app type
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
    
    # Create service principal
    local sp_id=$(az ad sp create --id $app_id --query id -o tsv)
    
    # Create client secret
    local secret=$(az ad app credential reset \
        --id $app_id \
        --append \
        --display-name "Auto-generated secret" \
        --query password -o tsv)
    
    # Save configuration to output file
    echo "=== App Registration: $full_name ===" >> $OUTPUT_FILE
    echo "App ID: $app_id" >> $OUTPUT_FILE
    echo "Service Principal ID: $sp_id" >> $OUTPUT_FILE
    echo "Client Secret: $secret" >> $OUTPUT_FILE
    echo "Redirect URI: $redirect_uri" >> $OUTPUT_FILE
    echo "Type: $app_type" >> $OUTPUT_FILE
    echo "" >> $OUTPUT_FILE
    
    log_info "✓ App registration created successfully: $full_name"
}

# Function to configure API permissions
configure_api_permissions() {
    local app_id=$1
    local app_name=$2
    
    log_info "Configuring API permissions for $app_name"
    
    # Microsoft Graph API ID
    local graph_api_id="00000003-0000-0000-c000-000000000000"
    
    # Define permissions based on app type
    case $app_name in
        "mahi-connector-app")
            # User.Read and User.ReadBasic.All
            az ad app permission add --id $app_id --api $graph_api_id --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope
            az ad app permission add --id $app_id --api $graph_api_id --api-permissions b340eb25-3456-403f-be2f-af7a0d370277=Scope
            ;;
        "mahi-api-access")
            # User.Read
            az ad app permission add --id $app_id --api $graph_api_id --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope
            ;;
        "mahi-teams-app")
            # User.Read and Team.ReadBasic.All
            az ad app permission add --id $app_id --api $graph_api_id --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope
            az ad app permission add --id $app_id --api $graph_api_id --api-permissions 485be79e-c497-4b35-9400-0e3fa7f2a5d4=Scope
            ;;
    esac
    
    # Grant admin consent
    sleep 10
    az ad app permission admin-consent --id $app_id 2>/dev/null || {
        log_warn "Admin consent failed for $app_name - may need manual approval"
    }
}

# Function to expose API scopes
expose_api_scopes() {
    local app_id=$1
    local app_name=$2
    
    log_info "Exposing API scopes for $app_name"
    
    # Set application ID URI
    az ad app update --id $app_id --identifier-uris "api://$app_id"
    
    # Generate UUIDs for scopes
    local scope_access_id=$(uuidgen)
    local scope_read_id=$(uuidgen)
    local scope_write_id=$(uuidgen)
    
    # Create OAuth2 permissions JSON
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
    
    # Update app with OAuth2 permissions
    az ad app update --id $app_id --set api.oauth2PermissionScopes@/tmp/oauth2_permissions.json
    
    # Clean up
    rm -f /tmp/oauth2_permissions.json
}

# FIXED: Function to create SAML enterprise application
create_saml_enterprise_application() {
    local app_name="app-proxy-saml-app"
    local full_name="$APP_PREFIX-$ENVIRONMENT-$app_name"
    
    log_step "Creating SAML enterprise application: $full_name"
    
    # Step 1: Create app registration WITHOUT identifier URIs initially
    local app_id=$(az ad app create \
        --display-name "$full_name" \
        --sign-in-audience "AzureADMyOrg" \
        --query appId -o tsv | tr -d '\r')

    if [ -z "$app_id" ]; then
        log_error "Failed to create app registration for SAML app"
        return 1
    fi

    log_info "Created app registration: $app_id"

    # Step 2: Retry loop for service principal creation
    local sp_id=""
    for attempt in {1..5}; do
        log_info "Attempt $attempt to create service principal..."
        sp_id=$(az ad sp create --id "$app_id" --query objectId -o tsv 2>/dev/null | tr -d '\r')

        if [ -n "$sp_id" ]; then
            break
        fi

        log_info "Waiting 5 seconds before retry..."
        sleep 5
    done

    if [ -z "$sp_id" ]; then
        log_error "Failed to create service principal for SAML app"
        return 1
    fi

    log_info "Created service principal (enterprise app): $sp_id"

    # Step 3: Configure service principal for SAML SSO
    az ad sp update \
        --id "$sp_id" \
        --set preferredSingleSignOnMode=saml

    # Step 4: Tag as enterprise application
    az ad sp update \
        --id "$sp_id" \
        --set tags='["Enterprise","SAML","SSO","CustomApp"]'

    
    # Step 5: Set identifier URI using SAFE format (no domain verification needed)
    local api_uri="api://$app_id"
    az ad app update --id $app_id --identifier-uris "$api_uri"
    
    log_info "✓ Set identifier URI to: $api_uri"
    
    # Step 6: Configure redirect URIs
    az ad app update \
        --id $app_id \
        --web-redirect-uris "https://saml-app-external.company.com/sso" "https://saml-app-external.company.com/acs"
    
    log_info "✓ SAML enterprise application created successfully"
    
    # Save configuration
    cat >> $OUTPUT_FILE << EOF
=== SAML Enterprise Application: $full_name ===
App ID: $app_id
Service Principal ID: $sp_id
Entity ID: $api_uri
ACS URL: https://saml-app-external.company.com/acs
SSO URL: https://saml-app-external.company.com/sso
Type: Enterprise Application (SAML)
Location: Azure AD > Enterprise Applications > $full_name

Manual Configuration Required:
1. Go to Azure AD > Enterprise Applications > $full_name
2. Configure Single Sign-On > SAML
3. Basic SAML Configuration:
   - Entity ID: $api_uri (already set)
   - ACS URL: https://saml-app-external.company.com/acs
   - Sign-on URL: https://saml-app-external.company.com
4. Download certificate and configure your app
5. Assign users and groups

EOF
    
    return 0
}

# FIXED: Function to create Application Proxy enterprise application
create_proxy_enterprise_application() {
    local app_name="chat-proxy-app"
    local full_name="$APP_PREFIX-$ENVIRONMENT-$app_name"
    
    log_step "Creating Application Proxy enterprise application: $full_name"
    
    # Step 1: Create app registration
    local app_id=$(az ad app create \
        --display-name "$full_name" \
        --sign-in-audience "AzureADMyOrg" \
        --query appId -o tsv)
    
    if [ -z "$app_id" ]; then
        log_error "Failed to create app registration for Application Proxy app"
        return 1
    fi
    
    log_info "Created app registration: $app_id"
    
    # Step 2: Create service principal IMMEDIATELY (this makes it an enterprise app)
    local sp_id=$(az ad sp create --id $app_id --query objectId -o tsv)
    
    if [ -z "$sp_id" ]; then
        log_error "Failed to create service principal for Application Proxy app"
        return 1
    fi
    
    log_info "Created service principal (enterprise app): $sp_id"
    
    # Step 3: Configure service principal for Application Proxy
    az ad sp update \
        --id $sp_id \
        --set preferredSingleSignOnMode=integrated
    
    # Step 4: Tag as enterprise application
    az ad sp update \
        --id $sp_id \
        --set tags='["Enterprise","ApplicationProxy","OnPrem","CustomApp"]'
    
    # Step 5: Configure redirect URIs (no domain verification needed for these)
    az ad app update \
        --id $app_id \
        --web-redirect-uris "https://chat-app-external.company.com/auth" "https://chat-app-external.company.com/signin-oidc" \
        --enable-id-token-issuance true \
        --enable-access-token-issuance true
    
    log_info "✓ Application Proxy enterprise application created successfully"
    
    # Save configuration
    cat >> $OUTPUT_FILE << EOF
=== Application Proxy Enterprise Application: $full_name ===
App ID: $app_id
Service Principal ID: $sp_id
Internal URL: http://internal-chat-app.company.com
External URL: https://chat-app-external.company.com
Type: Enterprise Application (Application Proxy)
Location: Azure AD > Enterprise Applications > $full_name

Manual Configuration Required:
1. Install Application Proxy connector if not already installed
2. Go to Azure AD > Enterprise Applications > $full_name
3. Configure Application Proxy:
   - Internal URL: http://internal-chat-app.company.com
   - External URL: https://chat-app-external.company.com
   - Pre-authentication: Azure Active Directory
   - Select connector group
4. Configure Single Sign-On if needed
5. Assign users and groups

EOF
    
    return 0
}

# FIXED: Main function to create enterprise applications
create_enterprise_applications() {
    log_step "Creating enterprise applications..."
    
    # Create SAML enterprise application
    if ! create_saml_enterprise_application; then
        log_error "Failed to create SAML enterprise application"
        return 1
    fi
    
    # Create Application Proxy enterprise application
    if ! create_proxy_enterprise_application; then
        log_error "Failed to create Application Proxy enterprise application"
        return 1
    fi
    
    log_info "✓ All enterprise applications created successfully"
    return 0
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
    
    # Create bot registration
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
    
    log_info "✓ Bot registration created successfully"
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
    
    log_info "✓ Bot channels configured"
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
    
    log_info "✓ Teams application configured"
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
    
    # Create deployment instructions
    cat > $manifest_dir/README.md << EOF
# Teams App Deployment Instructions

## Files Required
- manifest.json (created automatically)
- color.png (192x192px) - Create this icon
- outline.png (32x32px) - Create this icon

## Steps to Deploy
1. Create the required icon files
2. Create a ZIP file containing all three files
3. Go to Teams Admin Center
4. Navigate to Teams apps > Manage apps
5. Click "Upload" and select your ZIP file
6. Configure app permissions and policies

## Icon Requirements
- color.png: 192x192 pixels, color background
- outline.png: 32x32 pixels, white outline on transparent background
EOF
    
    log_info "Teams manifest created at $manifest_dir/manifest.json"
}

# Function to validate deployment
validate_deployment() {
    log_step "Validating deployment..."
    
    local validation_errors=0
    
    # Check if enterprise applications exist
    local saml_app_name="$APP_PREFIX-$ENVIRONMENT-app-proxy-saml-app"
    local proxy_app_name="$APP_PREFIX-$ENVIRONMENT-chat-proxy-app"
    
    # Check SAML enterprise application
    local saml_sp=$(az ad sp list --display-name "$saml_app_name" --query "[0].id" -o tsv)
    if [ ! -z "$saml_sp" ] && [ "$saml_sp" != "null" ]; then
        log_info "✓ SAML enterprise application found"
        
        # Check SSO mode
        local sso_mode=$(az ad sp show --id $saml_sp --query preferredSingleSignOnMode -o tsv)
        if [ "$sso_mode" == "saml" ]; then
            log_info "✓ SAML SSO mode correctly configured"
        else
            log_warn "⚠ SAML SSO mode is: $sso_mode (should be 'saml')"
            validation_errors=$((validation_errors + 1))
        fi
    else
        log_error "✗ SAML enterprise application not found"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check Application Proxy enterprise application
    local proxy_sp=$(az ad sp list --display-name "$proxy_app_name" --query "[0].id" -o tsv)
    if [ ! -z "$proxy_sp" ] && [ "$proxy_sp" != "null" ]; then
        log_info "✓ Application Proxy enterprise application found"
        
        # Check SSO mode
        local sso_mode=$(az ad sp show --id $proxy_sp --query preferredSingleSignOnMode -o tsv)
        if [ "$sso_mode" == "integrated" ]; then
            log_info "✓ Application Proxy SSO mode correctly configured"
        else
            log_warn "⚠ Application Proxy SSO mode is: $sso_mode (should be 'integrated')"
            validation_errors=$((validation_errors + 1))
        fi
    else
        log_error "✗ Application Proxy enterprise application not found"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check bot registration
    local bot_name="$APP_PREFIX-$ENVIRONMENT-mahi-teams-bot"
    local bot_exists=$(az bot show --resource-group $RESOURCE_GROUP --name $bot_name --query name -o tsv 2>/dev/null)
    if [ ! -z "$bot_exists" ]; then
        log_info "✓ Bot registration found"
    else
        log_error "✗ Bot registration not found"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check Teams app
    local teams_app_name="$APP_PREFIX-$ENVIRONMENT-mahi-teams-app"
    local teams_app_exists=$(az ad app list --display-name "$teams_app_name" --query "[0].appId" -o tsv)
    if [ ! -z "$teams_app_exists" ] && [ "$teams_app_exists" != "null" ]; then
        log_info "✓ Teams app registration found"
    else
        log_error "✗ Teams app registration not found"
        validation_errors=$((validation_errors + 1))
    fi
    
    if [ $validation_errors -eq 0 ]; then
        log_info "✓ All resources validated successfully"
        return 0
    else
        log_error "✗ Validation failed with $validation_errors errors"
        return 1
    fi
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
    
    log_info "✓ Prerequisites check passed"
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
    log_info "App Prefix: $APP_PREFIX"
    echo ""
    
    # Ask if user wants to clean up existing resources
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
    
    # Step 6: Validate Deployment
    validate_deployment
    
    log_step "Deployment completed successfully!"
    log_info "Check $OUTPUT_FILE for detailed output"
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
    echo "1. Go to Azure AD > Enterprise Applications to configure SAML and Application Proxy"
    echo "2. Upload Teams app manifest to Teams Admin Center"
    echo "3. Configure bot messaging endpoint in your application"
    echo "4. Test all applications and integrations"
    echo "5. Run './validate_enterprise_apps.sh' to verify everything is working"
}

# Run main function
main