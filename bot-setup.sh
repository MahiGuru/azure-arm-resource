#!/bin/bash

# Bot Service Setup Script - Bash Version
# This script handles certificate generation, certificate store import (Windows only), and bot service setup
# Works on macOS, Linux, and Windows with WSL/Git Bash

set -e

ENV_FILE=".env"
BOT_HOME_PATH=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        --bot-home-path)
            BOT_HOME_PATH="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--env-file FILE] [--bot-home-path PATH]"
            echo "  --env-file FILE        Environment file to load (default: .env)"
            echo "  --bot-home-path PATH   BOT_HOME directory path"
            exit 0
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
done

# Function to load environment variables from .env file
load_env_file() {
    local file_path="$1"
    
    if [[ -f "$file_path" ]]; then
        echo "Loading environment variables from $file_path"
        # Export variables while ignoring comments and empty lines
        export $(grep -v '^#' "$file_path" | grep -v '^$' | xargs)
        echo "Environment variables loaded"
        
        # Debug: Show loaded variables
        echo "Loaded variables:"
        grep -v '^#' "$file_path" | grep -v '^$' | while read line; do
            echo "  $line"
        done
    else
        echo "Error: Environment file $file_path not found!"
        exit 1
    fi
}

# Function to detect operating system
get_operating_system() {
    case "$OSTYPE" in
        darwin*)
            echo "macOS"
            ;;
        linux*)
            echo "Linux"
            ;;
        msys*|cygwin*|mingw*)
            echo "Windows"
            ;;
        *)
            echo "Unknown"
            ;;
    esac
}

# Function to set BOT_HOME environment variable
set_bot_home() {
    local path="$1"
    
    if [[ -z "$path" ]]; then
        read -p "Please enter the BOT_HOME path: " path
    fi
    
    if [[ ! -d "$path" ]]; then
        mkdir -p "$path"
        echo "Created directory: $path"
    fi
    
    export BOT_HOME="$path"
    echo "BOT_HOME set to: $path"
    
    cd "$path"
}

# Function to check if OpenSSL is available
test_openssl() {
    if command -v openssl >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to generate OpenSSL private key
generate_private_key() {
    if ! test_openssl; then
        echo "Error: OpenSSL is not installed or not in PATH. Please install OpenSSL:"
        echo "macOS: brew install openssl"
        echo "Linux: apt-get install openssl or yum install openssl"
        echo "Windows: Download from https://slproweb.com/products/Win32OpenSSL.html"
        exit 1
    fi
    
    echo "Generating private key..."
    
    if openssl genrsa -out bot.key 2048; then
        echo "Private key generated successfully: bot.key"
    else
        echo "Error: Failed to generate private key"
        exit 1
    fi
}

# Function to generate Certificate Signing Request
generate_csr() {
    echo "Generating Certificate Signing Request..."
    
    # Check required environment variables
    if [[ -z "$VM_NAME" || -z "$DOMAIN_NAME" || -z "$CITY_NAME" || -z "$STATE_NAME" || -z "$COUNTRY_NAME" ]]; then
        echo "Error: Missing required environment variables. Please check your .env file."
        echo "Required variables: VM_NAME, DOMAIN_NAME, CITY_NAME, STATE_NAME, COUNTRY_NAME"
        exit 1
    fi
    
    # Set defaults for optional variables
    ORGANIZATION=${ORGANIZATION:-"sail"}
    ORG_UNIT=${ORG_UNIT:-"magnolia"}
    
    local subject="/C=$COUNTRY_NAME/ST=$STATE_NAME/L=$CITY_NAME/O=$ORGANIZATION/OU=$ORG_UNIT/CN=$VM_NAME/emailAddress=$VM_NAME@$DOMAIN_NAME"
    
    if openssl req -new -key bot.key -out bot.csr -subj "$subject"; then
        echo "CSR generated successfully: bot.csr"
        echo "Subject: $subject"
    else
        echo "Error: Failed to generate CSR"
        exit 1
    fi
}

# Function to generate self-signed certificate
generate_certificate() {
    echo "Generating self-signed certificate..."
    
    if openssl x509 -req -days 365 -in bot.csr -signkey bot.key -out bot.cert; then
        echo "Certificate generated successfully: bot.cert"
    else
        echo "Error: Failed to generate certificate"
        exit 1
    fi
}

# Function to import certificate to certificate store
import_certificate_to_store() {
    local os=$(get_operating_system)
    
    case "$os" in
        "Windows")
            echo "Platform: Windows - Certificate store import would be handled by PowerShell version"
            echo "For manual import:"
            echo "1. Run 'certmgr.msc' as Administrator"
            echo "2. Navigate to Trusted Root Certification Authorities > Certificates"
            echo "3. Right-click > All Tasks > Import"
            echo "4. Select bot.cert file"
            ;;
        "macOS")
            echo "Platform: macOS - Certificate store import not supported in bash version"
            echo "To manually add certificate to Keychain:"
            echo "1. Double-click bot.cert file"
            echo "2. Choose 'System' keychain and click 'Add'"
            echo "3. In Keychain Access, find the certificate and set trust to 'Always Trust'"
            ;;
        *)
            echo "Platform: $os - Certificate store import not supported"
            echo "Certificate generated at: $(pwd)/bot.cert"
            echo "Please manually import to your system's certificate store if needed"
            ;;
    esac
}

