#!/bin/bash

# Fix script for missing enterprise applications

# Parse environment configuration
CONFIG_DIR="./config"
ENVIRONMENT_FILE="$CONFIG_DIR/environment.yaml"

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

eval $(parse_yaml $ENVIRONMENT_FILE "env_")
APP_PREFIX=$env_environment_application_prefix
ENVIRONMENT=$env_environment_name

# Fix SAML enterprise application
fix_saml_app() {
    local app_name="$APP_PREFIX-$ENVIRONMENT-app-proxy-saml-app"
    local app_id=$(az ad app list --display-name "$app_name" --query "[0].appId" -o tsv)
    
    if [ ! -z "$app_id" ] && [ "$app_id" != "null" ]; then
        echo "Fixing SAML enterprise application: $app_name"
        
        # Create service principal
        local sp_id=$(az ad sp create --id $app_id --query objectId -o tsv)
        
        # Configure for SAML
        az ad sp update --id $sp_id --set preferredSingleSignOnMode=saml
        az ad sp update --id $sp_id --set tags='["Enterprise","SAML","SSO"]'
        
        echo "✓ SAML enterprise application fixed"
    else
        echo "✗ SAML app registration not found"
    fi
}

# Fix Application Proxy enterprise application
fix_proxy_app() {
    local app_name="$APP_PREFIX-$ENVIRONMENT-chat-proxy-app"
    local app_id=$(az ad app list --display-name "$app_name" --query "[0].appId" -o tsv)
    
    if [ ! -z "$app_id" ] && [ "$app_id" != "null" ]; then
        echo "Fixing Application Proxy enterprise application: $app_name"
        
        # Create service principal
        local sp_id=$(az ad sp create --id $app_id --query objectId -o tsv)
        
        # Configure for Application Proxy
        az ad sp update --id $sp_id --set preferredSingleSignOnMode=integrated
        az ad sp update --id $sp_id --set tags='["Enterprise","ApplicationProxy"]'
        
        echo "✓ Application Proxy enterprise application fixed"
    else
        echo "✗ Application Proxy app registration not found"
    fi
}

echo "Fixing enterprise applications..."
fix_saml_app
fix_proxy_app
echo "Done! Run validation script to verify."
