// services/azureResourceManager.js
const { ResourceManagementClient } = require("@azure/arm-resources");
const { ClientSecretCredential } = require("@azure/identity");

class AzureResourceManager {
  constructor() {
    this.client = null;
    this.credential = null;
  }

  async initialize(tenantId, subscriptionId, clientId, clientSecret) {
    this.credential = new ClientSecretCredential(
      tenantId,
      clientId,
      clientSecret
    );
    this.client = new ResourceManagementClient(this.credential, subscriptionId);
  }

  async createResourceGroup(resourceGroupName, location) {
    try {
      const resourceGroup = {
        location: location,
        tags: {
          Environment: "automated-provisioning",
          CreatedBy: "azure-provisioner-app",
          CreatedAt: new Date().toISOString(),
        },
      };

      const result = await this.client.resourceGroups.createOrUpdate(
        resourceGroupName,
        resourceGroup
      );

      return {
        name: result.name,
        location: result.location,
        id: result.id,
        provisioningState: result.provisioningState,
      };
    } catch (error) {
      throw new Error(`Failed to create resource group: ${error.message}`);
    }
  }

  async deployARMTemplate(resourceGroupName, templateContent, parameters) {
    try {
      const deploymentName = `deployment-${Date.now()}`;
      const deploymentParameters = {
        properties: {
          mode: "Incremental",
          template: templateContent,
          parameters: parameters,
        },
      };

      const deployment = await this.client.deployments.beginCreateOrUpdate(
        resourceGroupName,
        deploymentName,
        deploymentParameters
      );

      const result = await deployment.pollUntilDone();
      return result;
    } catch (error) {
      throw new Error(`ARM template deployment failed: ${error.message}`);
    }
  }
}

// services/graphApiService.js
const { Client } = require("@microsoft/microsoft-graph-client");
const { ClientSecretCredential } = require("@azure/identity");

class GraphApiService {
  constructor() {
    this.graphClient = null;
    this.credential = null;
  }

  async initialize(tenantId, clientId, clientSecret) {
    this.credential = new ClientSecretCredential(
      tenantId,
      clientId,
      clientSecret
    );

    // Custom authentication provider for Microsoft Graph
    const authProvider = {
      getAccessToken: async () => {
        const tokenResponse = await this.credential.getToken(
          "https://graph.microsoft.com/.default"
        );
        return tokenResponse.token;
      },
    };

    this.graphClient = Client.initWithMiddleware({
      authProvider: authProvider,
    });
  }

  async createAppRegistration(config) {
    try {
      // Create the application
      const application = {
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
        application.web = {
          redirectUris: config.redirectUris,
          implicitGrantSettings: {
            enableIdTokenIssuance: true,
            enableAccessTokenIssuance: false,
          },
        };
      } else if (config.type === "spa") {
        application.spa = {
          redirectUris: config.redirectUris,
        };
      }

      const createdApp = await this.graphClient
        .api("/applications")
        .post(application);

      // Create client secret
      const clientSecret = await this.createClientSecret(createdApp.id);

      // Create service principal
      const servicePrincipal = await this.graphClient
        .api("/servicePrincipals")
        .post({
          appId: createdApp.appId,
        });

      return {
        appId: createdApp.appId,
        objectId: createdApp.id,
        displayName: createdApp.displayName,
        clientSecret: clientSecret.secretText,
        servicePrincipalId: servicePrincipal.id,
        servicePrincipalObjectId: servicePrincipal.id,
      };
    } catch (error) {
      throw new Error(`Failed to create app registration: ${error.message}`);
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

      const secret = await this.graphClient
        .api(`/applications/${applicationId}/addPassword`)
        .post(passwordCredential);

      return secret;
    } catch (error) {
      throw new Error(`Failed to create client secret: ${error.message}`);
    }
  }

  async createEnterpriseApplication(config) {
    try {
      // Create application for enterprise app
      const application = {
        displayName: config.name,
        signInAudience: "AzureADMyOrg",
        identifierUris: [config.samlSettings.identifier],
        web: {
          redirectUris: [config.samlSettings.replyUrl],
        },
      };

      const createdApp = await this.graphClient
        .api("/applications")
        .post(application);

      // Create service principal with SAML SSO
      const servicePrincipal = await this.graphClient
        .api("/servicePrincipals")
        .post({
          appId: createdApp.appId,
          tags: ["WindowsAzureActiveDirectoryIntegratedApp"],
          preferredSingleSignOnMode: "saml",
        });

      // Configure SAML settings (simplified)
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
      throw new Error(
        `Failed to create enterprise application: ${error.message}`
      );
    }
  }

