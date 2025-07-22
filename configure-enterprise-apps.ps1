# PowerShell Script for Advanced Enterprise Application Configuration
# This script uses Microsoft Graph PowerShell to configure enterprise applications

# Install required modules if not already installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Application.ReadWrite.All", "Directory.ReadWrite.All"

# Variables
$TenantId = "TENANT_ID_PLACEHOLDER"
$SamlAppName = "SAML_APP_NAME_PLACEHOLDER"
$ProxyAppName = "PROXY_APP_NAME_PLACEHOLDER"

# Function to configure SAML application
function Configure-SamlApplication {
    param($AppName)
    
    Write-Host "Configuring SAML application: $AppName"
    
    # Get the service principal
    $sp = Get-MgServicePrincipal -Filter "displayName eq '$AppName'"
    
    if ($sp) {
        # Update service principal for SAML
        Update-MgServicePrincipal -ServicePrincipalId $sp.Id -PreferredSingleSignOnMode "saml"
        
        # Add enterprise tags
        $tags = @("Enterprise", "SAML", "SingleSignOn", "WindowsAzureActiveDirectoryGalleryApplicationNonPrimaryV1")
        Update-MgServicePrincipal -ServicePrincipalId $sp.Id -Tags $tags
        
        Write-Host "✓ SAML application configured successfully"
    } else {
        Write-Error "SAML application not found: $AppName"
    }
}

# Function to configure Application Proxy
function Configure-ApplicationProxy {
    param($AppName)
    
    Write-Host "Configuring Application Proxy application: $AppName"
    
    # Get the service principal
    $sp = Get-MgServicePrincipal -Filter "displayName eq '$AppName'"
    
    if ($sp) {
        # Update service principal for Application Proxy
        Update-MgServicePrincipal -ServicePrincipalId $sp.Id -PreferredSingleSignOnMode "integrated"
        
        # Add enterprise tags
        $tags = @("Enterprise", "ApplicationProxy", "WebApp", "WindowsAzureActiveDirectoryApplicationProxyV1")
        Update-MgServicePrincipal -ServicePrincipalId $sp.Id -Tags $tags
        
        Write-Host "✓ Application Proxy application configured successfully"
    } else {
        Write-Error "Application Proxy application not found: $AppName"
    }
}

# Main execution
try {
    Configure-SamlApplication -AppName $SamlAppName
    Configure-ApplicationProxy -AppName $ProxyAppName
    
    Write-Host "✓ All enterprise applications configured successfully"
    Write-Host "Check Azure AD > Enterprise Applications to verify the configuration"
} catch {
    Write-Error "Error configuring enterprise applications: $_"
} finally {
    Disconnect-MgGraph
}
