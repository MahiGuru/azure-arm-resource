# Azure Portal Configuration Instructions

## Enterprise Applications Configuration

### 1. Locate Your Enterprise Applications

1. Go to **Azure Portal** (https://portal.azure.com)
2. Navigate to **Azure Active Directory**
3. Click on **Enterprise applications**
4. You should see your applications listed here:
   - `--app-proxy-saml-app`
   - `--chat-proxy-app`

### 2. Configure SAML Enterprise Application

1. Click on your SAML application
2. Go to **Single sign-on**
3. Select **SAML** as the method
4. Configure the following settings:
   - **Identifier (Entity ID)**: `https://saml-app-external.company.com`
   - **Reply URL**: `https://saml-app-external.company.com/sso`
   - **Sign on URL**: `https://saml-app-external.company.com`
   - **Logout URL**: `https://saml-app-external.company.com/logout`

5. Configure **User Attributes & Claims**:
   - **givenname**: user.givenname
   - **surname**: user.surname
   - **emailaddress**: user.mail

6. Download the **Certificate (Base64)** for your application
7. Note the **Login URL** and **Logout URL** for configuration

### 3. Configure Application Proxy Enterprise Application

1. Click on your Application Proxy application
2. Go to **Application proxy**
3. Configure the following settings:
   - **Internal URL**: `http://internal-chat-app.company.com`
   - **External URL**: `https://chat-app-external.company.com`
   - **Pre-authentication**: Azure Active Directory
   - **Connector group**: Default (or your custom group)
   - **Backend application timeout**: Default
   - **Use HTTP-Only cookie**: No
   - **Use Secure cookie**: Yes
   - **Use Persistent cookie**: No

4. Go to **Single sign-on**
5. Select **Integrated Windows Authentication** or **Password-based**
6. Configure delegated login if needed

### 4. Assign Users and Groups

For both applications:
1. Go to **Users and groups**
2. Click **Add user/group**
3. Select users or groups that should have access
4. Assign appropriate roles

### 5. Test Your Applications

1. **SAML Application**:
   - Go to `https://saml-app-external.company.com`
   - You should be redirected to Azure AD for authentication
   - After successful login, you should be redirected back to your app

2. **Application Proxy**:
   - Go to `https://chat-app-external.company.com`
   - You should be prompted for Azure AD authentication
   - After successful login, you should see your internal application

### 6. Troubleshooting

- **SAML Issues**: Check the SAML response in browser dev tools
- **Application Proxy Issues**: Check connector status and logs
- **Authentication Issues**: Verify user assignments and permissions

### 7. Application Proxy Connector

If you haven't installed the Application Proxy connector:
1. Go to **Azure Active Directory** > **Application proxy**
2. Click **Download connector service**
3. Install the connector on your on-premises server
4. Configure the connector to connect to your tenant

## Important Notes

- Enterprise applications created this way will appear under **Enterprise applications** in Azure Portal
- These are different from **App registrations** which are for developers
- Users will see these applications in their **My Apps** portal
- You can customize the application tiles and descriptions

## Next Steps

1. Configure your on-premises applications to work with Azure AD authentication
2. Test the SSO flow end-to-end
3. Configure conditional access policies if needed
4. Set up monitoring and alerting for the applications

