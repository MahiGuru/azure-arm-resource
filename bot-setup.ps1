# Bot Service Setup Script
# This script handles certificate generation, certificate store import (Windows only), and bot service setup
# Works on Windows PowerShell and macOS/Linux with PowerShell Core

param(
    [string]$EnvFile = ".env",
    [string]$BotHomePath = $null
)

# Function to load environment variables from .env file
function Load-EnvFile {
    param([string]$FilePath)
    
    if (Test-Path $FilePath) {
        Write-Host "Loading environment variables from $FilePath" -ForegroundColor Green
        Get-Content $FilePath | ForEach-Object {
            if ($_ -match '^([^#][^=]*?)=(.*)$') {
                $name = $matches[1].Trim()
                $value = $matches[2].Trim()
                [Environment]::SetEnvironmentVariable($name, $value, "Process")
                Write-Host "Set $name" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Error "Environment file $FilePath not found!"
        exit 1
    }
}

# Function to set BOT_HOME environment variable
function Set-BotHome {
    param([string]$Path)
    
    if (-not $Path) {
        $Path = Read-Host "Please enter the BOT_HOME path"
    }
    
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Host "Created directory: $Path" -ForegroundColor Green
    }
    
    [Environment]::SetEnvironmentVariable("BOT_HOME", $Path, "Process")
    [Environment]::SetEnvironmentVariable("BOT_HOME", $Path, "User")
    Write-Host "BOT_HOME set to: $Path" -ForegroundColor Green
    
    Set-Location $Path
}

# Function to check if OpenSSL is available
function Test-OpenSSL {
    try {
        $null = Get-Command openssl -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# Function to generate OpenSSL private key
function Generate-PrivateKey {
    if (-not (Test-OpenSSL)) {
        Write-Error "OpenSSL is not installed or not in PATH. Please install OpenSSL:"
        Write-Host "Windows: Download from https://slproweb.com/products/Win32OpenSSL.html" -ForegroundColor Cyan
        Write-Host "macOS: brew install openssl" -ForegroundColor Cyan
        Write-Host "Linux: apt-get install openssl or yum install openssl" -ForegroundColor Cyan
        exit 1
    }
    
    Write-Host "Generating private key..." -ForegroundColor Yellow
    
    $keyCommand = "openssl genrsa -out bot.key 2048"
    Invoke-Expression $keyCommand
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Private key generated successfully: bot.key" -ForegroundColor Green
    } else {
        Write-Error "Failed to generate private key"
        exit 1
    }
}

# Function to generate Certificate Signing Request
function Generate-CSR {
    Write-Host "Generating Certificate Signing Request..." -ForegroundColor Yellow
    
    $vmName = [Environment]::GetEnvironmentVariable("VM_NAME")
    $domainName = [Environment]::GetEnvironmentVariable("DOMAIN_NAME")
    $organization = [Environment]::GetEnvironmentVariable("ORGANIZATION") ?? "sail"
    $orgUnit = [Environment]::GetEnvironmentVariable("ORG_UNIT") ?? "magnolia"
    $city = [Environment]::GetEnvironmentVariable("CITY_NAME")
    $state = [Environment]::GetEnvironmentVariable("STATE_NAME")
    $country = [Environment]::GetEnvironmentVariable("COUNTRY_NAME")
    
    if (-not $vmName -or -not $domainName -or -not $city -or -not $state -or -not $country) {
        Write-Error "Missing required environment variables. Please check your .env file."
        Write-Host "Required variables: VM_NAME, DOMAIN_NAME, CITY_NAME, STATE_NAME, COUNTRY_NAME" -ForegroundColor Red
        exit 1
    }
    
    $subject = "/C=$country/ST=$state/L=$city/O=$organization/OU=$orgUnit/CN=$vmName/emailAddress=$vmName@$domainName"
    $csrCommand = "openssl req -new -key bot.key -out bot.csr -subj `"$subject`""
    
    Invoke-Expression $csrCommand
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "CSR generated successfully: bot.csr" -ForegroundColor Green
        Write-Host "Subject: $subject" -ForegroundColor Cyan
    } else {
        Write-Error "Failed to generate CSR"
        exit 1
    }
}

# Function to generate self-signed certificate
function Generate-Certificate {
    Write-Host "Generating self-signed certificate..." -ForegroundColor Yellow
    
    $certCommand = "openssl x509 -req -days 365 -in bot.csr -signkey bot.key -out bot.cert"
    Invoke-Expression $certCommand
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Certificate generated successfully: bot.cert" -ForegroundColor Green
    } else {
        Write-Error "Failed to generate certificate"
        exit 1
    }
}

# Function to detect operating system
function Get-OperatingSystem {
    if ($IsWindows -or ($env:OS -eq "Windows_NT")) {
        return "Windows"
    } elseif ($IsMacOS -or ($env:OSTYPE -match "darwin")) {
        return "macOS"
    } elseif ($IsLinux -or ($env:OSTYPE -match "linux")) {
        return "Linux"
    } else {
        return "Unknown"
    }
}

# Function to import certificate to certificate store (Windows only)
function Import-CertificateToStore {
    $os = Get-OperatingSystem
    
    if ($os -eq "Windows") {
        Write-Host "Importing certificate to Trusted Root Certification Authorities..." -ForegroundColor Yellow
        
        try {
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("bot.cert")
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
            $store.Open("ReadWrite")
            $store.Add($cert)
            $store.Close()
            
            Write-Host "Certificate imported successfully to Trusted Root CA store" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to import certificate automatically. Please manually import bot.cert:"
            Write-Host "1. Run 'certmgr.msc' as Administrator" -ForegroundColor Cyan
            Write-Host "2. Navigate to Trusted Root Certification Authorities > Certificates" -ForegroundColor Cyan
            Write-Host "3. Right-click > All Tasks > Import" -ForegroundColor Cyan
            Write-Host "4. Select bot.cert file" -ForegroundColor Cyan
        }
    } elseif ($os -eq "macOS") {
        Write-Host "Platform: macOS - Certificate store import not supported" -ForegroundColor Yellow
        Write-Host "To manually add certificate to Keychain:" -ForegroundColor Cyan
        Write-Host "1. Double-click bot.cert file" -ForegroundColor Cyan
        Write-Host "2. Choose 'System' keychain and click 'Add'" -ForegroundColor Cyan
        Write-Host "3. In Keychain Access, find the certificate and set trust to 'Always Trust'" -ForegroundColor Cyan
    } else {
        Write-Host "Platform: $os - Certificate store import not supported" -ForegroundColor Yellow
        Write-Host "Certificate generated at: $(Get-Location)/bot.cert" -ForegroundColor Cyan
        Write-Host "Please manually import to your system's certificate store if needed" -ForegroundColor Cyan
    }
}

# Function to create secret source JSON file
function Create-SecretSourceFile {
    param([string]$SecretType, [string]$FilePath)
    
    $secretContent = Get-Content $FilePath -Raw
    $jsonContent = @{
        secretType = $SecretType
        secretValue = $secretContent
    } | ConvertTo-Json -Depth 10
    
    $outputFile = "secretSource_$SecretType.json"
    $jsonContent | Out-File -FilePath $outputFile -Encoding UTF8
    Write-Host "Created $outputFile" -ForegroundColor Green
    return $outputFile
}

# Function to encrypt secrets via API
function Encrypt-Secrets {
    $botEndpoint = [Environment]::GetEnvironmentVariable("BOT_ENDPOINT")
    $appSecret = [Environment]::GetEnvironmentVariable("APP_SECRET")
    
    if (-not $botEndpoint) {
        Write-Error "BOT_ENDPOINT not found in environment variables"
        exit 1
    }
    
    Write-Host "Encrypting secrets via API endpoint: $botEndpoint" -ForegroundColor Yellow
    
    # Encrypt app secret
    if ($appSecret) {
        $appSecretJson = @{ secretType = "app_secret"; secretValue = $appSecret } | ConvertTo-Json
        $appSecretJson | Out-File -FilePath "secretSource_app_secret.json" -Encoding UTF8
        
        $curlCommand = "curl --insecure --request POST -H `"Content-Type:application/json`" --data @secretSource_app_secret.json `"$botEndpoint/util/encrypt`""
        Write-Host "Encrypting app_secret..." -ForegroundColor Cyan
        Invoke-Expression $curlCommand
    }
    
    # Encrypt bot.key
    if (Test-Path "bot.key") {
        $keyFile = Create-SecretSourceFile -SecretType "bot_key" -FilePath "bot.key"
        $curlCommand = "curl --insecure --request POST -H `"Content-Type:application/json`" --data @$keyFile `"$botEndpoint/util/encrypt`""
        Write-Host "Encrypting bot.key..." -ForegroundColor Cyan
        Invoke-Expression $curlCommand
    }
    
    # Encrypt bot.cert
    if (Test-Path "bot.cert") {
        $certFile = Create-SecretSourceFile -SecretType "bot_cert" -FilePath "bot.cert"
        $curlCommand = "curl --insecure --request POST -H `"Content-Type:application/json`" --data @$certFile `"$botEndpoint/util/encrypt`""
        Write-Host "Encrypting bot.cert..." -ForegroundColor Cyan
        Invoke-Expression $curlCommand
    }
}

# Global variable to store bot service process
$script:BotServiceProcess = $null

# Function to start bot service
function Start-BotService {
    $botServiceExe = [Environment]::GetEnvironmentVariable("BOT_SERVICE_EXE")
    $os = Get-OperatingSystem
    
    if (-not $botServiceExe) {
        if ($os -eq "Windows") {
            $botServiceExe = Read-Host "Please enter the path to bot_service.exe"
        } else {
            $botServiceExe = Read-Host "Please enter the path to bot service executable"
        }
    }
    
    if (Test-Path $botServiceExe) {
        Write-Host "Starting bot service: $botServiceExe" -ForegroundColor Yellow
        
        if ($os -eq "Windows") {
            $script:BotServiceProcess = Start-Process $botServiceExe -NoNewWindow -PassThru
        } else {
            # For macOS/Linux, make executable and run
            chmod +x $botServiceExe 2>/dev/null
            $script:BotServiceProcess = Start-Process $botServiceExe -NoNewWindow -PassThru
        }
        
        Write-Host "Bot service started (PID: $($script:BotServiceProcess.Id))" -ForegroundColor Green
        
        # Wait a moment for the service to start
        Start-Sleep 3
    } else {
        Write-Warning "Bot service executable not found: $botServiceExe"
        Write-Host "Please ensure the bot service executable exists and is accessible" -ForegroundColor Cyan
    }
}

# Function to stop bot service
function Stop-BotService {
    if ($script:BotServiceProcess -and -not $script:BotServiceProcess.HasExited) {
        Write-Host "Stopping bot service (PID: $($script:BotServiceProcess.Id))..." -ForegroundColor Yellow
        try {
            $script:BotServiceProcess.Kill()
            $script:BotServiceProcess.WaitForExit(5000)
            Write-Host "Bot service stopped" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to stop bot service gracefully"
        }
    } else {
        Write-Host "No bot service process found, attempting to find and stop..." -ForegroundColor Yellow
        # Try to find the process by name
        $botServiceExe = [Environment]::GetEnvironmentVariable("BOT_SERVICE_EXE")
        if ($botServiceExe) {
            $processName = [System.IO.Path]::GetFileNameWithoutExtension($botServiceExe)
            Get-Process $processName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }
    $script:BotServiceProcess = $null
}

# Function to restart bot service
function Restart-BotService {
    Write-Host "Restarting bot service..." -ForegroundColor Yellow
    Stop-BotService
    Start-Sleep 2
    Start-BotService
}

# Function to retrieve endpoint content
function Get-EndpointContent {
    param(
        [string]$Endpoint,
        [string]$Description
    )
    
    $botEndpoint = [Environment]::GetEnvironmentVariable("BOT_ENDPOINT")
    
    if (-not $botEndpoint) {
        Write-Error "BOT_ENDPOINT not configured"
        return
    }
    
    $fullUrl = "$botEndpoint$Endpoint"
    Write-Host "Retrieving $Description from: $fullUrl" -ForegroundColor Cyan
    
    try {
        $response = Invoke-RestMethod -Uri $fullUrl -Method Get -TimeoutSec 10 -SkipCertificateCheck -ErrorAction Stop
        
        Write-Host "=== $Description Content ===" -ForegroundColor Green
        Write-Host ($response | ConvertTo-Json -Depth 10)
        Write-Host "=========================" -ForegroundColor Green
        
        # Save to file for easy copying
        $filename = $Endpoint -replace '/', '_' -replace '^_', ''
        $outputFile = "${filename}_content.txt"
        $response | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputFile -Encoding UTF8
        Write-Host "Content saved to: $outputFile" -ForegroundColor Yellow
        Write-Host ""
        
    } catch {
        Write-Warning "Failed to retrieve $Description : $($_.Exception.Message)"
        Write-Host "Please ensure:" -ForegroundColor Cyan
        Write-Host "1. Bot service is running and accessible" -ForegroundColor Cyan
        Write-Host "2. BOT_ENDPOINT is correct: $botEndpoint" -ForegroundColor Cyan
        Write-Host "3. Network connectivity is available" -ForegroundColor Cyan
        Write-Host ""
    }
}

# Main execution
try {
    $os = Get-OperatingSystem
    Write-Host "=== Bot Service Setup Script ===" -ForegroundColor Magenta
    Write-Host "Platform detected: $os" -ForegroundColor Cyan
    Write-Host "Starting bot setup process..." -ForegroundColor Green
    
    # Load environment variables
    Load-EnvFile -FilePath $EnvFile
    
    # Set BOT_HOME
    Set-BotHome -Path $BotHomePath
    
    # Generate certificates
    Generate-PrivateKey
    Generate-CSR
    Generate-Certificate
    
    # Import certificate to certificate store (Windows only)
    Import-CertificateToStore
    
    # Start bot service initially
    Start-BotService
    
    # Encrypt secrets
    Encrypt-Secrets
    
    # Restart bot service after encryption
    Write-Host "Restarting bot service after certificate encryption..." -ForegroundColor Yellow
    Restart-BotService
    
    # Retrieve endpoint content
    Write-Host "Retrieving bot service endpoints..." -ForegroundColor Yellow
    Get-EndpointContent -Endpoint "/notify" -Description "Notify Endpoint"
    Get-EndpointContent -Endpoint "/messages" -Description "Messages Endpoint"
    
    Write-Host "=== Setup completed successfully! ===" -ForegroundColor Green
    Write-Host "Bot service endpoints have been retrieved and saved to text files." -ForegroundColor Cyan
    Write-Host "Check the following files for endpoint content:" -ForegroundColor Cyan
    Write-Host "- notify_content.txt" -ForegroundColor Yellow
    Write-Host "- messages_content.txt" -ForegroundColor Yellow
    
} catch {
    Write-Error "Setup failed: $($_.Exception.Message)"
    exit 1
}