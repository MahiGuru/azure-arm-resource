#!/bin/bash

# Bot and Teams Configuration Helper Script
# This script helps configure bot credentials and Teams app settings

CONFIG_DIR="./config"
ENVIRONMENT_FILE="$CONFIG_DIR/environment.yaml"
TEAMS_DIR="./teams-manifest"
OUTPUT_FILE="bot-teams-config.txt"

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

# Function to get bot credentials
get_bot_credentials() {
    log_step "Retrieving bot credentials..."
    
    # Parse environment configuration
    eval $(parse_yaml $ENVIRONMENT_FILE "env_")
    
    RESOURCE_GROUP=$env_environment_resource_group
    APP_PREFIX=$env_environment_application_prefix
    ENVIRONMENT=$env_environment_name
    
    local bot_name="$APP_PREFIX-$ENVIRONMENT-mahi-teams-bot"
    local teams_app_name="$APP_PREFIX-$ENVIRONMENT-mahi-teams-app"
    
    # Get Teams app credentials
    local teams_app_id=$(az ad app list --display-name "$teams_app_name" --query "[0].appId" -o tsv)
    local teams_app_secret=$(az ad app credential list --id $teams_app_id --query "[0].secretText" -o tsv)
    
    if [ -z "$teams_app_id" ]; then
        log_error "Teams app not found: $teams_app_name"
        return 1
    fi
    
    # Get bot information
    local bot_info=$(az bot show --resource-group $RESOURCE_GROUP --name $bot_name --query "{id:id,endpoint:properties.endpoint}" -o json)
    
    if [ -z "$bot_info" ]; then
        log_error "Bot not found: $bot_name"
        return 1
    fi
    
    # Save credentials to configuration file
    cat > $OUTPUT_FILE << EOF
# Bot and Teams Application Configuration
# Generated on: $(date)

# Teams Application Credentials
TEAMS_APP_ID=$teams_app_id
TEAMS_APP_SECRET=$teams_app_secret

# Bot Configuration
BOT_NAME=$bot_name
BOT_RESOURCE_GROUP=$RESOURCE_GROUP
BOT_MESSAGING_ENDPOINT=https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net/api/messages
BOT_CALLING_ENDPOINT=https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net/api/calls

# Application Settings for Web App
# Add these to your web application configuration:
MicrosoftAppId=$teams_app_id
MicrosoftAppPassword=$teams_app_secret
BotFrameworkAppId=$teams_app_id
BotFrameworkAppSecret=$teams_app_secret

# Connection String for Bot Framework
BOT_CONNECTION_STRING="BotFramework:AppId=$teams_app_id;BotFramework:AppSecret=$teams_app_secret"

# Teams App URLs
TEAMS_APP_BASE_URL=https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net
TEAMS_APP_TAB_URL=https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net/teams/tab
TEAMS_APP_CONFIG_URL=https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net/teams/config

# Bot Framework Channels
TEAMS_CHANNEL_ENABLED=true
WEBCHAT_CHANNEL_ENABLED=true
EOF
    
    log_info "Bot credentials saved to $OUTPUT_FILE"
    
    # Display credentials
    echo ""
    echo "=== Bot and Teams Credentials ==="
    echo "Teams App ID: $teams_app_id"
    echo "Bot Name: $bot_name"
    echo "Messaging Endpoint: https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net/api/messages"
    echo ""
    echo "Add these environment variables to your web application:"
    echo "  MicrosoftAppId=$teams_app_id"
    echo "  MicrosoftAppPassword=[Generated Secret]"
    echo ""
}

# Function to create enhanced Teams manifest
create_enhanced_teams_manifest() {
    log_step "Creating enhanced Teams manifest..."
    
    eval $(parse_yaml $ENVIRONMENT_FILE "env_")
    
    APP_PREFIX=$env_environment_application_prefix
    ENVIRONMENT=$env_environment_name
    
    local teams_app_name="$APP_PREFIX-$ENVIRONMENT-mahi-teams-app"
    local teams_app_id=$(az ad app list --display-name "$teams_app_name" --query "[0].appId" -o tsv)
    
    if [ -z "$teams_app_id" ]; then
        log_error "Teams app not found"
        return 1
    fi
    
    mkdir -p $TEAMS_DIR
    
    # Create comprehensive manifest.json
    cat > $TEAMS_DIR/manifest.json << EOF
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
        "full": "Complete Teams application for Mahi with bot capabilities and custom tabs"
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
            "supportsFiles": true,
            "isNotificationOnly": false,
            "commandLists": [
                {
                    "scopes": [
                        "personal",
                        "team",
                        "groupchat"
                    ],
                    "commands": [
                        {
                            "title": "Help",
                            "description": "Get help with using the bot"
                        },
                        {
                            "title": "Status",
                            "description": "Check the bot status"
                        },
                        {
                            "title": "Settings",
                            "description": "Configure bot settings"
                        }
                    ]
                }
            ]
        }
    ],
    "staticTabs": [
        {
            "entityId": "home",
            "name": "Home",
            "contentUrl": "https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net/teams/tab",
            "websiteUrl": "https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net",
            "scopes": [
                "personal"
            ]
        }
    ],
    "configurableTabs": [
        {
            "configurationUrl": "https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net/teams/config",
            "canUpdateConfiguration": true,
            "scopes": [
                "team",
                "groupchat"
            ]
        }
    ],
    "permissions": [
        "identity",
        "messageTeamMembers"
    ],
    "validDomains": [
        "$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net",
        "token.botframework.com"
    ],
    "webApplicationInfo": {
        "id": "$teams_app_id",
        "resource": "https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net"
    }
}
EOF
    
    # Create app package information
    cat > $TEAMS_DIR/package-info.md << EOF
