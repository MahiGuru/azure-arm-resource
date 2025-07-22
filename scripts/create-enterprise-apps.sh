#!/bin/bash

# Create Enterprise Applications Script
# This script creates true enterprise applications (not app registrations)
# Required for SAML SSO and Application Proxy functionality

CONFIG_DIR="./config"
ENVIRONMENT_FILE="$CONFIG_DIR/environment.yaml"
OUTPUT_FILE="enterprise-apps-output.txt"

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

# Initialize output file
init_output() {
    echo "Enterprise Applications Deployment Output" > $OUTPUT_FILE
    echo "Generated on: $(date)" >> $OUTPUT_FILE
    echo "=======================================" >> $OUTPUT_FILE
    echo "" >> $OUTPUT_FILE
}

# Function to create SAML enterprise application
create_saml_enterprise_app() {
    local app_name=$1
    local internal_url=$2
    local external_url=$3
    local full_name="$APP_PREFIX-$ENVIRONMENT-$app_name"
    
    log_step "Creating SAML enterprise application: $full_name"
    
    # Step 1: Create a non-gallery application (enterprise application)
    log_info "Creating non-gallery enterprise application..."
    
    # Create app registration first (required for enterprise app)
    local app_id=$(az ad app create \
        --display-name "$full_name" \
        --sign-in-audience "AzureADMyOrg" \
        --query appId -o tsv)
    
    if [ -z "$app_id" ]; then
        log_error "Failed to create app registration for SAML app: $full_name"
        return 1
    fi
    
    # Create service principal (this creates the enterprise application)
    local sp_object_id=$(az ad sp create \
        --id $app_id \
        --query objectId -o tsv)
    
    if [ -z "$sp_object_id" ]; then
        log_error "Failed to create service principal for SAML app: $full_name"
        return 1
    fi
    
    # Step 2: Configure as SAML application
    log_info "Configuring SAML SSO..."
    
    # Set the application to use SAML
    az ad sp update \
        --id $sp_object_id \
        --set preferredSingleSignOnMode=saml
    
    # Configure SAML settings
    az ad app update \
        --id $app_id \
        --identifier-uris "$external_url" \
        --web-redirect-uris "$external_url/sso" "$external_url/acs"
    
    # Step 3: Configure SAML claims
    log_info "Configuring SAML claims..."
    
    # Create claims configuration
    local claims_config=$(cat << EOF
[
    {
        "name": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname",
        "source": "user",
        "essential": false,
        "additionalProperties": {}
    },
    {
        "name": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname",
        "source": "user",
        "essential": false,
        "additionalProperties": {}
    },
    {
        "name": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress",
        "source": "user",
        "essential": false,
        "additionalProperties": {}
    }
]
EOF
)
    
    # Apply claims configuration
    echo "$claims_config" > /tmp/saml_claims.json
    az ad app update --id $app_id --optional-claims saml2Token=@/tmp/saml_claims.json
    rm -f /tmp/saml_claims.json
    
    # Step 4: Configure tags for enterprise application
    az ad sp update \
        --id $sp_object_id \
        --set tags='["Enterprise","SAML","SSO","CustomApp"]'
    
    log_info "✓ SAML enterprise application created successfully"
    
    # Save configuration
    cat >> $OUTPUT_FILE << EOF
=== SAML Enterprise Application: $full_name ===
App ID: $app_id
Service Principal Object ID: $sp_object_id
Internal URL: $internal_url
External URL: $external_url
Entity ID: $external_url
SSO URL: $external_url/sso
ACS URL: $external_url/acs
Type: Non-gallery SAML application
Location: Azure AD > Enterprise Applications > $full_name

Manual Configuration Required:
1. Go to Azure AD > Enterprise Applications > $full_name
2. Configure Single Sign-On:
   - Select SAML
   - Set Entity ID: $external_url
   - Set ACS URL: $external_url/acs
   - Set Sign-on URL: $external_url
3. Download certificate and configure your app
4. Assign users and groups

EOF
    
    return 0
}