  async configureSAMLSettings(servicePrincipalId, samlSettings) {
    try {
      // This is a simplified SAML configuration
      // In production, you'd need more detailed SAML claim configurations
      const updateData = {
        loginUrl: samlSettings.signOnUrl,
        logoutUrl: samlSettings.signOnUrl + "/logout",
        samlSingleSignOnSettings: {
          relayState: "",
        },
      };

      await this.graphClient
        .api(`/servicePrincipals/${servicePrincipalId}`)
        .patch(updateData);
    } catch (error) {
      console.warn(`SAML configuration warning: ${error.message}`);
    }
  }

  async configureCrossApplicationPermissions(appRegistrations) {
    try {
      if (appRegistrations.length < 3) return;

      const [app1, app2, app3] = appRegistrations;

      // Configure App1 to access App2
      await this.addApplicationPermission(app1.objectId, app2.appId, [
        "api.access",
      ]);

      // Configure App3 to access App1 and App2
      await this.addApplicationPermission(app3.objectId, app1.appId, [
        "user.read",
      ]);
      await this.addApplicationPermission(app3.objectId, app2.appId, [
        "api.access",
      ]);

      console.log("Cross-application permissions configured successfully");
    } catch (error) {
      throw new Error(
        `Failed to configure cross permissions: ${error.message}`
      );
    }
  }

  async addApplicationPermission(sourceAppObjectId, targetAppId, scopes) {
    try {
      // Get current required resource access
      const app = await this.graphClient
        .api(`/applications/${sourceAppObjectId}`)
        .get();
      const currentAccess = app.requiredResourceAccess || [];

      // Add new resource access
      const newResourceAccess = {
        resourceAppId: targetAppId,
        resourceAccess: scopes.map((scope) => ({
          id: this.generateGuid(), // In production, get actual scope IDs
          type: "Scope",
        })),
      };

      currentAccess.push(newResourceAccess);

      await this.graphClient
        .api(`/applications/${sourceAppObjectId}`)
        .patch({ requiredResourceAccess: currentAccess });
    } catch (error) {
      console.warn(`Permission configuration warning: ${error.message}`);
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

// services/botServiceManager.js
const { AzureBotService } = require("@azure/arm-botservice");
const { WebSiteManagementClient } = require("@azure/arm-appservice");
const { ClientSecretCredential } = require("@azure/identity");

class BotServiceManager {
  constructor() {
    this.botClient = null;
    this.webClient = null;
    this.credential = null;
  }

  async initialize(tenantId, subscriptionId, clientId, clientSecret) {
    this.credential = new ClientSecretCredential(
      tenantId,
      clientId,
      clientSecret
    );
    this.botClient = new AzureBotService(this.credential, subscriptionId);
    this.webClient = new WebSiteManagementClient(
      this.credential,
      subscriptionId
    );
  }

  async createBotService(config) {
    try {
      // Create App Service Plan first
      const appServicePlan = await this.createAppServicePlan(
        config.resourceGroupName,
        `${config.botName}-plan`,
        config.location
      );

      // Create Bot Service
      const botParameters = {
        location: config.location,
        sku: {
          name: "F0", // Free tier
        },
        kind: "azurebot",
        properties: {
          displayName: config.botName,
          description: "Bot service created via automated provisioning",
          iconUrl: "",
          endpoint: `https://${config.botName}.azurewebsites.net/api/messages`,
          msaAppId: "", // Will be updated after app registration
          msaAppMSIResourceId: "",
          msaAppTenantId: this.credential.tenantId,
          msaAppType: "MultiTenant",
          isCmekEnabled: false,
          isIsolated: false,
          schemaTransformationVersion: "1.3",
        },
        tags: {
          Environment: config.environment,
          Purpose: "Bot Service",
          CreatedBy: "azure-provisioner-app",
        },
      };

      const botService = await this.botClient.bots.create(
        config.resourceGroupName,
        config.botName,
        botParameters
      );

      return {
        name: botService.name,
        id: botService.id,
        location: botService.location,
        endpoint: botService.properties.endpoint,
        msaAppId: botService.properties.msaAppId,
        appServicePlan: appServicePlan.name,
      };
    } catch (error) {
      throw new Error(`Failed to create bot service: ${error.message}`);
    }
  }

  async createAppServicePlan(resourceGroupName, planName, location) {
    try {
      const planParameters = {
        location: location || "East US",
        sku: {
          name: "F1",
          tier: "Free",
          size: "F1",
          family: "F",
          capacity: 1,
        },
        properties: {
          reserved: false,
        },
      };

      const plan = await this.webClient.appServicePlans.beginCreateOrUpdate(
        resourceGroupName,
        planName,
        planParameters
      );

      return plan;
    } catch (error) {
      throw new Error(`Failed to create app service plan: ${error.message}`);
    }
  }
}

module.exports = {
  AzureResourceManager,
  GraphApiService,
  BotServiceManager,
};