# Function to create secret source JSON file
create_secret_source_file() {
    local secret_type="$1"
    local file_path="$2"
    
    if [[ ! -f "$file_path" ]]; then
        echo "Error: File not found: $file_path" >&2
        return 1
    fi
    
    local secret_content=$(cat "$file_path")
    local output_file="secretSource_$secret_type.json"
    
    # Create JSON using jq if available, otherwise use simple string manipulation
    if command -v jq >/dev/null 2>&1; then
        jq -n --arg type "$secret_type" --arg value "$secret_content" '{secretType: $type, secretValue: $value}' > "$output_file"
    else
        # Escape quotes and newlines for JSON
        secret_content=$(echo "$secret_content" | sed 's/"/\\"/g' | sed 's/$/\\n/' | tr -d '\n' | sed 's/\\n$//')
        echo "{\"secretType\": \"$secret_type\", \"secretValue\": \"$secret_content\"}" > "$output_file"
    fi
    
    echo "Created $output_file" >&2
    echo "$output_file"
}

# Function to encrypt secrets via API
encrypt_secrets() {
    if [[ -z "$BOT_ENDPOINT" ]]; then
        echo "Error: BOT_ENDPOINT not found in environment variables"
        exit 1
    fi
    
    echo "Encrypting secrets via API endpoint: $BOT_ENDPOINT"
    
    # Check if curl is available
    if ! command -v curl >/dev/null 2>&1; then
        echo "Error: curl is not installed. Please install curl to encrypt secrets."
        exit 1
    fi
    
    # Encrypt app secret
    if [[ -n "$APP_SECRET" ]]; then
        echo "Encrypting app_secret..."
        if command -v jq >/dev/null 2>&1; then
            jq -n --arg value "$APP_SECRET" '{secretType: "app_secret", secretValue: $value}' > secretSource_app_secret.json
        else
            echo "{\"secretType\": \"app_secret\", \"secretValue\": \"$APP_SECRET\"}" > secretSource_app_secret.json
        fi
        
        echo "Making API call for app_secret..."
        curl --insecure --request POST -H "Content-Type:application/json" --data @secretSource_app_secret.json "$BOT_ENDPOINT/util/encrypt" || echo "API call failed for app_secret"
    fi
    
    # Encrypt bot.key
    if [[ -f "bot.key" ]]; then
        echo "Encrypting bot.key..."
        local key_file=$(create_secret_source_file "bot_key" "bot.key")
        echo "Making API call for bot.key..."
        curl --insecure --request POST -H "Content-Type:application/json" --data @"$key_file" "$BOT_ENDPOINT/util/encrypt" || echo "API call failed for bot.key"
    fi
    
    # Encrypt bot.cert
    if [[ -f "bot.cert" ]]; then
        echo "Encrypting bot.cert..."
        local cert_file=$(create_secret_source_file "bot_cert" "bot.cert")
        echo "Making API call for bot.cert..."
        curl --insecure --request POST -H "Content-Type:application/json" --data @"$cert_file" "$BOT_ENDPOINT/util/encrypt" || echo "API call failed for bot.cert"
    fi
}

# Global variable to store bot service PID
BOT_SERVICE_PID=""

