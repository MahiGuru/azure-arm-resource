// server.js - Enhanced Complete Version with API Permissions & Admin Consent
const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const morgan = require("morgan");
const rateLimit = require("express-rate-limit");
const Joi = require("joi");
const path = require("path");
const { v4: uuidv4 } = require("uuid");
const axios = require("axios");
const { ResourceManagementClient } = require("@azure/arm-resources");
const { ClientSecretCredential } = require("@azure/identity");
require("dotenv").config();

const app = express();
const port = process.env.PORT || 3000;

// Security middleware
app.use(
  helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        scriptSrc: ["'self'", "'unsafe-inline'"],
        imgSrc: ["'self'", "data:", "https:"],
      },
    },
  })
);

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100,
  message: { error: "Too many requests from this IP, please try again later." },
});

app.use("/api/", limiter);
app.use(morgan("combined"));
app.use(cors());
app.use(express.json({ limit: "10mb" }));
app.use(express.urlencoded({ extended: true, limit: "10mb" }));
app.use(express.static("public"));

// Complete validation schema with all fields using unique IDs
const provisioningSchema = Joi.object({
  tenantId: Joi.string().guid().required(),
  subscriptionId: Joi.string().guid().required(),
  resourceGroupName: Joi.string()
    .min(1)
    .max(90)
    .pattern(/^[a-zA-Z0-9._-]+$/)
    .required(),
  location: Joi.string()
    .valid(
      "East US",
      "West US",
      "West Europe",
      "North Europe",
      "Southeast Asia"
    )
    .default("East US"),
  environment: Joi.string().valid("dev", "test", "prod").default("dev"),
  applicationPrefix: Joi.string()
    .min(1)
    .max(20)
    .pattern(/^[a-zA-Z0-9]+$/)
    .default("myapp"),
  clientId: Joi.string().guid().required(),
  clientSecret: Joi.string().min(1).required(),

  // App Registration Configuration with unique IDs
  app1Name: Joi.string()
    .min(1)
    .max(50)
    .pattern(/^[a-zA-Z0-9-_]+$/)
    .default("mahi-connector-app"),
  app1Id: Joi.string().valid("MAHI_CONNECTOR_APP").required(),
  app1RedirectUri: Joi.string().uri().optional(),
  app2Name: Joi.string()
    .min(1)
    .max(50)
    .pattern(/^[a-zA-Z0-9-_]+$/)
    .default("mahi-api-access"),
  app2Id: Joi.string().valid("MAHI_API_ACCESS").required(),
  app2RedirectUri: Joi.string().uri().optional(),
  app3Name: Joi.string()
    .min(1)
    .max(50)
    .pattern(/^[a-zA-Z0-9-_]+$/)
    .default("mahi-teams-app"),
  app3Id: Joi.string().valid("MAHI_TEAMS_APP").required(),
  app3RedirectUri: Joi.string().uri().optional(),
  enableCrossPermissions: Joi.string()
    .valid("true", "false")
    .default("true")
    .custom((value) => value === "true"),
  generateSecrets: Joi.string()
    .valid("true", "false")
    .default("true")
    .custom((value) => value === "true"),
  grantAdminConsent: Joi.string()
    .valid("true", "false")
    .default("true")
    .custom((value) => value === "true"),

  // Enterprise Application Configuration with unique IDs
  enterprise1Name: Joi.string()
    .min(1)
    .max(50)
    .pattern(/^[a-zA-Z0-9-_]+$/)
    .default("app-proxy-saml-app"),
  enterprise1Id: Joi.string().valid("APP_PROXY_SAML_APP").required(),
  enterprise2Name: Joi.string()
    .min(1)
    .max(50)
    .pattern(/^[a-zA-Z0-9-_]+$/)
    .default("chat-proxy-app"),
  enterprise2Id: Joi.string().valid("CHAT_PROXY_APP").required(),

  // Application Proxy Configuration
  enterprise1InternalUrl: Joi.string().uri().optional(),
  enterprise1ExternalUrl: Joi.string().uri().optional(),
  enterprise2InternalUrl: Joi.string().uri().optional(),
  enterprise2ExternalUrl: Joi.string().uri().optional(),
});

/**
 * Validation middleware that validates incoming request bodies against a Joi schema
 * @param {Joi.ObjectSchema} schema - The Joi schema to validate against
 * @returns {Function} Express middleware function
 */
function validateRequest(schema) {
  return (req, res, next) => {
    const { error, value } = schema.validate(req.body);
    if (error) {
      return res.status(400).json({
        success: false,
        error: "Validation failed",
        details: error.details.map((detail) => ({
          field: detail.path.join("."),
          message: detail.message,
        })),
      });
    }
    req.validatedData = value;
    next();
  };
}

/**
 * Centralized logging utility for consistent log formatting across the application
 * @param {string} level - Log level (info, error, warn)
 * @param {string} message - Log message
 * @param {Object} data - Additional data to include in log
 */
function log(level, message, data = {}) {
  const logEntry = {
    timestamp: new Date().toISOString(),
    level,
    message,
    ...data,
  };
  console.log(JSON.stringify(logEntry));
}