# Function to create Application Proxy enterprise application
create_proxy_enterprise_app() {
    local app_name=$1
    local internal_url=$2
    local external_url=$3
    local full_name="$APP_PREFIX-$ENVIRONMENT-$app_name"
    
    log_step "Creating Application Proxy enterprise application: $full_name"
    
    # Step 1: Create app registration
    log_info "Creating app registration for Application Proxy..."
    
    local app_id=$(az ad app create \
        --display-name "$full_name" \
        --sign-in-audience "AzureADMyOrg" \
        --query appId -o tsv)
    
    if [ -z "$app_id" ]; then
        log_error "Failed to create app registration for proxy app: $full_name"
        return 1
    fi
    
    # Step 2: Create service principal (enterprise application)
    local sp_object_id=$(az ad sp create \
        --id $app_id \
        --query objectId -o tsv)
    
    if [ -z "$sp_object_id" ]; then
        log_error "Failed to create service principal for proxy app: $full_name"
        return 1
    fi
    
    # Step 3: Configure for Application Proxy
    log_info "Configuring Application Proxy settings..."
    
    # Set SSO method to integrated (for Application Proxy)
    az ad sp update \
        --id $sp_object_id \
        --set preferredSingleSignOnMode=integrated
    
    # Configure redirect URIs for proxy
    az ad app update \
        --id $app_id \
        --web-redirect-uris "$external_url/auth" "$external_url/signin-oidc"
    
    # Step 4: Configure tags for enterprise application
    az ad sp update \
        --id $sp_object_id \
        --set tags='["Enterprise","ApplicationProxy","OnPrem","CustomApp"]'
    
    log_info "✓ Application Proxy enterprise application created successfully"
    
    # Save configuration
    cat >> $OUTPUT_FILE << EOF
=== Application Proxy Enterprise Application: $full_name ===
App ID: $app_id
Service Principal Object ID: $sp_object_id
Internal URL: $internal_url
External URL: $external_url
Type: Application Proxy application
Location: Azure AD > Enterprise Applications > $full_name

Manual Configuration Required:
1. Ensure Application Proxy connector is installed and running
2. Go to Azure AD > Enterprise Applications > $full_name
3. Configure Application Proxy:
   - Set Internal URL: $internal_url
   - Set External URL: $external_url
   - Set Pre-authentication: Azure Active Directory
   - Configure connector group
4. Configure Single Sign-On if needed
5. Assign users and groups

EOF
    
    return 0
}

# Function to create enterprise applications with proper configuration
create_enterprise_applications() {
    log_step "Creating enterprise applications..."
    
    # Parse environment configuration
    eval $(parse_yaml $ENVIRONMENT_FILE "env_")
    
    APP_PREFIX=$env_environment_application_prefix
    ENVIRONMENT=$env_environment_name
    
    # Initialize output file
    init_output
    
    # Create SAML enterprise application
    create_saml_enterprise_app \
        "app-proxy-saml-app" \
        "http://internal-saml-app.company.com" \
        "https://saml-app-external.company.com"
    
    # Create Application Proxy enterprise application
    create_proxy_enterprise_app \
        "chat-proxy-app" \
        "http://internal-chat-app.company.com" \
        "https://chat-app-external.company.com"
    
    log_step "Enterprise applications created successfully!"
    log_info "Check $OUTPUT_FILE for detailed configuration"
    
    return 0
}

# Function to validate enterprise applications
validate_enterprise_apps() {
    log_step "Validating enterprise applications..."
    
    eval $(parse_yaml $ENVIRONMENT_FILE "env_")
    APP_PREFIX=$env_environment_application_prefix
    ENVIRONMENT=$env_environment_name
    
    local apps=("app-proxy-saml-app" "chat-proxy-app")
    local validation_passed=true
    
    for app_name in "${apps[@]}"; do
        local full_name="$APP_PREFIX-$ENVIRONMENT-$app_name"
        
        # Check if enterprise application exists
        local sp_id=$(az ad sp list --display-name "$full_name" --query "[0].id" -o tsv)
        
        if [ ! -z "$sp_id" ] && [ "$sp_id" != "null" ]; then
            log_info "✓ Enterprise application exists: $full_name"
            
            # Check SSO configuration
            local sso_mode=$(az ad sp show --id $sp_id --query preferredSingleSignOnMode -o tsv)
            log_info "  SSO Mode: $sso_mode"
            
            # Check tags
            local tags=$(az ad sp show --id $sp_id --query tags -o tsv)
            log_info "  Tags: $tags"
            
        else
            log_error "✗ Enterprise application not found: $full_name"
            validation_passed=false
        fi
    done
    
    if [ "$validation_passed" = true ]; then
        log_info "✓ All enterprise applications validated successfully"
        return 0
    else
        log_error "✗ Enterprise application validation failed"
        return 1
    fi
}

