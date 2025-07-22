# Enterprise Application Configuration Guide

Generated on: Wed Jul  9 17:00:04 IST 2025

## Overview

This guide provides step-by-step instructions for configuring the enterprise applications created by the deployment script. These applications should appear in the **Azure AD > Enterprise Applications** section, not under App Registrations.

## Prerequisites

- Azure AD admin privileges
- Access to Azure Portal
- Application Proxy connector installed (for proxy applications)

---

## 1. SAML Enterprise Application Configuration

### Application Details
- **Name**: mg-dev-app-proxy-saml-app
- **App ID**: 
- **Type**: SAML SSO Application
- **Internal URL**: http://internal-saml-app.company.com
- **External URL**: https://saml-app-external.company.com

### Configuration Steps

#### Step 1: Access the Enterprise Application
1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to **Azure Active Directory** > **Enterprise Applications**
3. Search for and select: `mg-dev-app-proxy-saml-app`
4. If not found in Enterprise Applications, check **App Registrations** and move/configure as needed

#### Step 2: Configure SAML Single Sign-On
1. In the enterprise application, go to **Single sign-on**
2. Select **SAML** as the single sign-on method
3. Configure the following settings:

   **Basic SAML Configuration:**
   - **Identifier (Entity ID)**: `https://saml-app-external.company.com`
   - **Reply URL (Assertion Consumer Service URL)**: `https://saml-app-external.company.com/sso`
   - **Sign on URL**: `https://saml-app-external.company.com`
   - **Logout URL**: `https://saml-app-external.company.com/logout`

   **User Attributes & Claims:**
   - **givenname**: user.givenname
   - **surname**: user.surname
   - **emailaddress**: user.mail
   - **Name ID format**: Persistent

#### Step 3: Download Certificate
1. In the **SAML Signing Certificate** section
2. Download the **Certificate (Base64)**
3. Save it to your application server

#### Step 4: Configure Application
1. Note the **Login URL** and **Logout URL** from the setup section
2. Configure your application with:
   - **SAML Certificate**: The downloaded certificate
   - **SAML Login URL**: The login URL from Azure
   - **SAML Logout URL**: The logout URL from Azure

#### Step 5: Test Configuration
1. Go to **Test single sign-on**
2. Test the SAML configuration
3. Verify user attributes are passed correctly

---

## 2. Application Proxy Enterprise Application Configuration

### Application Details
- **Name**: mg-dev-chat-proxy-app
- **App ID**: d5f6a81b-e47e-4acd-bc13-e5a897a4fcf3
- **Type**: Application Proxy
- **Internal URL**: http://internal-chat-app.company.com
- **External URL**: https://chat-app-external.company.com

### Configuration Steps

#### Step 1: Access the Enterprise Application
1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to **Azure Active Directory** > **Enterprise Applications**
3. Search for and select: `mg-dev-chat-proxy-app`

#### Step 2: Configure Application Proxy
1. In the enterprise application, go to **Application proxy**
2. Configure the following settings:

   **Basic Configuration:**
   - **Internal URL**: `http://internal-chat-app.company.com`
   - **External URL**: `https://chat-app-external.company.com`
   - **Pre-authentication**: Azure Active Directory
   - **Connector group**: Default (or create custom group)

   **Advanced Settings:**
   - **Backend application timeout**: Default
   - **Use HTTP-Only cookie**: No
   - **Use Secure cookie**: Yes
   - **Use Persistent cookie**: No
   - **Translate URLs in headers**: Yes
   - **Translate URLs in application body**: No

#### Step 3: Configure Single Sign-On
1. Go to **Single sign-on**
2. Select **Integrated Windows Authentication** or **Headers-based authentication**
3. Configure as needed for your application

#### Step 4: Configure Connector
1. Ensure Application Proxy connector is installed on your on-premises server
2. Verify connector is running and connected
3. Assign the connector to the appropriate connector group

#### Step 5: Test Configuration
1. Go to **Test single sign-on**
2. Test access to the external URL
3. Verify users can access the internal application through the proxy

---

## 3. User and Group Assignment

### For Both Applications:

#### Assign Users and Groups
1. In each enterprise application, go to **Users and groups**
2. Click **Add user/group**
3. Select users or groups that should have access
4. Assign appropriate roles if applicable

#### Configure Access Policies
1. Go to **Conditional Access** (if available)
2. Create policies for additional security
3. Configure MFA requirements if needed

---

## 4. Troubleshooting

### Common Issues and Solutions

#### SAML Application Issues
- **Error**: "SAML response not valid"
  - **Solution**: Check certificate validity and URL configuration
  - **Verify**: Entity ID matches application configuration

- **Error**: "User attributes not received"
  - **Solution**: Verify attribute mapping in Azure AD
  - **Check**: Claims configuration in SAML setup

#### Application Proxy Issues
- **Error**: "Application not accessible"
  - **Solution**: Check connector status and connectivity
  - **Verify**: Internal URL is accessible from connector server

- **Error**: "Authentication failed"
  - **Solution**: Verify SSO configuration
  - **Check**: User has appropriate permissions

### Verification Commands

```bash
# Check SAML enterprise app
az ad sp show --id $(az ad sp list --display-name "mg-dev-app-proxy-saml-app" --query "[0].id" -o tsv) --query "{displayName:displayName, preferredSingleSignOnMode:preferredSingleSignOnMode, tags:tags}"

# Check Application Proxy enterprise app
az ad sp show --id $(az ad sp list --display-name "mg-dev-chat-proxy-app" --query "[0].id" -o tsv) --query "{displayName:displayName, preferredSingleSignOnMode:preferredSingleSignOnMode, tags:tags}"
```

---

## 5. Post-Configuration Checklist

### SAML Application
- [ ] Enterprise application appears in Enterprise Applications section
- [ ] SAML SSO is configured with correct URLs
- [ ] Certificate is downloaded and configured in application
- [ ] User attributes are mapped correctly
- [ ] Test login works successfully
- [ ] Users are assigned to the application

### Application Proxy
- [ ] Enterprise application appears in Enterprise Applications section
- [ ] Application Proxy is configured with correct URLs
- [ ] Connector is installed and running
- [ ] SSO method is configured
- [ ] External URL is accessible
- [ ] Users are assigned to the application

### General
- [ ] Both applications have proper tags for Enterprise Applications
- [ ] Service principals are configured with correct SSO modes
- [ ] Access policies are configured if needed
- [ ] Users can access applications through My Apps portal

---

## 6. Additional Resources

- [Azure AD SAML SSO Documentation](https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/configure-saml-single-sign-on)
- [Application Proxy Documentation](https://docs.microsoft.com/en-us/azure/active-directory/app-proxy/application-proxy)
- [Enterprise Applications Overview](https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/what-is-application-management)

---

## Support

If you encounter issues:
1. Check the Azure AD sign-in logs
2. Verify connector status (for Application Proxy)
3. Test from different networks/devices
4. Contact your Azure administrator

Generated by: Enterprise Application Configuration Helper
