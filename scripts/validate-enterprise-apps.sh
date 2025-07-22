#!/bin/bash

# Complete Enterprise Applications Validation Script
# This script validates all resources created by deploy.sh

CONFIG_DIR="./config"
ENVIRONMENT_FILE="$CONFIG_DIR/environment.yaml"
VALIDATION_OUTPUT="validation-report.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_detail() {
    echo -e "${PURPLE}[DETAIL]${NC} $1"
}

# Parse YAML function
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

# Initialize validation report
init_validation_report() {
    echo "Azure Resources Validation Report" > $VALIDATION_OUTPUT
    echo "Generated on: $(date)" >> $VALIDATION_OUTPUT
    echo "Environment: $ENVIRONMENT" >> $VALIDATION_OUTPUT
    echo "App Prefix: $APP_PREFIX" >> $VALIDATION_OUTPUT
    echo "=======================================" >> $VALIDATION_OUTPUT
    echo "" >> $VALIDATION_OUTPUT
}

# Function to check app registration
check_app_registration() {
    local app_name=$1
    local expected_type=$2
    local full_name="$APP_PREFIX-$ENVIRONMENT-$app_name"
    
    log_step "Validating app registration: $app_name"
    
    # Get app registration info
    local app_info=$(az ad app list --display-name "$full_name" --query "[0]" -o json 2>/dev/null)
    
    if [ "$app_info" == "null" ] || [ -z "$app_info" ]; then
        log_error "  ✗ App registration not found: $full_name"
        echo "❌ $full_name: NOT FOUND" >> $VALIDATION_OUTPUT
        return 1
    fi
    
    local app_id=$(echo "$app_info" | jq -r '.appId')
    local display_name=$(echo "$app_info" | jq -r '.displayName')
    local sign_in_audience=$(echo "$app_info" | jq -r '.signInAudience')
    local identifier_uris=$(echo "$app_info" | jq -r '.identifierUris[]?' 2>/dev/null | tr '\n' ' ')
    local redirect_uris=$(echo "$app_info" | jq -r '.web.redirectUris[]?' 2>/dev/null | tr '\n' ' ')
    local public_client_uris=$(echo "$app_info" | jq -r '.publicClient.redirectUris[]?' 2>/dev/null | tr '\n' ' ')
    
    log_success "  ✓ App registration found: $full_name"
    log_detail "    App ID: $app_id"
    log_detail "    Sign-in Audience: $sign_in_audience"
    
    if [ ! -z "$identifier_uris" ]; then
        log_detail "    Identifier URIs: $identifier_uris"
    fi
    
    if [ ! -z "$redirect_uris" ]; then
        log_detail "    Web Redirect URIs: $redirect_uris"
    fi
    
    if [ ! -z "$public_client_uris" ]; then
        log_detail "    Public Client URIs: $public_client_uris"
    fi
    
    # Check if service principal exists
    local sp_exists=$(az ad sp list --filter "appId eq '$app_id'" --query "[0].id" -o tsv)
    
    if [ ! -z "$sp_exists" ] && [ "$sp_exists" != "null" ]; then
        log_success "  ✓ Service principal exists"
        log_detail "    Service Principal ID: $sp_exists"
    else
        log_warn "  ⚠ Service principal not found"
    fi
    
    # Save to report
    cat >> $VALIDATION_OUTPUT << EOF
✅ $full_name: FOUND
   App ID: $app_id
   Service Principal: ${sp_exists:-"NOT FOUND"}
   Type: $expected_type
   Identifier URIs: ${identifier_uris:-"None"}
   Redirect URIs: ${redirect_uris:-"None"}${public_client_uris:+" (Public Client)"}

EOF
    
    return 0
}