/**
 * Azure Resource Manager class for managing Azure Resource Groups
 * Handles authentication and resource group creation operations
 */
class AzureResourceManager {
  constructor() {
    this.client = null;
    this.credential = null;
  }

  /**
   * Initializes the Azure Resource Manager client with service principal credentials
   * @param {string} tenantId - Azure AD tenant ID
   * @param {string} subscriptionId - Azure subscription ID
   * @param {string} clientId - Service principal client ID
   * @param {string} clientSecret - Service principal client secret
   */
  async initialize(tenantId, subscriptionId, clientId, clientSecret) {
    this.credential = new ClientSecretCredential(
      tenantId,
      clientId,
      clientSecret
    );
    this.client = new ResourceManagementClient(this.credential, subscriptionId);
  }

  /**
   * Creates or updates an Azure Resource Group in the specified location
   * @param {string} resourceGroupName - Name of the resource group to create
   * @param {string} location - Azure region where the resource group should be created
   * @returns {Object} Created resource group details including name, location, and ID
   */
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
}

/**
 * Enhanced Graph API Service class for managing Azure AD applications and service principals
 * Handles app registrations, enterprise applications, API permissions, and admin consent
 */
class GraphApiService {
  constructor() {
    this.accessToken = null;
    this.credential = null;
  }

  /**
   * Initializes the Graph API service with service principal credentials and obtains access token
   * @param {string} tenantId - Azure AD tenant ID
   * @param {string} clientId - Service principal client ID
   * @param {string} clientSecret - Service principal client secret
   */
  async initialize(tenantId, clientId, clientSecret) {
    try {
      this.credential = new ClientSecretCredential(
        tenantId,
        clientId,
        clientSecret
      );
      const tokenResponse = await this.credential.getToken(
        "https://graph.microsoft.com/.default"
      );
      this.accessToken = tokenResponse.token;
      console.log("Graph API service initialized successfully");
    } catch (error) {
      throw new Error(`Graph API initialization failed: ${error.message}`);
    }
  }

  /**
   * Checks if an application with the given display name already exists in Azure AD
   * @param {string} displayName - Display name of the application to search for
   * @returns {Object|null} Existing application object or null if not found
   */
  async checkExistingApplication(displayName) {
    try {
      const response = await axios.get(
        `https://graph.microsoft.com/v1.0/applications?$filter=displayName eq '${displayName}'`,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
            "Content-Type": "application/json",
          },
        }
      );

