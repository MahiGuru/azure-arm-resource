#!/bin/bash

# Deployment Validation Script
# This script validates the configuration and environment before deployment

CONFIG_DIR="./config"
ENVIRONMENT_FILE="$CONFIG_DIR/environment.yaml"
APP_REG_FILE="$CONFIG_DIR/app-registrations.yaml"

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

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
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

# Validate system requirements
validate_system_requirements() {
    log_step "Validating system requirements..."
    
    local errors=0
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed"
        errors=$((errors + 1))
    else
        local az_version=$(az version --query '"azure-cli"' -o tsv)
        log_success "Azure CLI installed: $az_version"
    fi
    
    # Check if uuidgen is available
    if ! command -v uuidgen &> /dev/null; then
        log_error "uuidgen is not installed"
        log_error "Install with: sudo apt-get install uuid-runtime (Ubuntu/Debian) or sudo yum install util-linux (CentOS/RHEL)"
        errors=$((errors + 1))
    else
        log_success "uuidgen is available"
    fi
    
    # Check if sed is available
    if ! command -v sed &> /dev/null; then
        log_error "sed is not installed"
        errors=$((errors + 1))
    else
        log_success "sed is available"
    fi
    
    # Check if awk is available
    if ! command -v awk &> /dev/null; then
        log_error "awk is not installed"
        errors=$((errors + 1))
    else
        log_success "awk is available"
    fi
    
    return $errors
}

# Validate Azure login
validate_azure_login() {
    log_step "Validating Azure login..."
    
    local errors=0
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Run 'az login' first."
        errors=$((errors + 1))
    else
        local subscription=$(az account show --query name -o tsv)
        local subscription_id=$(az account show --query id -o tsv)
        local user=$(az account show --query user.name -o tsv)
        
        log_success "Logged in to Azure"
        log_info "  Subscription: $subscription"
        log_info "  Subscription ID: $subscription_id"
        log_info "  User: $user"
    fi
    
    return $errors
}

# Validate configuration files
validate_configuration_files() {
    log_step "Validating configuration files..."
    
    local errors=0
    
    # Check if environment file exists
    if [ ! -f "$ENVIRONMENT_FILE" ]; then
        log_error "Environment configuration file not found: $ENVIRONMENT_FILE"
        errors=$((errors + 1))
    else
        log_success "Environment file found: $ENVIRONMENT_FILE"
        
        # Try to parse the environment file
        if eval $(parse_yaml $ENVIRONMENT_FILE "env_") 2>/dev/null; then
            log_success "Environment file is valid YAML"
            log_info "  Environment: $env_environment_name"
            log_info "  Resource Group: $env_environment_resource_group"
            log_info "  Location: $env_environment_location"
            log_info "  App Prefix: $env_environment_application_prefix"
            log_info "  Tenant ID: $env_environment_tenant_id"
        else
            log_error "Environment file is not valid YAML"
            errors=$((errors + 1))
        fi
    fi
    
    # Check if app registration file exists
    if [ ! -f "$APP_REG_FILE" ]; then
        log_error "App registration configuration file not found: $APP_REG_FILE"
        errors=$((errors + 1))
    else
        log_success "App registration file found: $APP_REG_FILE"
        
        # Check if it's valid YAML
        if python3 -c "import yaml; yaml.safe_load(open('$APP_REG_FILE'))" 2>/dev/null; then
            log_success "App registration file is valid YAML"
        elif python -c "import yaml; yaml.safe_load(open('$APP_REG_FILE'))" 2>/dev/null; then
            log_success "App registration file is valid YAML"
        else
            log_warn "Cannot validate YAML syntax (python/python3 with yaml module not available)"
        fi
    fi
    
    return $errors
}

# Validate Azure permissions
validate_azure_permissions() {
    log_step "Validating Azure permissions..."
    
    local errors=0
    
    # Parse environment configuration
    eval $(parse_yaml $ENVIRONMENT_FILE "env_")
    
    local resource_group=$env_environment_resource_group
    local location=$env_environment_location
    
    # Check if user can create resource groups
    log_info "Checking resource group permissions..."
    if az group show --name $resource_group &> /dev/null; then
        log_success "Resource group exists: $resource_group"
    else
        log_info "Resource group does not exist, checking if it can be created..."
        
        # Try to create a test resource group (dry run)
        local test_rg="test-permissions-$(date +%s)"
        if az group create --name $test_rg --location $location --dry-run &> /dev/null; then
            log_success "Can create resource groups in $location"
        else
            log_error "Cannot create resource groups in $location"
            errors=$((errors + 1))
        fi
    fi
    
    # Check if user can create app registrations
    log_info "Checking app registration permissions..."
    if az ad app list --query "[0]" &> /dev/null; then
        log_success "Can read app registrations"
    else
        log_error "Cannot read app registrations"
        errors=$((errors + 1))
    fi
    
    # Check if user can create service principals
    log_info "Checking service principal permissions..."
    if az ad sp list --query "[0]" &> /dev/null; then
        log_success "Can read service principals"
    else
        log_error "Cannot read service principals"
        errors=$((errors + 1))
    fi
    
    return $errors
}