# Function to check enterprise application
check_enterprise_application() {
    local app_name=$1
    local expected_sso_mode=$2
    local app_purpose=$3
    local full_name="$APP_PREFIX-$ENVIRONMENT-$app_name"
    
    log_step "Validating enterprise application: $app_name"
    
    # Get service principal info
    local sp_info=$(az ad sp list --display-name "$full_name" --query "[0]" -o json 2>/dev/null)
    
    if [ "$sp_info" == "null" ] || [ -z "$sp_info" ]; then
        log_error "  ✗ Enterprise application NOT FOUND: $full_name"
        log_error "    This means the app exists only as an app registration"
        log_error "    You need to create a service principal for this app"
        
        echo "❌ $full_name: ENTERPRISE APP NOT FOUND" >> $VALIDATION_OUTPUT
        echo "   Status: Only exists as app registration" >> $VALIDATION_OUTPUT
        echo "   Required: Create service principal" >> $VALIDATION_OUTPUT
        echo "" >> $VALIDATION_OUTPUT
        
        return 1
    fi
    
    local sp_id=$(echo "$sp_info" | jq -r '.id')
    local app_id=$(echo "$sp_info" | jq -r '.appId')
    local sso_mode=$(echo "$sp_info" | jq -r '.preferredSingleSignOnMode // "none"')
    local tags=$(echo "$sp_info" | jq -r '.tags[]?' 2>/dev/null | tr '\n' ' ')
    local homepage=$(echo "$sp_info" | jq -r '.homepage // "None"')
    
    log_success "  ✓ Enterprise application FOUND: $full_name"
    log_detail "    Service Principal ID: $sp_id"
    log_detail "    App ID: $app_id"
    log_detail "    SSO Mode: $sso_mode"
    log_detail "    Tags: ${tags:-"None"}"
    log_detail "    Homepage: $homepage"
    
    local validation_issues=0
    
    # Check SSO mode
    if [ "$sso_mode" == "$expected_sso_mode" ]; then
        log_success "  ✓ SSO mode is correctly configured ($expected_sso_mode)"
    else
        log_warn "  ⚠ SSO mode should be '$expected_sso_mode' but is '$sso_mode'"
        validation_issues=$((validation_issues + 1))
    fi
    
    # Check tags
    if [[ $tags == *"Enterprise"* ]]; then
        log_success "  ✓ Properly tagged as Enterprise application"
    else
        log_warn "  ⚠ Missing Enterprise tag"
        validation_issues=$((validation_issues + 1))
    fi
    
    # Check app registration settings
    local app_reg_info=$(az ad app show --id $app_id --query "{identifierUris:identifierUris,redirectUris:web.redirectUris}" -o json 2>/dev/null)
    local identifier_uris=$(echo "$app_reg_info" | jq -r '.identifierUris[]?' 2>/dev/null | tr '\n' ' ')
    local redirect_uris=$(echo "$app_reg_info" | jq -r '.redirectUris[]?' 2>/dev/null | tr '\n' ' ')
    
    if [ ! -z "$identifier_uris" ]; then
        log_detail "    Identifier URIs: $identifier_uris"
    fi
    
    if [ ! -z "$redirect_uris" ]; then
        log_detail "    Redirect URIs: $redirect_uris"
    fi
    
    # Save to report
    local status_icon="✅"
    if [ $validation_issues -gt 0 ]; then
        status_icon="⚠️"
    fi
    
    cat >> $VALIDATION_OUTPUT << EOF
$status_icon $full_name: ENTERPRISE APP FOUND
   Purpose: $app_purpose
   Service Principal ID: $sp_id
   App ID: $app_id
   SSO Mode: $sso_mode (expected: $expected_sso_mode)
   Tags: ${tags:-"None"}
   Identifier URIs: ${identifier_uris:-"None"}
   Redirect URIs: ${redirect_uris:-"None"}
   Issues: $validation_issues

EOF
    
    return $validation_issues
}