# Teams App Package Information

## Package Contents
- manifest.json: Teams application manifest
- color.png: Color icon (192x192px)
- outline.png: Outline icon (32x32px)

## Required Icons
Create the following icon files:

### Color Icon (color.png)
- Size: 192x192 pixels
- Format: PNG
- Background: Color background representing your brand
- Usage: Displayed in Teams app store and app bar

### Outline Icon (outline.png)
- Size: 32x32 pixels
- Format: PNG
- Background: Transparent
- Color: White outline only
- Usage: Used in Teams UI when app is active

## Packaging Instructions
1. Create the required icon files
2. Place all files (manifest.json, color.png, outline.png) in a ZIP archive
3. Upload the ZIP file to Teams Admin Center or use Teams Toolkit

## Deployment
1. Go to Teams Admin Center
2. Navigate to Teams apps > Manage apps
3. Click "Upload" and select your ZIP file
4. Configure app permissions and policies as needed
EOF
    
    log_info "Enhanced Teams manifest created at $TEAMS_DIR/manifest.json"
    log_info "Package instructions created at $TEAMS_DIR/package-info.md"
}

# Function to configure bot framework settings
configure_bot_framework() {
    log_step "Configuring Bot Framework settings..."
    
    eval $(parse_yaml $ENVIRONMENT_FILE "env_")
    
    RESOURCE_GROUP=$env_environment_resource_group
    APP_PREFIX=$env_environment_application_prefix
    ENVIRONMENT=$env_environment_name
    
    local bot_name="$APP_PREFIX-$ENVIRONMENT-mahi-teams-bot"
    
    # Update bot messaging endpoint
    local messaging_endpoint="https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net/api/messages"
    
    az bot update \
        --resource-group $RESOURCE_GROUP \
        --name $bot_name \
        --set properties.endpoint=$messaging_endpoint
    
    log_info "Bot messaging endpoint updated to: $messaging_endpoint"
    
    # Configure additional bot settings
    az bot update \
        --resource-group $RESOURCE_GROUP \
        --name $bot_name \
        --set properties.description="Teams bot for Mahi application"
    
    # Enable additional channels if needed
    log_info "Configuring bot channels..."
    
    # Configure Microsoft Teams channel with calling enabled
    az bot msteams create \
        --resource-group $RESOURCE_GROUP \
        --name $bot_name \
        --enable-calling true \
        --calling-web-hook "https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net/api/calls" \
        --enable-messaging true \
        --enable-media-cards true \
        --enable-video true \
        --enable-calling true
    
    log_info "Bot Framework configuration completed"
}

# Function to validate bot configuration
validate_bot_config() {
    log_step "Validating bot configuration..."
    
    eval $(parse_yaml $ENVIRONMENT_FILE "env_")
    
    RESOURCE_GROUP=$env_environment_resource_group
    APP_PREFIX=$env_environment_application_prefix
    ENVIRONMENT=$env_environment_name
    
    local bot_name="$APP_PREFIX-$ENVIRONMENT-mahi-teams-bot"
    local teams_app_name="$APP_PREFIX-$ENVIRONMENT-mahi-teams-app"
    
    # Check if bot exists
    local bot_exists=$(az bot show --resource-group $RESOURCE_GROUP --name $bot_name --query name -o tsv 2>/dev/null)
    
    if [ -z "$bot_exists" ]; then
        log_error "Bot not found: $bot_name"
        return 1
    fi
    
    log_info "✓ Bot exists: $bot_name"
    
    # Check if Teams app exists
    local teams_app_exists=$(az ad app list --display-name "$teams_app_name" --query "[0].appId" -o tsv)
    
    if [ -z "$teams_app_exists" ]; then
        log_error "Teams app not found: $teams_app_name"
        return 1
    fi
    
    log_info "✓ Teams app exists: $teams_app_name"
    
    # Check bot channels
    local channels=$(az bot show --resource-group $RESOURCE_GROUP --name $bot_name --query "properties.configuredChannels" -o tsv)
    
    if [[ $channels == *"MsTeamsChannel"* ]]; then
        log_info "✓ Microsoft Teams channel configured"
    else
        log_warn "⚠ Microsoft Teams channel not configured"
    fi
    
    if [[ $channels == *"WebChatChannel"* ]]; then
        log_info "✓ Web Chat channel configured"
    else
        log_warn "⚠ Web Chat channel not configured"
    fi
    
    # Check messaging endpoint
    local endpoint=$(az bot show --resource-group $RESOURCE_GROUP --name $bot_name --query "properties.endpoint" -o tsv)
    local expected_endpoint="https://$APP_PREFIX-$ENVIRONMENT-app3.azurewebsites.net/api/messages"
    
    if [ "$endpoint" == "$expected_endpoint" ]; then
        log_info "✓ Messaging endpoint configured correctly"
    else
        log_warn "⚠ Messaging endpoint mismatch"
        log_warn "  Expected: $expected_endpoint"
        log_warn "  Actual: $endpoint"
    fi
    
    log_info "Bot configuration validation completed"
}