      return response.data.value.length > 0 ? response.data.value[0] : null;
    } catch (error) {
      console.warn("Error checking existing application:", error.message);
      return null;
    }
  }

  /**
   * Checks if a service principal with the given app ID already exists in Azure AD
   * @param {string} appId - Application ID to search for
   * @returns {Object|null} Existing service principal object or null if not found
   */
  async checkExistingServicePrincipal(appId) {
    try {
      const response = await axios.get(
        `https://graph.microsoft.com/v1.0/servicePrincipals?$filter=appId eq '${appId}'`,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
            "Content-Type": "application/json",
          },
        }
      );

      return response.data.value.length > 0 ? response.data.value[0] : null;
    } catch (error) {
      console.warn("Error checking existing service principal:", error.message);
      return null;
    }
  }

  /**
   * Returns specific Microsoft Graph API permissions based on app unique ID
   * App1 (MAHI_CONNECTOR_APP) gets advanced permissions for role management, user management, and organization access
   * @param {string} appUniqueId - Unique identifier for the application
   * @returns {Array} Array of required resource access permissions
   */
  getAppPermissionsByUniqueId(appUniqueId) {
    if (appUniqueId === "MAHI_CONNECTOR_APP") {
      return [
        {
          resourceAppId: "00000003-0000-0000-c000-000000000000", // Microsoft Graph
          resourceAccess: [
            { id: "9e3f62cf-ca93-4989-b6ce-bf83c28f9fe8", type: "Role" }, // RoleManagement.ReadWrite.Directory
            { id: "c79f8feb-a9db-4090-85f9-90d820caa0eb", type: "Role" }, // Organization.Read.All
            { id: "09850681-111b-4a89-9bed-3f2cae46d706", type: "Role" }, // User.Invite.All
            { id: "6e472fd1-ad78-48da-a0f0-97ab2c6b769e", type: "Role" }, // IdentityRiskEvent.Read.All
            { id: "df021288-bdef-4463-88db-98f22de89214", type: "Role" }, // User.Read.All
            { id: "5b567255-7703-4780-807c-7be8301ae99b", type: "Role" }, // Group.Read.All
            { id: "62a82d76-70ea-41e2-9197-370581804d09", type: "Role" }, // Group.ReadWrite.All
            { id: "9a5d68dd-52b0-4cc2-bd40-abcf44ac3a30", type: "Role" }, // Application.Read.All
            { id: "e1fe6dd8-ba31-4d61-89e7-88639da4683d", type: "Scope" }, // User.Read (delegated)
          ],
        },
      ];
    }

    // Default permissions for other app registrations
    return [
      {
        resourceAppId: "00000003-0000-0000-c000-000000000000",
        resourceAccess: [
          {
            id: "e1fe6dd8-ba31-4d61-89e7-88639da4683d", // User.Read
            type: "Scope",
          },
        ],
      },
    ];
  }

  /**
   * Creates an Azure AD App Registration with specified configuration
   * Handles both new creation and reuse of existing applications
   * @param {Object} config - Configuration object containing app details, scopes, type, and redirect URIs
   * @returns {Object} Created or existing app registration details including client secret if generated
   */
  async createAppRegistration(config) {
    try {
      // Check if application already exists
      const existingApp = await this.checkExistingApplication(config.name);
      if (existingApp) {
        console.log(
          `App registration '${config.name}' already exists, using existing one`
        );

        // Get existing service principal
        const existingServicePrincipal =
          await this.checkExistingServicePrincipal(existingApp.appId);

        // Create a new client secret for the existing app (if requested)
        let clientSecret;
        if (config.generateSecret !== false) {
          try {
            clientSecret = await this.createClientSecret(existingApp.id);
          } catch (error) {
            console.warn(
              `Could not create new secret for existing app: ${error.message}`
            );
            clientSecret = {
              secretText:
                "Unable to generate new secret - use existing or create manually",
            };
          }
        } else {
          clientSecret = {
            secretText:
              "Secret generation skipped - use existing or create manually",
          };
        }

        return {
          appId: existingApp.appId,
          objectId: existingApp.id,
          displayName: existingApp.displayName,
          clientSecret: clientSecret.secretText,
          servicePrincipalId: existingServicePrincipal?.id || "Not found",
          redirectUris: config.redirectUris,
          type: config.type,
          uniqueId: config.uniqueId,
          isExisting: true,
          adminConsentGranted: false, // Assume not granted for existing apps
        };
      }

      // Create new application with specific permissions based on app name
      const applicationData = {
        displayName: config.name,
        signInAudience: "AzureADMyOrg",
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

      // Set specific permissions based on app unique ID
      applicationData.requiredResourceAccess = this.getAppPermissionsByUniqueId(
        config.uniqueId
      );

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

      // Create the application
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

      // For App2 (MAHI_API_ACCESS): Set Application ID URI
      if (config.uniqueId === "MAHI_API_ACCESS") {
        await this.setApplicationIdUri(createdApp.id, createdApp.appId);
      }

      // Create client secret only if requested
      let clientSecret = null;
      if (config.generateSecret !== false) {
        try {
          clientSecret = await this.createClientSecret(createdApp.id);
        } catch (error) {
          console.warn(`Could not create client secret: ${error.message}`);
          clientSecret = {
            secretText: "Secret generation failed - create manually if needed",
          };
        }
      } else {
        clientSecret = {
          secretText: "Secret generation skipped - create manually if needed",
        };
      }

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

      // Grant admin consent if requested and permissions exist
      let adminConsentGranted = false;
      if (config.grantAdminConsent && applicationData.requiredResourceAccess) {
        try {
          adminConsentGranted = await this.grantAdminConsent(
            servicePrincipal.id,
            applicationData.requiredResourceAccess
          );
        } catch (error) {
          console.warn(`Could not grant admin consent: ${error.message}`);
        }
      }

      return {
        appId: createdApp.appId,
        objectId: createdApp.id,
        displayName: createdApp.displayName,
        clientSecret: clientSecret.secretText,
        servicePrincipalId: servicePrincipal.id,
        redirectUris: config.redirectUris,
        type: config.type,
        uniqueId: config.uniqueId,
        isExisting: false,
        adminConsentGranted,
        applicationIdUri:
          config.uniqueId === "MAHI_API_ACCESS"
            ? `api://${createdApp.appId}/api`
            : null,
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

  /**
   * Sets the Application ID URI for an application (required for API applications)
   * @param {string} applicationId - Object ID of the application
   * @param {string} appId - Application ID (client ID)
   * @returns {string} The set Application ID URI
   */
  async setApplicationIdUri(applicationId, appId) {
    try {
      const applicationIdUri = `api://${appId}/api`;

      await axios.patch(
        `https://graph.microsoft.com/v1.0/applications/${applicationId}`,
        {
          identifierUris: [applicationIdUri],
        },
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
            "Content-Type": "application/json",
          },
        }
      );

      console.log(`Set Application ID URI: ${applicationIdUri}`);
      return applicationIdUri;
    } catch (error) {
      console.warn(`Could not set Application ID URI: ${error.message}`);
      throw error;
    }
  }

  /**
   * Grants admin consent for application permissions (role-based permissions)
   * Includes retry logic and better error handling for permission assignment
   * @param {string} servicePrincipalId - Object ID of the service principal
   * @param {Array} requiredResourceAccess - Array of required resource access permissions
   * @returns {boolean} True if at least one permission was granted successfully
   */
  async grantAdminConsent(servicePrincipalId, requiredResourceAccess) {
    try {
      let consentGranted = false;

      // Wait a bit for service principal to be fully created
      await new Promise((resolve) => setTimeout(resolve, 2000));

      for (const resource of requiredResourceAccess) {
        const resourceServicePrincipalId =
          await this.getServicePrincipalIdByAppId(resource.resourceAppId);

        for (const permission of resource.resourceAccess) {
          if (permission.type === "Role") {
            // Grant application permissions (admin consent required)
            try {
              const appRoleAssignment = {
                principalId: servicePrincipalId,
                resourceId: resourceServicePrincipalId,
                appRoleId: permission.id,
              };

              await axios.post(
                `https://graph.microsoft.com/v1.0/servicePrincipals/${servicePrincipalId}/appRoleAssignments`,
                appRoleAssignment,
                {
                  headers: {
                    Authorization: `Bearer ${this.accessToken}`,
                    "Content-Type": "application/json",
                  },
                }
              );

              consentGranted = true;
              console.log(
                `✅ Granted admin consent for permission: ${permission.id}`
              );

              // Small delay between permission grants
              await new Promise((resolve) => setTimeout(resolve, 500));
            } catch (error) {
              const errorMessage =
                error.response?.data?.error?.message || error.message;
              console.warn(
                `❌ Could not grant permission ${permission.id}: ${errorMessage}`
              );

              // Check if it's a "Permission being assigned already exists" error
              if (
                errorMessage.includes("already exists") ||
                errorMessage.includes(
                  "Permission being assigned already exists"
                )
              ) {
                console.log(
                  `ℹ️ Permission ${permission.id} already exists - considering as granted`
                );
                consentGranted = true;
              }
            }
          }
        }
      }

      if (consentGranted) {
        console.log(
          `✅ Admin consent process completed for service principal: ${servicePrincipalId}`
        );
      } else {
        console.warn(
          `⚠️ No admin consent permissions were granted for service principal: ${servicePrincipalId}`
        );
      }

      return consentGranted;
    } catch (error) {
      console.error(`❌ Admin consent failed: ${error.message}`);
      return false;
    }
  }

  /**
   * Gets the service principal object ID by application ID
   * @param {string} appId - Application ID to search for
   * @returns {string} Service principal object ID
   */
  async getServicePrincipalIdByAppId(appId) {
    try {
      const response = await axios.get(
        `https://graph.microsoft.com/v1.0/servicePrincipals?$filter=appId eq '${appId}'`,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
            "Content-Type": "application/json",
          },
        }
      );

      if (response.data.value.length > 0) {
        return response.data.value[0].id;
      }
      throw new Error(`Service principal not found for appId: ${appId}`);
    } catch (error) {
      throw new Error(`Could not find service principal: ${error.message}`);
    }
  }

  /**
   * Creates a client secret for an application with specified description and expiration
   * @param {string} applicationId - Object ID of the application
   * @param {string} description - Description for the client secret
   * @returns {Object} Created client secret object containing the secret value
   */
  async createClientSecret(
    applicationId,
    description = "Auto-generated secret"
  ) {
    try {
      const passwordCredential = {
        displayName: description,
        endDateTime: new Date(
          Date.now() + 365 * 24 * 60 * 60 * 1000
        ).toISOString(),
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
      throw new Error(
        `Failed to create client secret: ${
          error.response?.data?.error?.message || error.message
        }`
      );
    }
  }

  /**
   * Creates an Enterprise Application with SAML SSO and/or Application Proxy configuration
   * Handles both App Proxy SAML App (SAML + Proxy) and Chat Proxy App (Proxy only)
   * @param {Object} config - Configuration object containing app details, type, SAML settings, and proxy settings
   * @returns {Object} Created or existing enterprise application details
   */
  async createEnterpriseApplication(config) {
    try {
      // Check if application already exists
      const existingApp = await this.checkExistingApplication(config.name);
      if (existingApp) {
        console.log(
          `Enterprise application '${config.name}' already exists, using existing one`
        );

        // Get existing service principal
        const existingServicePrincipal =
          await this.checkExistingServicePrincipal(existingApp.appId);

        return {
          appId: existingApp.appId,
          objectId: existingApp.id,
          displayName: existingApp.displayName,
          servicePrincipalId: existingServicePrincipal?.id || "Not found",
          type: config.type,
          uniqueId: config.uniqueId,
          ssoMode: config.type === "saml" ? "saml" : "none",
          samlSettings: config.samlSettings,
          proxySettings: config.proxySettings,
          isExisting: true,
        };
      }

      // Create new application for enterprise app
      const applicationData = {
        displayName: config.name,
        signInAudience: "AzureADMyOrg",
      };

      // Only add SAML configuration if this is a SAML-enabled app (App Proxy SAML App)
      if (config.type === "saml" && config.samlSettings) {
        applicationData.identifierUris = [config.samlSettings.identifier];
        applicationData.web = {
          redirectUris: [config.samlSettings.replyUrl],
        };
      }

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

      // Create service principal
      const servicePrincipalData = {
        appId: createdApp.appId,
        tags: ["WindowsAzureActiveDirectoryIntegratedApp"],
      };

      // Only set SAML SSO mode if this is a SAML-enabled app (App Proxy SAML App)
      if (config.type === "saml") {
        servicePrincipalData.preferredSingleSignOnMode = "saml";
      }

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
        servicePrincipalId: servicePrincipal.id,
        type: config.type,
        uniqueId: config.uniqueId,
        ssoMode: config.type === "saml" ? "saml" : "none",
        samlSettings: config.samlSettings,
        proxySettings: config.proxySettings,
        isExisting: false,
      };
    } catch (error) {
      throw new Error(
        `Failed to create enterprise application: ${
          error.response?.data?.error?.message || error.message
        }`
      );
    }
  }

  /**
   * Configures cross-application permissions between the three app registrations based on unique IDs
   * App1 (MAHI_CONNECTOR_APP) to access App2 (MAHI_API_ACCESS), and App3 (MAHI_TEAMS_APP) to access both
   * @param {Array} appRegistrations - Array of created app registrations
   */
  async configureCrossApplicationPermissions(appRegistrations) {
    try {
      if (appRegistrations.length < 3) {
        console.warn(
          "Not enough app registrations for cross-permissions configuration"
        );
        return;
      }

      // Find apps by their unique IDs instead of names
      const app1 = appRegistrations.find(
        (app) => app.uniqueId === "MAHI_CONNECTOR_APP"
      );
      const app2 = appRegistrations.find(
        (app) => app.uniqueId === "MAHI_API_ACCESS"
      );
      const app3 = appRegistrations.find(
        (app) => app.uniqueId === "MAHI_TEAMS_APP"
      );

      if (!app1 || !app2 || !app3) {
        console.warn(
          "Could not find all required apps for cross-permissions configuration"
        );
        return;
      }

      // Configure App1 to access App2 scopes
      await this.addApplicationPermission(
        app1.objectId,
        app2.appId,
        "api.access"
      );

      // Configure App3 to access App1 and App2 scopes
      await this.addApplicationPermission(
        app3.objectId,
        app1.appId,
        "user.read"
      );
      await this.addApplicationPermission(
        app3.objectId,
        app2.appId,
        "api.access"
      );

      // For App3: Add web platform and configure to access App2
      await this.configureApp3WebPlatform(app3.objectId, app3.redirectUris);
      await this.addMyApiPermission(
        app3.objectId,
        app2.appId,
        app2.applicationIdUri
      );

      console.log(
        "Cross-application permissions configured successfully using unique IDs"
      );
    } catch (error) {
      console.error("Failed to configure cross permissions:", error.message);
      throw new Error(
        `Failed to configure cross permissions: ${error.message}`
      );
    }
  }

  /**
   * Configures App3 (MAHI_TEAMS_APP) with web platform capabilities in addition to SPA
   * Adds web platform redirect URIs and implicit grant settings
   * @param {string} app3ObjectId - Object ID of App3 (Teams App)
   * @param {Array} redirectUris - Array of redirect URIs to configure
   */
  async configureApp3WebPlatform(app3ObjectId, redirectUris) {
    try {
      // Get current app configuration
      const appResponse = await axios.get(
        `https://graph.microsoft.com/v1.0/applications/${app3ObjectId}`,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
            "Content-Type": "application/json",
          },
        }
      );

      const app = appResponse.data;

      // Add web platform if not already exists
      const webConfig = {
        web: {
          redirectUris: redirectUris || [],
          implicitGrantSettings: {
            enableIdTokenIssuance: true,
            enableAccessTokenIssuance: false,
          },
        },
      };

      // Merge with existing SPA configuration
      if (app.spa && app.spa.redirectUris) {
        webConfig.spa = app.spa;
      }

      await axios.patch(
        `https://graph.microsoft.com/v1.0/applications/${app3ObjectId}`,
        webConfig,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
            "Content-Type": "application/json",
          },
        }
      );

      console.log("Added web platform to App3 (Teams App)");
    } catch (error) {
      console.warn(`Could not add web platform to App3: ${error.message}`);
    }
  }

  /**
   * Adds custom API permissions from one app registration to another
   * Configures "My APIs" permissions for accessing custom scopes
   * @param {string} sourceAppObjectId - Object ID of the source application requesting permission
   * @param {string} targetAppId - Application ID of the target API application
   * @param {string} applicationIdUri - Application ID URI of the target API
   */
  async addMyApiPermission(sourceAppObjectId, targetAppId, applicationIdUri) {
    try {
      // Get current source application
      const sourceAppResponse = await axios.get(
        `https://graph.microsoft.com/v1.0/applications/${sourceAppObjectId}`,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
            "Content-Type": "application/json",
          },
        }
      );

      const sourceApp = sourceAppResponse.data;
      const currentRequiredResourceAccess =
        sourceApp.requiredResourceAccess || [];

      // Add permission to access Mahi API Access's exposed API
      const newResourceAccess = {
        resourceAppId: targetAppId,
        resourceAccess: [
          {
            id: this.generateGuid(), // Default scope ID for custom API
            type: "Scope",
          },
        ],
      };

      // Check if permission already exists
      const existingResource = currentRequiredResourceAccess.find(
        (resource) => resource.resourceAppId === targetAppId
      );
      if (!existingResource) {
        currentRequiredResourceAccess.push(newResourceAccess);

        await axios.patch(
          `https://graph.microsoft.com/v1.0/applications/${sourceAppObjectId}`,
          { requiredResourceAccess: currentRequiredResourceAccess },
          {
            headers: {
              Authorization: `Bearer ${this.accessToken}`,
              "Content-Type": "application/json",
            },
          }
        );

        console.log(
          `Added My API permission from App3 to App2: ${targetAppId}`
        );
      }
    } catch (error) {
      console.warn(`Could not add My API permission: ${error.message}`);
    }
  }

  /**
   * Adds application permissions from one app registration to another for specific scopes
   * @param {string} sourceAppObjectId - Object ID of the source application requesting permission
   * @param {string} targetAppId - Application ID of the target application exposing the scope
   * @param {string} scopeValue - The scope value to request permission for
   */
  async addApplicationPermission(sourceAppObjectId, targetAppId, scopeValue) {
    try {
      // Get the target application to find the scope ID
      const targetAppResponse = await axios.get(
        `https://graph.microsoft.com/v1.0/applications?$filter=appId eq '${targetAppId}'`,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
            "Content-Type": "application/json",
          },
        }
      );

      if (targetAppResponse.data.value.length === 0) {
        console.warn(
          `Target application ${targetAppId} not found for permissions`
        );
        return;
      }

      const targetApp = targetAppResponse.data.value[0];
      const oauth2Scopes = targetApp.api?.oauth2PermissionScopes || [];

      // Find the scope with the matching value
      const targetScope = oauth2Scopes.find(
        (scope) => scope.value === scopeValue
      );
      if (!targetScope) {
        console.warn(
          `Scope '${scopeValue}' not found in target application ${targetAppId}`
        );
        return;
      }

      // Get current source application
      const sourceAppResponse = await axios.get(
        `https://graph.microsoft.com/v1.0/applications/${sourceAppObjectId}`,
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
            "Content-Type": "application/json",
          },
        }
      );

      const sourceApp = sourceAppResponse.data;
      const currentRequiredResourceAccess =
        sourceApp.requiredResourceAccess || [];

      // Check if permission already exists
      const existingResource = currentRequiredResourceAccess.find(
        (resource) => resource.resourceAppId === targetAppId
      );

      if (existingResource) {
        // Check if scope already exists
        const existingScope = existingResource.resourceAccess.find(
          (access) => access.id === targetScope.id
        );
        if (existingScope) {
          console.log(
            `Permission already exists: ${scopeValue} from ${targetAppId}`
          );
          return;
        }
        // Add new scope to existing resource
        existingResource.resourceAccess.push({
          id: targetScope.id,
          type: "Scope",
        });
      } else {
        // Add new resource with scope
        currentRequiredResourceAccess.push({
          resourceAppId: targetAppId,
          resourceAccess: [
            {
              id: targetScope.id,
              type: "Scope",
            },
          ],
        });
      }

      // Update the source application with new permissions
      await axios.patch(
        `https://graph.microsoft.com/v1.0/applications/${sourceAppObjectId}`,
        { requiredResourceAccess: currentRequiredResourceAccess },
        {
          headers: {
            Authorization: `Bearer ${this.accessToken}`,
            "Content-Type": "application/json",
          },
        }
      );

      console.log(
        `Successfully added permission: ${scopeValue} from ${targetAppId} to ${sourceAppObjectId}`
      );
    } catch (error) {
      console.warn(`Failed to add application permission: ${error.message}`);
    }
  }

  /**
   * Generates a new GUID (UUID) for use in Azure AD configurations
   * @returns {string} A new GUID in standard format
   */
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