# Function to check bot registration
check_bot_registration() {
    local bot_name="$APP_PREFIX-$ENVIRONMENT-mahi-teams-bot"
    
    log_step "Validating bot registration: $bot_name"
    
    # Check if bot exists
    local bot_info=$(az bot show --resource-group $RESOURCE_GROUP --name $bot_name --query "{name:name,kind:kind,endpoint:properties.endpoint,appId:properties.appId}" -o json 2>/dev/null)
    
    if [ "$bot_info" == "null" ] || [ -z "$bot_info" ]; then
        log_error "  ✗ Bot registration not found: $bot_name"
        echo "❌ $bot_name: NOT FOUND" >> $VALIDATION_OUTPUT
        echo "" >> $VALIDATION_OUTPUT
        return 1
    fi
    
    local bot_kind=$(echo "$bot_info" | jq -r '.kind')
    local bot_endpoint=$(echo "$bot_info" | jq -r '.endpoint')
    local bot_app_id=$(echo "$bot_info" | jq -r '.appId')
    
    log_success "  ✓ Bot registration found: $bot_name"
    log_detail "    Bot Kind: $bot_kind"
    log_detail "    Messaging Endpoint: $bot_endpoint"
    log_detail "    App ID: $bot_app_id"
    
    # Check bot channels
    local channels=$(az bot show --resource-group $RESOURCE_GROUP --name $bot_name --query "properties.configuredChannels" -o tsv 2>/dev/null)
    
    if [ ! -z "$channels" ]; then
        log_detail "    Configured Channels: $channels"
    fi
    
    # Check if linked Teams app exists
    local teams_app_name="$APP_PREFIX-$ENVIRONMENT-mahi-teams-app"
    local teams_app_exists=$(az ad app list --display-name "$teams_app_name" --query "[0].appId" -o tsv)
    
    if [ ! -z "$teams_app_exists" ] && [ "$teams_app_exists" != "null" ]; then
        if [ "$bot_app_id" == "$teams_app_exists" ]; then
            log_success "  ✓ Bot correctly linked to Teams app"
        else
            log_warn "  ⚠ Bot app ID doesn't match Teams app ID"
        fi
    else
        log_warn "  ⚠ Teams app not found"
    fi
    
    # Save to report
    cat >> $VALIDATION_OUTPUT << EOF
✅ $bot_name: FOUND
   Kind: $bot_kind
   Messaging Endpoint: $bot_endpoint
   App ID: $bot_app_id
   Channels: ${channels:-"None"}
   Teams App Link: ${teams_app_exists:-"Not Found"}

EOF
    
    return 0
}

# Function to check Teams app manifest
check_teams_app_manifest() {
    local manifest_dir="./teams-manifest"
    
    log_step "Validating Teams app manifest"
    
    if [ ! -d "$manifest_dir" ]; then
        log_error "  ✗ Teams manifest directory not found: $manifest_dir"
        echo "❌ Teams Manifest: DIRECTORY NOT FOUND" >> $VALIDATION_OUTPUT
        return 1
    fi
    
    if [ ! -f "$manifest_dir/manifest.json" ]; then
        log_error "  ✗ Teams manifest file not found: $manifest_dir/manifest.json"
        echo "❌ Teams Manifest: FILE NOT FOUND" >> $VALIDATION_OUTPUT
        return 1
    fi
    
    log_success "  ✓ Teams manifest file found"
    
    # Parse manifest
    local manifest_content=$(cat "$manifest_dir/manifest.json")
    local manifest_version=$(echo "$manifest_content" | jq -r '.manifestVersion')
    local app_id=$(echo "$manifest_content" | jq -r '.id')
    local app_name=$(echo "$manifest_content" | jq -r '.name.short')
    
    log_detail "    Manifest Version: $manifest_version"
    log_detail "    App ID: $app_id"
    log_detail "    App Name: $app_name"
    
    # Check if icons exist
    local icons_missing=0
    
    if [ ! -f "$manifest_dir/color.png" ]; then
        log_warn "  ⚠ Color icon missing: $manifest_dir/color.png"
        icons_missing=$((icons_missing + 1))
    else
        log_success "  ✓ Color icon found"
    fi
    
    if [ ! -f "$manifest_dir/outline.png" ]; then
        log_warn "  ⚠ Outline icon missing: $manifest_dir/outline.png"
        icons_missing=$((icons_missing + 1))
    else
        log_success "  ✓ Outline icon found"
    fi
    
    # Save to report
    local status_icon="✅"
    if [ $icons_missing -gt 0 ]; then
        status_icon="⚠️"
    fi
    
    cat >> $VALIDATION_OUTPUT << EOF
$status_icon Teams App Manifest: FOUND
   Manifest Version: $manifest_version
   App ID: $app_id
   App Name: $app_name
   Color Icon: $([[ -f "$manifest_dir/color.png" ]] && echo "Found" || echo "Missing")
   Outline Icon: $([[ -f "$manifest_dir/outline.png" ]] && echo "Found" || echo "Missing")
   Missing Icons: $icons_missing

EOF
    
    return $icons_missing
}