# Function to create deployment checklist
create_deployment_checklist() {
    log_step "Creating deployment checklist..."
    
    cat > deployment-checklist.md << EOF
# Deployment Checklist

## Pre-deployment
- [ ] Azure CLI installed and configured
- [ ] Logged in to Azure with appropriate permissions
- [ ] Resource group exists or will be created
- [ ] Domain name configured for external URLs

## App Registrations
- [ ] Mahi Connector App created
- [ ] Mahi API Access created with exposed scopes
- [ ] Mahi Teams App created with Teams permissions
- [ ] All app registrations have proper redirect URIs
- [ ] API permissions configured and admin consent granted

## Bot Framework
- [ ] Bot registration created
- [ ] Bot linked to Teams app registration
- [ ] Microsoft Teams channel enabled
- [ ] Web Chat channel enabled (optional)
- [ ] Messaging endpoint configured
- [ ] Calling endpoint configured (for calling features)

## Teams Application
- [ ] Teams manifest created
- [ ] App icons created (color.png, outline.png)
- [ ] App package (ZIP) created
- [ ] App uploaded to Teams Admin Center
- [ ] App policies configured
- [ ] App permissions approved

## Enterprise Applications
- [ ] SAML enterprise app created
- [ ] Application Proxy configured (manual step)
- [ ] SAML SSO configured
- [ ] Proxy-only app created
- [ ] Internal/external URLs configured

## Web Application Configuration
- [ ] Environment variables configured:
  - [ ] MicrosoftAppId
  - [ ] MicrosoftAppPassword
  - [ ] BotFrameworkAppId
  - [ ] BotFrameworkAppSecret
- [ ] Bot messaging endpoint implemented
- [ ] Bot calling endpoint implemented (if needed)
- [ ] Teams tab pages implemented
- [ ] SAML authentication configured

## Testing
- [ ] Bot responds to messages in Teams
- [ ] Teams app can be installed
- [ ] Static tabs work correctly
- [ ] Configurable tabs work correctly
- [ ] SAML SSO works
- [ ] Application Proxy works
- [ ] API endpoints accessible with proper authentication

## Post-deployment
- [ ] Monitor bot performance
- [ ] Check logs for errors
- [ ] Validate all integrations
- [ ] Update documentation
- [ ] Train users on new features

## Troubleshooting
Common issues and solutions:
1. Bot not responding: Check messaging endpoint and credentials
2. Teams app not installing: Verify manifest and permissions
3. SAML issues: Check certificate and configuration
4. API access denied: Verify scopes and permissions
5. Application Proxy not working: Check connector group and URLs

## Support Resources
- Azure Bot Service documentation
- Teams app development documentation
- Application Proxy configuration guide
- SAML SSO setup guide
EOF
    
    log_info "Deployment checklist created: deployment-checklist.md"
}

# Main menu function
show_menu() {
    echo ""
    echo "==============================================="
    echo "Bot and Teams Configuration Helper"
    echo "==============================================="
    echo "1. Get bot credentials"
    echo "2. Create enhanced Teams manifest"
    echo "3. Configure Bot Framework settings"
    echo "4. Validate bot configuration"
    echo "5. Create deployment checklist"
    echo "6. Exit"
    echo ""
    read -p "Select an option (1-6): " choice
    
    case $choice in
        1) get_bot_credentials ;;
        2) create_enhanced_teams_manifest ;;
        3) configure_bot_framework ;;
        4) validate_bot_config ;;
        5) create_deployment_checklist ;;
        6) echo "Goodbye!"; exit 0 ;;
        *) echo "Invalid option. Please try again." ;;
    esac
}

# Main execution
main() {
    if [ $# -eq 0 ]; then
        # Interactive mode
        while true; do
            show_menu
        done
    else
        # Command line mode
        case $1 in
            "credentials") get_bot_credentials ;;
            "manifest") create_enhanced_teams_manifest ;;
            "configure") configure_bot_framework ;;
            "validate") validate_bot_config ;;
            "checklist") create_deployment_checklist ;;
            "all") 
                get_bot_credentials
                create_enhanced_teams_manifest
                configure_bot_framework
                validate_bot_config
                create_deployment_checklist
                ;;
            *) 
                echo "Usage: $0 [credentials|manifest|configure|validate|checklist|all]"
                exit 1
                ;;
        esac
    fi
}

# Run main function
main "$@"