# Function to list enterprise applications
list_enterprise_apps() {
    log_step "Listing enterprise applications..."
    
    eval $(parse_yaml $ENVIRONMENT_FILE "env_")
    APP_PREFIX=$env_environment_application_prefix
    ENVIRONMENT=$env_environment_name
    
    echo ""
    echo "=== Enterprise Applications ==="
    echo ""
    
    local apps=("app-proxy-saml-app" "chat-proxy-app")
    
    for app_name in "${apps[@]}"; do
        local full_name="$APP_PREFIX-$ENVIRONMENT-$app_name"
        
        # Get service principal info
        local sp_info=$(az ad sp list --display-name "$full_name" --query "[0].{id:id,appId:appId,displayName:displayName,preferredSingleSignOnMode:preferredSingleSignOnMode}" -o json)
        
        if [ "$sp_info" != "null" ] && [ ! -z "$sp_info" ]; then
            echo "Enterprise App: $full_name"
            echo "$sp_info" | jq -r '"  App ID: " + .appId + "\n  SP ID: " + .id + "\n  SSO Mode: " + .preferredSingleSignOnMode'
            echo ""
        else
            echo "Enterprise App: $full_name (NOT FOUND)"
            echo ""
        fi
    done
}

# Function to cleanup enterprise applications
cleanup_enterprise_apps() {
    log_step "Cleaning up enterprise applications..."
    
    eval $(parse_yaml $ENVIRONMENT_FILE "env_")
    APP_PREFIX=$env_environment_application_prefix
    ENVIRONMENT=$env_environment_name
    
    local apps=("app-proxy-saml-app" "chat-proxy-app")
    
    for app_name in "${apps[@]}"; do
        local full_name="$APP_PREFIX-$ENVIRONMENT-$app_name"
        
        # Get service principal and app registration IDs
        local sp_id=$(az ad sp list --display-name "$full_name" --query "[0].id" -o tsv)
        local app_id=$(az ad sp list --display-name "$full_name" --query "[0].appId" -o tsv)
        
        if [ ! -z "$sp_id" ] && [ "$sp_id" != "null" ]; then
            log_info "Deleting enterprise application: $full_name"
            
            # Delete service principal (enterprise application)
            az ad sp delete --id $sp_id
            
            # Delete app registration
            if [ ! -z "$app_id" ] && [ "$app_id" != "null" ]; then
                az ad app delete --id $app_id
            fi
            
            log_info "✓ Deleted enterprise application: $full_name"
        else
            log_warn "Enterprise application not found: $full_name"
        fi
    done
}

# Main function
main() {
    if [ $# -eq 0 ]; then
        # Default action: create enterprise applications
        create_enterprise_applications
    else
        case $1 in
            "create")
                create_enterprise_applications
                ;;
            "validate")
                validate_enterprise_apps
                ;;
            "list")
                list_enterprise_apps
                ;;
            "cleanup")
                cleanup_enterprise_apps
                ;;
            *)
                echo "Usage: $0 [create|validate|list|cleanup]"
                echo ""
                echo "Commands:"
                echo "  create   - Create enterprise applications (default)"
                echo "  validate - Validate existing enterprise applications"
                echo "  list     - List enterprise applications"
                echo "  cleanup  - Remove enterprise applications"
                exit 1
                ;;
        esac
    fi
}

# Check prerequisites
if [ ! -f "$ENVIRONMENT_FILE" ]; then
    log_error "Environment configuration file not found: $ENVIRONMENT_FILE"
    exit 1
fi

# Run main function
main "$@"