# Function to show Azure Portal locations
show_portal_locations() {
    log_step "Azure Portal Locations"
    
    cat << EOF

=== WHERE TO FIND YOUR RESOURCES ===

1. **Enterprise Applications**:
   → Azure Portal: https://portal.azure.com
   → Azure Active Directory > Enterprise Applications
   → Look for:
     • $APP_PREFIX-$ENVIRONMENT-app-proxy-saml-app
     • $APP_PREFIX-$ENVIRONMENT-chat-proxy-app

2. **App Registrations**:
   → Azure Active Directory > App registrations
   → Look for:
     • $APP_PREFIX-$ENVIRONMENT-mahi-connector-app
     • $APP_PREFIX-$ENVIRONMENT-mahi-api-access
     • $APP_PREFIX-$ENVIRONMENT-mahi-teams-app

3. **Bot Registration**:
   → Azure Portal > All resources
   → Look for: $APP_PREFIX-$ENVIRONMENT-mahi-teams-bot

4. **Teams Admin Center**:
   → https://admin.teams.microsoft.com
   → Teams apps > Manage apps
   → Upload your Teams app package

EOF
}

# Function to provide configuration guidance
provide_configuration_guidance() {
    log_step "Configuration Guidance"
    
    cat << EOF

=== NEXT STEPS FOR MANUAL CONFIGURATION ===

1. **SAML Enterprise Application**:
   → Go to: Enterprise Applications > $APP_PREFIX-$ENVIRONMENT-app-proxy-saml-app
   → Configure: Single sign-on > SAML
   → Set:
     • Entity ID: api://{app-id} (should be set automatically)
     • ACS URL: https://saml-app-external.company.com/acs
     • Sign-on URL: https://saml-app-external.company.com
   → Download: Certificate (Base64)
   → Configure: User attributes & claims
   → Assign: Users and groups

2. **Application Proxy Enterprise Application**:
   → Go to: Enterprise Applications > $APP_PREFIX-$ENVIRONMENT-chat-proxy-app
   → Configure: Application proxy
   → Set:
     • Internal URL: http://internal-chat-app.company.com
     • External URL: https://chat-app-external.company.com
     • Pre-authentication: Azure Active Directory
   → Configure: Connector group
   → Assign: Users and groups

3. **Teams Application**:
   → Create icons: color.png (192x192) and outline.png (32x32)
   → Create ZIP: manifest.json + color.png + outline.png
   → Upload to: Teams Admin Center > Teams apps > Manage apps
   → Configure: App policies and permissions

4. **Bot Configuration**:
   → Verify: Messaging endpoint is accessible
   → Test: Bot responds to messages
   → Configure: Additional channels if needed

EOF
}

