// services/graphApiService.js - Simplified Working Version
const { Client } = require("@microsoft/microsoft-graph-client");
const { ClientSecretCredential } = require("@azure/identity");
const axios = require("axios");

class GraphApiService {
  constructor() {
    this.graphClient = null;
    this.credential = null;
    this.accessToken = null;
  }

  async initialize(tenantId, clientId, clientSecret) {
    this.credential = new ClientSecretCredential(
      tenantId,
      clientId,
      clientSecret
    );

    try {
      // Get access token for Microsoft Graph
      const tokenResponse = await this.credential.getToken(
        "https://graph.microsoft.com/.default"
      );
      this.accessToken = tokenResponse.token;

      // Initialize Graph client with simple auth
      this.graphClient = Client.init({
        authProvider: (done) => {
          done(null, this.accessToken);
        },
      });

      console.log("Graph API service initialized successfully");
    } catch (error) {
      console.error("Failed to initialize Graph API service:", error.message);
      throw new Error(`Graph API initialization failed: ${error.message}`);
    }
  }

  async createAppRegistration(config) {
    try {
      // Create the application using direct API call for better control
      const applicationData = {
        displayName: config.name,
        signInAudience: "AzureADMyOrg",
        requiredResourceAccess: [
          {
            resourceAppId: "00000003-0000-0000-c000-000000000000", // Microsoft Graph
            resourceAccess: [
              {
                id: "e1fe6dd8-ba31-4d61-89e7-88639da4683d", // User.Read
                type: "Scope",
              },
            ],
          },
        ],
        api: {
          requestedAccessTokenVersion: 2,
          oauth2PermissionScopes: config.scopes.map((scope) => ({
            id: this.generateGuid(),
            adminConsentDescription: `Allow the application to ${scope}`,
            adminConsentDisplayName: scope,
            userConsentDescription: `Allow the application to ${scope} on your behalf`,
            userConsentDisplayName: scope,
            value: scope,
            type: "User",
            isEnabled: true,
          })),
        },
      };

      // Configure redirect URIs based on app type
      if (config.type === "web") {
        applicationData.web = {
          redirectUris: config.redirectUris,
          implicitGrantSettings: {
            enableIdTokenIssuance: true,
            enableAccessTokenIssuance: false,
          },
        };
      } else if (config.type === "spa") {
        applicationData.spa = {
          redirectUris: config.redirectUris,
        };
      }

      // Create application using direct HTTP call
      const createAppResponse = await axios.post(
        "https://graph.microsoft.com/v1.0/applications",
        applicationData,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
            "Content-Type": "application/json",
          },
        }
      );

      const createdApp = createAppResponse.data;

      // Create client secret
      const clientSecret = await this.createClientSecret(createdApp.id);

      // Create service principal
      const servicePrincipalData = {
        appId: createdApp.appId,
      };