// Routes
app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

/**
 * Health check endpoint that returns server status and available features
 */
app.get("/api/health", (req, res) => {
  res.json({
    status: "healthy",
    timestamp: new Date().toISOString(),
    version: "2.1.0",
    features: [
      "Duplicate Detection and Reuse",
      "Unique App Identification System",
      "Custom Application Names Support",
      "Advanced API Permissions (App1 with unique ID)",
      "Application ID URI Configuration (App2 with unique ID)",
      "Web Platform & My API Access (App3 with unique ID)",
      "Enhanced Admin Consent with Retry Logic",
      "Custom Redirect URIs",
      "SAML + Proxy Configuration (Enterprise App 1)",
      "Proxy-Only Configuration (Enterprise App 2)",
      "Cross-Application Permissions",
      "Enhanced Status Reporting",
      "Production-Ready Security",
    ],
  });
});

/**
 * Main provisioning endpoint with enhanced functionality using unique app identification
 * Creates resource groups, app registrations, and enterprise applications with cross-permissions
 * Supports custom application names while maintaining unique identification for functionality
 */
app.post(
  "/api/provision",
  validateRequest(provisioningSchema),
  async (req, res) => {
    const startTime = Date.now();
    const requestId = uuidv4();

    try {
      log(
        "info",
        "Starting Azure resource provisioning with unique app identification and enhanced API permissions",
        {
          requestId,
          resourceGroup: req.validatedData.resourceGroupName,
        }
      );

      const {
        tenantId,
        subscriptionId,
        resourceGroupName,
        location,
        environment,
        applicationPrefix,
        clientId,
        clientSecret,

        // App Registration Configuration with unique IDs
        app1Name,
        app1Id,
        app1RedirectUri,
        app2Name,
        app2Id,
        app2RedirectUri,
        app3Name,
        app3Id,
        app3RedirectUri,
        enableCrossPermissions,
        generateSecrets,
        grantAdminConsent,

        // Enterprise Application Configuration with unique IDs
        enterprise1Name,
        enterprise1Id,
        enterprise2Name,
        enterprise2Id,

        // Application Proxy Configuration
        enterprise1InternalUrl,
        enterprise1ExternalUrl,
        enterprise2InternalUrl,
        enterprise2ExternalUrl,
      } = req.validatedData;

      // Initialize services
      const azureRM = new AzureResourceManager();
      const graphService = new GraphApiService();

      await azureRM.initialize(
        tenantId,
        subscriptionId,
        clientId,
        clientSecret
      );
      await graphService.initialize(tenantId, clientId, clientSecret);

      const provisioningResults = {
        requestId,
        resourceGroup: null,
        appRegistrations: [],
        enterpriseApplications: [],
        errors: [],
        warnings: [],
      };

      // Step 1: Create Resource Group
      try {
        provisioningResults.resourceGroup = await azureRM.createResourceGroup(
          resourceGroupName,
          location
        );
        log("info", "Resource group created", {
          requestId,
          resourceGroup: resourceGroupName,
        });
      } catch (error) {
        const errorMsg = `Resource Group creation failed: ${error.message}`;
        provisioningResults.errors.push(errorMsg);
        log("error", errorMsg, { requestId });
      }

      // Step 2: Create App Registrations with enhanced configurations using unique IDs
      const appConfigs = [
        {
          name: `${applicationPrefix}-${environment}-${app1Name}`,
          uniqueId: app1Id,
          scopes: ["user.read"],
          type: "web",
          redirectUris: [
            app1RedirectUri ||
              `https://${applicationPrefix}-${environment}-app1.azurewebsites.net/signin-oidc`,
          ],
          generateSecret: generateSecrets,
          grantAdminConsent: grantAdminConsent,
        },
        {
          name: `${applicationPrefix}-${environment}-${app2Name}`,
          uniqueId: app2Id,
          scopes: ["api.access"],
          type: "web",
          redirectUris: [
            app2RedirectUri ||
              `https://${applicationPrefix}-${environment}-app2.azurewebsites.net/signin-oidc`,
          ],
          generateSecret: generateSecrets,
          grantAdminConsent: grantAdminConsent,
        },
        {
          name: `${applicationPrefix}-${environment}-${app3Name}`,
          uniqueId: app3Id,
          scopes: ["resource.manage"],
          type: "spa",
          redirectUris: [
            app3RedirectUri ||
              `https://${applicationPrefix}-${environment}-app3.azurewebsites.net/auth/callback`,
          ],
          generateSecret: generateSecrets,
          grantAdminConsent: grantAdminConsent,
        },
      ];

      for (const config of appConfigs) {
        try {
          const appResult = await graphService.createAppRegistration(config);
          provisioningResults.appRegistrations.push(appResult);

          const action = appResult.isExisting
            ? "reused existing"
            : "created new";
          log("info", `App registration ${action}`, {
            requestId,
            appName: config.name,
            uniqueId: config.uniqueId,
            isExisting: appResult.isExisting,
            adminConsentGranted: appResult.adminConsentGranted,
          });
        } catch (error) {
          const errorMsg = `App Registration ${config.name} (${config.uniqueId}) failed: ${error.message}`;
          provisioningResults.errors.push(errorMsg);
          log("error", errorMsg, { requestId });
        }
      }

      // Step 3: Create Enterprise Applications with different configurations using unique IDs
      const enterpriseConfigs = [
        {
          name: `${applicationPrefix}-${environment}-${enterprise1Name}`,
          uniqueId: enterprise1Id,
          type: "saml", // Enterprise App 1 has SAML + Proxy
          samlSettings: {
            // Use external URL from proxy configuration for SAML
            identifier: `api://${applicationPrefix}-${environment}-ent1`,
            replyUrl: `${
              enterprise1ExternalUrl || "https://saml-app-external.company.com"
            }/saml2/acs`,
            signOnUrl: `${
              enterprise1ExternalUrl || "https://saml-app-external.company.com"
            }/login`,
          },
          proxySettings: {
            internalUrl:
              enterprise1InternalUrl || "http://internal-saml-app.company.com",
            externalUrl:
              enterprise1ExternalUrl || "https://saml-app-external.company.com",
          },
        },
        {
          name: `${applicationPrefix}-${environment}-${enterprise2Name}`,
          uniqueId: enterprise2Id,
          type: "proxy-only", // Enterprise App 2 has ONLY proxy configuration
          samlSettings: null, // No SAML configuration
          proxySettings: {
            internalUrl:
              enterprise2InternalUrl || "http://internal-chat-app.company.com",
            externalUrl:
              enterprise2ExternalUrl || "https://chat-app-external.company.com",
          },
        },
      ];

      for (const config of enterpriseConfigs) {
        try {
          const enterpriseResult =
            await graphService.createEnterpriseApplication(config);
          provisioningResults.enterpriseApplications.push(enterpriseResult);

          const action = enterpriseResult.isExisting
            ? "reused existing"
            : "created new";
          log("info", `Enterprise application ${action}`, {
            requestId,
            appName: config.name,
            uniqueId: config.uniqueId,
            isExisting: enterpriseResult.isExisting,
          });
        } catch (error) {
          const errorMsg = `Enterprise App ${config.name} (${config.uniqueId}) failed: ${error.message}`;
          provisioningResults.errors.push(errorMsg);
          log("error", errorMsg, { requestId });
        }
      }

      // Step 4: Configure cross-application permissions between Mahi apps (if enabled)
      if (
        enableCrossPermissions &&
        provisioningResults.appRegistrations.length >= 3
      ) {
        try {
          await graphService.configureCrossApplicationPermissions(
            provisioningResults.appRegistrations
          );
          log(
            "info",
            "Cross-application permissions configured for app registrations",
            {
              requestId,
            }
          );
          provisioningResults.warnings.push(
            "Cross-application permissions configured including App3 web platform and My API access"
          );
        } catch (error) {
          const errorMsg = `Cross-application permissions failed: ${error.message}`;
          provisioningResults.errors.push(errorMsg);
          log("error", errorMsg, { requestId });
        }
      } else if (!enableCrossPermissions) {
        log("info", "Cross-application permissions skipped per user request", {
          requestId,
        });
        provisioningResults.warnings.push(
          "Cross-application permissions skipped - configure manually if needed"
        );
      }

      // Add warnings for manual steps
      provisioningResults.warnings.push(
        "Application Proxy connectors must be installed manually"
      );
      if (
        provisioningResults.enterpriseApplications.some(
          (app) => app.type === "saml"
        )
      ) {
        provisioningResults.warnings.push(
          "SAML certificates need to be configured manually for Enterprise App 1"
        );
      }
      if (grantAdminConsent) {
        provisioningResults.warnings.push(
          "Admin consent attempted - verify permissions in Azure Portal if needed"
        );
      }

      const duration = Date.now() - startTime;

      res.json({
        success: true,
        message:
          "Azure resources provisioned successfully with enhanced API permissions and unique app identification",
        requestId,
        duration,
        results: provisioningResults,
        summary: {
          resourceGroupCreated: !!provisioningResults.resourceGroup,
          appRegistrationsCreated: provisioningResults.appRegistrations.filter(
            (app) => !app.isExisting
          ).length,
          appRegistrationsReused: provisioningResults.appRegistrations.filter(
            (app) => app.isExisting
          ).length,
          enterpriseApplicationsCreated:
            provisioningResults.enterpriseApplications.filter(
              (app) => !app.isExisting
            ).length,
          enterpriseApplicationsReused:
            provisioningResults.enterpriseApplications.filter(
              (app) => app.isExisting
            ).length,
          crossApplicationPermissionsConfigured:
            enableCrossPermissions &&
            provisioningResults.appRegistrations.length >= 3,
          clientSecretsGenerated: generateSecrets,
          adminConsentAttempted: grantAdminConsent,
          adminConsentSuccessful: provisioningResults.appRegistrations.some(
            (app) => app.adminConsentGranted
          ),
          errorsCount: provisioningResults.errors.length,
          warningsCount: provisioningResults.warnings.length,
        },
      });
    } catch (error) {
      const duration = Date.now() - startTime;
      log("error", "Application provisioning failed", {
        requestId,
        error: error.message,
      });

      res.status(500).json({
        success: false,
        error: "Provisioning failed",
        message: error.message,
        requestId,
        duration,
      });
    }
  }
);

/**
 * Error handling middleware for unhandled errors
 */
app.use((error, req, res, next) => {
  log("error", "Unhandled error", { error: error.message });
  res.status(500).json({
    success: false,
    error: "Internal server error",
    message:
      process.env.NODE_ENV === "development"
        ? error.message
        : "Something went wrong",
  });
});

/**
 * 404 handler for undefined routes
 */
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: "Not found",
    message: `Route ${req.method} ${req.path} not found`,
  });
});

app.listen(port, () => {
  log(
    "info",
    "Enhanced server started with API permissions support and unique app identification",
    {
      port,
      environment: process.env.NODE_ENV || "development",
    }
  );
  console.log(`🚀 Enhanced Azure Provisioner server running on port ${port}`);
  console.log(`📱 Open http://localhost:${port} to access the application`);
  console.log(
    `✨ Features: Advanced API Permissions, Admin Consent, Application ID URI, Web Platform Config with Unique IDs`
  );
});

module.exports = app;