# Function to create fix script
create_fix_script() {
    log_step "Generating fix script for found issues..."
    
    cat > fix-validation-issues.sh << 'FIXSCRIPT'
#!/bin/bash

# Fix script for validation issues
# This script addresses common problems found during validation

CONFIG_DIR="./config"
ENVIRONMENT_FILE="$CONFIG_DIR/environment.yaml"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Parse YAML function
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

# Parse environment
eval $(parse_yaml $ENVIRONMENT_FILE "env_")
APP_PREFIX=$env_environment_application_prefix
ENVIRONMENT=$env_environment_name

# Fix missing service principals for enterprise apps
fix_enterprise_apps() {
    log_info "Fixing enterprise applications..."
    
    local apps=("app-proxy-saml-app" "chat-proxy-app")
    
    for app_name in "${apps[@]}"; do
        local full_name="$APP_PREFIX-$ENVIRONMENT-$app_name"
        
        # Get app registration ID
        local app_id=$(az ad app list --display-name "$full_name" --query "[0].appId" -o tsv)
        
        if [ -z "$app_id" ] || [ "$app_id" == "null" ]; then
            log_error "App registration not found: $full_name"
            continue
        fi
        
        # Check if service principal exists
        local sp_exists=$(az ad sp list --filter "appId eq '$app_id'" --query "[0].id" -o tsv)
        
        if [ -z "$sp_exists" ] || [ "$sp_exists" == "null" ]; then
            log_info "Creating service principal for: $full_name"
            
            # Create service principal
            local sp_id=$(az ad sp create --id $app_id --query objectId -o tsv)
            
            if [ ! -z "$sp_id" ]; then
                log_info "✓ Created service principal: $sp_id"
                
                # Configure based on app type
                if [[ $app_name == *"saml"* ]]; then
                    az ad sp update --id $sp_id --set preferredSingleSignOnMode=saml
                    az ad sp update --id $sp_id --set tags='["Enterprise","SAML","SSO"]'
                    
                    # Set identifier URI if not set
                    local identifier_uri=$(az ad app show --id $app_id --query identifierUris -o tsv)
                    if [ -z "$identifier_uri" ]; then
                        az ad app update --id $app_id --identifier-uris "api://$app_id"
                        log_info "✓ Set identifier URI: api://$app_id"
                    fi
                    
                    log_info "✓ Configured for SAML SSO"
                elif [[ $app_name == *"proxy"* ]]; then
                    az ad sp update --id $sp_id --set preferredSingleSignOnMode=integrated
                    az ad sp update --id $sp_id --set tags='["Enterprise","ApplicationProxy"]'
                    log_info "✓ Configured for Application Proxy"
                fi
            else
                log_error "Failed to create service principal for: $full_name"
            fi
        else
            log_info "Service principal already exists for: $full_name"
            
            # Update configuration if needed
            local sso_mode=$(az ad sp show --id $sp_exists --query preferredSingleSignOnMode -o tsv)
            
            if [[ $app_name == *"saml"* ]] && [ "$sso_mode" != "saml" ]; then
                az ad sp update --id $sp_exists --set preferredSingleSignOnMode=saml
                log_info "✓ Updated SSO mode to SAML"
            elif [[ $app_name == *"proxy"* ]] && [ "$sso_mode" != "integrated" ]; then
                az ad sp update --id $sp_exists --set preferredSingleSignOnMode=integrated
                log_info "✓ Updated SSO mode to integrated"
            fi
        fi
    done
}

# Fix Teams app icons
fix_teams_app_icons() {
    log_info "Checking Teams app icons..."
    
    local manifest_dir="./teams-manifest"
    
    if [ ! -d "$manifest_dir" ]; then
        log_error "Teams manifest directory not found: $manifest_dir"
        return 1
    fi
    
    if [ ! -f "$manifest_dir/color.png" ]; then
        log_warn "Color icon missing. Creating placeholder..."
        # Create a simple placeholder icon (you should replace this with actual icons)
        convert -size 192x192 xc:blue -pointsize 48 -fill white -gravity center -annotate +0+0 "APP" "$manifest_dir/color.png" 2>/dev/null || {
            log_warn "ImageMagick not available. Please create color.png manually (192x192px)"
        }
    fi
    
    if [ ! -f "$manifest_dir/outline.png" ]; then
        log_warn "Outline icon missing. Creating placeholder..."
        # Create a simple placeholder icon (you should replace this with actual icons)
        convert -size 32x32 xc:transparent -stroke white -strokewidth 2 -fill none -draw "rectangle 4,4 28,28" "$manifest_dir/outline.png" 2>/dev/null || {
            log_warn "ImageMagick not available. Please create outline.png manually (32x32px)"
        }
    fi
}

# Main function
main() {
    echo "================================================="
    echo "Validation Issues Fix Script"
    echo "================================================="
    echo ""
    
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_info "Starting fix process..."
    
    fix_enterprise_apps
    echo ""
    fix_teams_app_icons
    echo ""
    
    log_info "Fix process completed!"
    log_info "Run './validate_enterprise_apps.sh' again to verify fixes."
}

main "$@"
FIXSCRIPT
    
    chmod +x fix-validation-issues.sh
    log_info "Fix script created: fix-validation-issues.sh"
}