      const createSpResponse = await axios.post(
        "https://graph.microsoft.com/v1.0/servicePrincipals",
        servicePrincipalData,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
            "Content-Type": "application/json",
          },
        }
      );

      const servicePrincipal = createSpResponse.data;

      return {
        appId: createdApp.appId,
        objectId: createdApp.id,
        displayName: createdApp.displayName,
        clientSecret: clientSecret.secretText,
        servicePrincipalId: servicePrincipal.id,
        servicePrincipalObjectId: servicePrincipal.id,
      };
    } catch (error) {
      console.error(
        "Failed to create app registration:",
        error.response?.data || error.message
      );
      throw new Error(
        `Failed to create app registration: ${
          error.response?.data?.error?.message || error.message
        }`
      );
    }
  }

  async createClientSecret(
    applicationId,
    description = "Auto-generated secret"
  ) {
    try {
      const passwordCredential = {
        displayName: description,
        endDateTime: new Date(
          Date.now() + 365 * 24 * 60 * 60 * 1000
        ).toISOString(), // 1 year
      };

      const response = await axios.post(
        `https://graph.microsoft.com/v1.0/applications/${applicationId}/addPassword`,
        passwordCredential,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
            "Content-Type": "application/json",
          },
        }
      );

      return response.data;
    } catch (error) {
      console.error(
        "Failed to create client secret:",
        error.response?.data || error.message
      );
      throw new Error(
        `Failed to create client secret: ${
          error.response?.data?.error?.message || error.message
        }`
      );
    }
  }

  async createEnterpriseApplication(config) {
    try {
      // Create application for enterprise app
      const applicationData = {
        displayName: config.name,
        signInAudience: "AzureADMyOrg",
        identifierUris: [config.samlSettings.identifier],
        web: {
          redirectUris: [config.samlSettings.replyUrl],
        },
      };

      const createAppResponse = await axios.post(
        "https://graph.microsoft.com/v1.0/applications",
        applicationData,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
            "Content-Type": "application/json",
          },
        }
      );

      const createdApp = createAppResponse.data;

      // Create service principal with SAML SSO
      const servicePrincipalData = {
        appId: createdApp.appId,
        tags: ["WindowsAzureActiveDirectoryIntegratedApp"],
        preferredSingleSignOnMode: "saml",
      };

      const createSpResponse = await axios.post(
        "https://graph.microsoft.com/v1.0/servicePrincipals",
        servicePrincipalData,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
            "Content-Type": "application/json",
          },
        }
      );

      const servicePrincipal = createSpResponse.data;

      // Configure basic SAML settings
      await this.configureSAMLSettings(
        servicePrincipal.id,
        config.samlSettings
      );

      return {
        appId: createdApp.appId,
        objectId: createdApp.id,
        displayName: createdApp.displayName,
        servicePrincipalId: servicePrincipal.id,
        ssoMode: "saml",
        samlSettings: config.samlSettings,
        proxySettings: config.proxySettings,
      };
    } catch (error) {
      console.error(
        "Failed to create enterprise application:",
        error.response?.data || error.message
      );
      throw new Error(
        `Failed to create enterprise application: ${
          error.response?.data?.error?.message || error.message
        }`
      );
    }
  }

  async configureSAMLSettings(servicePrincipalId, samlSettings) {
    try {
      // Basic SAML configuration
      const updateData = {
        loginUrl: samlSettings.signOnUrl,
        logoutUrl: samlSettings.signOnUrl + "/logout",
      };

      await axios.patch(
        `https://graph.microsoft.com/v1.0/servicePrincipals/${servicePrincipalId}`,
        updateData,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
            "Content-Type": "application/json",
          },
        }
      );
    } catch (error) {
      console.warn(
        `SAML configuration warning: ${
          error.response?.data?.error?.message || error.message
        }`
      );
    }
  }

  async configureCrossApplicationPermissions(appRegistrations) {
    try {
      if (appRegistrations.length < 3) return;

      const [app1, app2, app3] = appRegistrations;

      // Configure App1 to access App2
      await this.addApplicationPermission(app1.objectId, app2.appId);

      // Configure App3 to access App1 and App2
      await this.addApplicationPermission(app3.objectId, app1.appId);
      await this.addApplicationPermission(app3.objectId, app2.appId);

      console.log("Cross-application permissions configured successfully");
    } catch (error) {
      console.error("Failed to configure cross permissions:", error.message);
      throw new Error(
        `Failed to configure cross permissions: ${error.message}`
      );
    }
  }

  async addApplicationPermission(sourceAppObjectId, targetAppId) {
    try {
      // Get current app
      const getAppResponse = await axios.get(
        `https://graph.microsoft.com/v1.0/applications/${sourceAppObjectId}`,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
          },
        }
      );

      const app = getAppResponse.data;
      const currentAccess = app.requiredResourceAccess || [];

      // Add basic Microsoft Graph permissions
      const newResourceAccess = {
        resourceAppId: "00000003-0000-0000-c000-000000000000", // Microsoft Graph
        resourceAccess: [
          {
            id: "e1fe6dd8-ba31-4d61-89e7-88639da4683d", // User.Read
            type: "Scope",
          },
        ],
      };

      // Check if this resource access already exists
      const existingAccess = currentAccess.find(
        (access) => access.resourceAppId === newResourceAccess.resourceAppId
      );
      if (!existingAccess) {
        currentAccess.push(newResourceAccess);

        await axios.patch(
          `https://graph.microsoft.com/v1.0/applications/${sourceAppObjectId}`,
          { requiredResourceAccess: currentAccess },
          {
            headers: {
              Authorization: `Bearer ${this.accessToken}`,
              "Content-Type": "application/json",
            },
          }
        );
      }
    } catch (error) {
      console.warn(
        `Permission configuration warning: ${
          error.response?.data?.error?.message || error.message
        }`
      );
    }
  }

  generateGuid() {
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(
      /[xy]/g,
      function (c) {
        const r = (Math.random() * 16) | 0;
        const v = c === "x" ? r : (r & 0x3) | 0x8;
        return v.toString(16);
      }
    );
  }
}

module.exports = { GraphApiService };
