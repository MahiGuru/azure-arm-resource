# Manual Fix Instructions for Enterprise Applications

## Issue: Applications not appearing in Enterprise Applications

If your applications are not appearing in the Enterprise Applications section of Azure AD, follow these steps:

### Step 1: Check Current Location
1. Go to Azure Portal > Azure AD > App Registrations
2. Look for:
   - `mg-dev-app-proxy-saml-app`
   - `mg-dev-chat-proxy-app`

### Step 2: Create Service Principals (if missing)
If the applications exist in App Registrations but not in Enterprise Applications:

1. Go to Azure Portal > Azure AD > App Registrations
2. Click on `mg-dev-app-proxy-saml-app`
3. Note the Application (client) ID
4. Go to Azure AD > Enterprise Applications
5. Click "New application" > "Create your own application"
6. Select "Integrate any other application you don't find in the gallery"
7. Name it `mg-dev-app-proxy-saml-app`
8. Click "Create"

Repeat for the second application.

### Step 3: Configure SSO Mode
For each enterprise application:

1. Go to Azure AD > Enterprise Applications
2. Click on the application
3. Go to "Single sign-on"
4. For SAML app: Select "SAML"
5. For Application Proxy app: Select "Integrated Windows Authentication"

### Step 4: Alternative PowerShell Method
If the above doesn't work, use PowerShell:

```powershell
# Install required module
Install-Module -Name AzureAD -Force

# Connect to Azure AD
Connect-AzureAD

# For SAML app
$samlApp = Get-AzureADApplication -Filter "displayName eq 'mg-dev-app-proxy-saml-app'"
$samlSP = New-AzureADServicePrincipal -AppId $samlApp.AppId
Set-AzureADServicePrincipal -ObjectId $samlSP.ObjectId -PreferredSingleSignOnMode "saml"

# For Application Proxy app
$proxyApp = Get-AzureADApplication -Filter "displayName eq 'mg-dev-chat-proxy-app'"
$proxySP = New-AzureADServicePrincipal -AppId $proxyApp.AppId
Set-AzureADServicePrincipal -ObjectId $proxySP.ObjectId -PreferredSingleSignOnMode "integrated"
```

### Step 5: Verify
1. Go to Azure AD > Enterprise Applications
2. Both applications should now appear in the list
3. Click on each application to verify SSO mode is set correctly

### Step 6: Complete Configuration
Follow the configuration guide generated earlier to complete the setup.

## Common Issues and Solutions

### Issue: "Application not found" error
**Solution**: Check the application name for typos and ensure it exists in App Registrations

### Issue: "Insufficient privileges" error
**Solution**: Ensure you have Application Administrator or Global Administrator role

### Issue: Service principal creation fails
**Solution**: Wait 5-10 minutes after creating the app registration, then try again

### Issue: Applications appear in wrong section
**Solution**: The key is the service principal - ensure it exists and has the correct tags

## Contact Support
If these steps don't resolve the issue, contact your Azure administrator or Microsoft support.