# Function to generate summary report
generate_summary_report() {
    local total_issues=$1
    
    log_step "Generating summary report..."
    
    cat >> $VALIDATION_OUTPUT << EOF

=== VALIDATION SUMMARY ===

Total Issues Found: $total_issues

EOF
    
    if [ $total_issues -eq 0 ]; then
        cat >> $VALIDATION_OUTPUT << EOF
🎉 ALL VALIDATIONS PASSED! 🎉

Your Azure resources are correctly configured:
✅ All app registrations created
✅ All enterprise applications configured
✅ Bot registration working
✅ Teams app manifest ready

Next Steps:
1. Configure SAML SSO in Azure Portal
2. Configure Application Proxy in Azure Portal
3. Upload Teams app to Teams Admin Center
4. Test all integrations

EOF
    else
        cat >> $VALIDATION_OUTPUT << EOF
⚠️  ISSUES FOUND - ACTION REQUIRED

Some resources need attention. Please:
1. Review the detailed findings above
2. Run the fix script: ./fix-validation-issues.sh
3. Complete manual configuration steps
4. Re-run validation to verify fixes

EOF
    fi
}

# Main validation function
main() {
    echo "================================================="
    echo "Azure Resources Validation Script"
    echo "================================================="
    echo ""
    
    # Check prerequisites
    if [ ! -f "$ENVIRONMENT_FILE" ]; then
        log_error "Environment configuration file not found: $ENVIRONMENT_FILE"
        exit 1
    fi
    
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it first."
        log_error "On Ubuntu/Debian: sudo apt-get install jq"
        log_error "On CentOS/RHEL: sudo yum install jq"
        exit 1
    fi
    
    # Parse environment
    eval $(parse_yaml $ENVIRONMENT_FILE "env_")
    APP_PREFIX=$env_environment_application_prefix
    ENVIRONMENT=$env_environment_name
    RESOURCE_GROUP=$env_environment_resource_group
    
    log_info "Environment: $ENVIRONMENT"
    log_info "App Prefix: $APP_PREFIX"
    log_info "Resource Group: $RESOURCE_GROUP"
    echo ""
    
    # Initialize validation report
    init_validation_report
    
    # Show portal locations
    show_portal_locations
    
    # Track validation issues
    local total_issues=0
    
    # Validate app registrations
    log_step "=== VALIDATING APP REGISTRATIONS ==="
    check_app_registration "mahi-connector-app" "Web Application" || total_issues=$((total_issues + 1))
    echo ""
    check_app_registration "mahi-api-access" "Web Application with API" || total_issues=$((total_issues + 1))
    echo ""
    check_app_registration "mahi-teams-app" "Single Page Application" || total_issues=$((total_issues + 1))
    echo ""
    
    # Validate enterprise applications
    log_step "=== VALIDATING ENTERPRISE APPLICATIONS ==="
    check_enterprise_application "app-proxy-saml-app" "saml" "SAML SSO"
    total_issues=$((total_issues + $?))
    echo ""
    check_enterprise_application "chat-proxy-app" "integrated" "Application Proxy"
    total_issues=$((total_issues + $?))
    echo ""
    
    # Validate bot registration
    log_step "=== VALIDATING BOT REGISTRATION ==="
    check_bot_registration || total_issues=$((total_issues + 1))
    echo ""
    
    # Validate Teams app manifest
    log_step "=== VALIDATING TEAMS APP MANIFEST ==="
    check_teams_app_manifest
    total_issues=$((total_issues + $?))
    echo ""
    
    # Generate summary report
    generate_summary_report $total_issues
    
    # Show results
    echo "================================================="
    echo "VALIDATION SUMMARY"
    echo "================================================="
    
    if [ $total_issues -eq 0 ]; then
        log_success "🎉 ALL VALIDATIONS PASSED! 🎉"
        echo ""
        log_info "Your Azure resources are correctly configured!"
        echo ""
        provide_configuration_guidance
    else
        log_error "⚠️  FOUND $total_issues ISSUES THAT NEED ATTENTION"
        echo ""
        log_info "Issues found:"
        cat $VALIDATION_OUTPUT | grep -E "❌|⚠️"
        echo ""
        
        # Create fix script
        create_fix_script
        
        echo ""
        log_info "To fix the issues:"
        log_info "1. Run: ./fix-validation-issues.sh"
        log_info "2. Complete manual configuration steps"
        log_info "3. Re-run: ./validate_enterprise_apps.sh"
        echo ""
        
        provide_configuration_guidance
    fi
    
    echo ""
    log_info "Detailed validation report saved to: $VALIDATION_OUTPUT"
}

# Run main function
main "$@"