# Validate Azure extensions
validate_azure_extensions() {
    log_step "Validating Azure CLI extensions..."
    
    local errors=0
    
    # Check if botservice extension is available
    if az extension show --name botservice &> /dev/null; then
        log_success "botservice extension is installed"
    else
        log_warn "botservice extension is not installed"
        log_info "Will be installed automatically during deployment"
    fi
    
    return $errors
}

# Check for existing resources
check_existing_resources() {
    log_step "Checking for existing resources..."
    
    # Parse environment configuration
    eval $(parse_yaml $ENVIRONMENT_FILE "env_")
    
    local resource_group=$env_environment_resource_group
    local app_prefix=$env_environment_application_prefix
    local environment=$env_environment_name
    
    local conflicts=0
    
    # Check for existing app registrations
    local apps=("mahi-connector-app" "mahi-api-access" "mahi-teams-app")
    
    for app_name in "${apps[@]}"; do
        local full_name="$app_prefix-$environment-$app_name"
        local app_id=$(az ad app list --display-name "$full_name" --query "[0].appId" -o tsv)
        
        if [ ! -z "$app_id" ] && [ "$app_id" != "null" ]; then
            log_warn "Existing app registration found: $full_name ($app_id)"
            conflicts=$((conflicts + 1))
        fi
    done
    
    # Check for existing bot registration
    local bot_name="$app_prefix-$environment-mahi-teams-bot"
    if az bot show --resource-group $resource_group --name $bot_name &> /dev/null; then
        log_warn "Existing bot registration found: $bot_name"
        conflicts=$((conflicts + 1))
    fi
    
    # Check for existing resource group
    if az group show --name $resource_group &> /dev/null; then
        log_warn "Resource group already exists: $resource_group"
        log_info "  Existing resources in the group:"
        az resource list --resource-group $resource_group --query "[].{Name:name,Type:type}" -o table
        conflicts=$((conflicts + 1))
    fi
    
    if [ $conflicts -gt 0 ]; then
        log_warn "Found $conflicts existing resources that may conflict with deployment"
        log_warn "Consider running cleanup script or manually removing conflicting resources"
    else
        log_success "No conflicting resources found"
    fi
    
    return $conflicts
}

# Generate deployment preview
generate_deployment_preview() {
    log_step "Generating deployment preview..."
    
    # Parse environment configuration
    eval $(parse_yaml $ENVIRONMENT_FILE "env_")
    
    local resource_group=$env_environment_resource_group
    local location=$env_environment_location
    local app_prefix=$env_environment_application_prefix
    local environment=$env_environment_name
    
    cat << EOF

================================================
DEPLOYMENT PREVIEW
================================================

Environment Configuration:
  Name: $environment
  Resource Group: $resource_group
  Location: $location
  App Prefix: $app_prefix

Resources to be Created:
  
  App Registrations:
    ✓ $app_prefix-$environment-mahi-connector-app
    ✓ $app_prefix-$environment-mahi-api-access
    ✓ $app_prefix-$environment-mahi-teams-app
    ✓ $app_prefix-$environment-app-proxy-saml-app
    ✓ $app_prefix-$environment-chat-proxy-app
  
  Bot Registration:
    ✓ $app_prefix-$environment-mahi-teams-bot
  
  Teams App:
    ✓ Teams manifest and configuration
  
  Web App URLs:
    ✓ https://$app_prefix-$environment-app1.azurewebsites.net
    ✓ https://$app_prefix-$environment-app2.azurewebsites.net
    ✓ https://$app_prefix-$environment-app3.azurewebsites.net

================================================

EOF
}

# Main validation function
main() {
    echo "================================================="
    echo "Azure Deployment Validation Script"
    echo "================================================="
    echo ""
    
    local total_errors=0
    
    # Run all validations
    validate_system_requirements
    total_errors=$((total_errors + $?))
    
    validate_azure_login
    total_errors=$((total_errors + $?))
    
    validate_configuration_files
    total_errors=$((total_errors + $?))
    
    validate_azure_permissions
    total_errors=$((total_errors + $?))
    
    validate_azure_extensions
    total_errors=$((total_errors + $?))
    
    check_existing_resources
    local conflicts=$?
    
    # Generate deployment preview
    generate_deployment_preview
    
    # Summary
    echo "================================================="
    echo "VALIDATION SUMMARY"
    echo "================================================="
    
    if [ $total_errors -eq 0 ]; then
        log_success "All validations passed!"
        
        if [ $conflicts -gt 0 ]; then
            log_warn "Found $conflicts existing resources that may conflict"
            log_warn "Consider cleaning up before deployment"
        fi
        
        echo ""
        log_info "You can now run the deployment script:"
        log_info "  ./scripts/deploy.sh"
        echo ""
        
        exit 0
    else
        log_error "Validation failed with $total_errors errors"
        echo ""
        log_error "Please fix the errors above before running deployment"
        echo ""
        
        exit 1
    fi
}

# Run main function
main "$@"