# Function to start bot service
start_bot_service() {
    local os=$(get_operating_system)
    
    if [[ -z "$BOT_SERVICE_EXE" ]]; then
        if [[ "$os" == "Windows" ]]; then
            read -p "Please enter the path to bot_service.exe: " BOT_SERVICE_EXE
        else
            read -p "Please enter the path to bot service executable: " BOT_SERVICE_EXE
        fi
    fi
    
    if [[ -f "$BOT_SERVICE_EXE" ]]; then
        echo "Starting bot service: $BOT_SERVICE_EXE"
        
        # Make executable if on Unix systems
        if [[ "$os" != "Windows" ]]; then
            chmod +x "$BOT_SERVICE_EXE"
        fi
        
        # Start the service in background
        "$BOT_SERVICE_EXE" &
        BOT_SERVICE_PID=$!
        echo "Bot service started (PID: $BOT_SERVICE_PID)"
        
        # Wait a moment for the service to start
        sleep 3
    else
        echo "Warning: Bot service executable not found: $BOT_SERVICE_EXE"
        echo "Please ensure the bot service executable exists and is accessible"
    fi
}

# Function to stop bot service
stop_bot_service() {
    if [[ -n "$BOT_SERVICE_PID" ]]; then
        echo "Stopping bot service (PID: $BOT_SERVICE_PID)..."
        kill "$BOT_SERVICE_PID" 2>/dev/null || echo "Bot service may have already stopped"
        sleep 2
        BOT_SERVICE_PID=""
        echo "Bot service stopped"
    else
        echo "No bot service PID found, attempting to find and stop..."
        # Try to find the process by name
        pkill -f "$BOT_SERVICE_EXE" 2>/dev/null || echo "No bot service process found to stop"
    fi
}

# Function to restart bot service
restart_bot_service() {
    echo "Restarting bot service..."
    stop_bot_service
    sleep 2
    start_bot_service
}

# Function to retrieve endpoint content
get_endpoint_content() {
    local endpoint="$1"
    local description="$2"
    
    if [[ -z "$BOT_ENDPOINT" ]]; then
        echo "Error: BOT_ENDPOINT not configured"
        return 1
    fi
    
    local full_url="$BOT_ENDPOINT$endpoint"
    echo "Retrieving $description from: $full_url"
    
    # Try to get the endpoint content
    local response=$(curl --insecure --silent --show-error --max-time 10 "$full_url" 2>/dev/null)
    local curl_exit_code=$?
    
    if [[ $curl_exit_code -eq 0 && -n "$response" ]]; then
        echo "=== $description Content ==="
        echo "$response"
        echo "========================="
        
        # Save to file for easy copying
        local filename=$(echo "$endpoint" | sed 's/\//_/g' | sed 's/^_//')
        echo "$response" > "${filename}_content.txt"
        echo "Content saved to: ${filename}_content.txt"
        echo ""
    else
        echo "Failed to retrieve $description (curl exit code: $curl_exit_code)"
        echo "Please ensure:"
        echo "1. Bot service is running and accessible"
        echo "2. BOT_ENDPOINT is correct: $BOT_ENDPOINT"
        echo "3. Network connectivity is available"
        echo ""
    fi
}

# Main execution
main() {
    local os=$(get_operating_system)
    echo "=== Bot Service Setup Script ==="
    echo "Platform detected: $os"
    echo "Starting bot setup process..."
    
    # Load environment variables
    load_env_file "$ENV_FILE"
    
    # Set BOT_HOME
    set_bot_home "$BOT_HOME_PATH"
    
    # Generate certificates
    generate_private_key
    generate_csr
    generate_certificate
    
    # Import certificate to certificate store
    import_certificate_to_store
    
    # Start bot service initially
    start_bot_service
    
    # Encrypt secrets
    encrypt_secrets
    
    # Restart bot service after encryption
    echo "Restarting bot service after certificate encryption..."
    restart_bot_service
    
    # Retrieve endpoint content
    echo "Retrieving bot service endpoints..."
    get_endpoint_content "/notify" "Notify Endpoint"
    get_endpoint_content "/messages" "Messages Endpoint"
    
    echo "=== Setup completed successfully! ==="
    echo "Bot service endpoints have been retrieved and saved to text files."
    echo "Check the following files for endpoint content:"
    echo "- notify_content.txt"
    echo "- messages_content.txt"
}

# Run main function with error handling
if ! main "$@"; then
    echo "Setup failed!"
    exit 1
fi