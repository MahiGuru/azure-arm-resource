// server.js - Final Complete Version with All Features
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

// Complete validation schema with all fields
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

  // App Registration Configuration
  app1Name: Joi.string()
    .min(1)
    .max(50)
    .pattern(/^[a-zA-Z0-9-_]+$/)
    .default("app-reg-1"),
  app1RedirectUri: Joi.string().uri().optional(),
  app2Name: Joi.string()
    .min(1)
    .max(50)
    .pattern(/^[a-zA-Z0-9-_]+$/)
    .default("app-reg-2"),
  app2RedirectUri: Joi.string().uri().optional(),
  app3Name: Joi.string()
    .min(1)
    .max(50)
    .pattern(/^[a-zA-Z0-9-_]+$/)
    .default("app-reg-3"),
  app3RedirectUri: Joi.string().uri().optional(),
  enableCrossPermissions: Joi.string()
    .valid("true", "false")
    .default("true")
    .custom((value) => value === "true"),
  generateSecrets: Joi.string()
    .valid("true", "false")
    .default("true")
    .custom((value) => value === "true"),

  // Enterprise Application Configuration
  enterprise1Name: Joi.string()
    .min(1)
    .max(50)
    .pattern(/^[a-zA-Z0-9-_]+$/)
    .default("enterprise-app-1"),
  enterprise2Name: Joi.string()
    .min(1)
    .max(50)
    .pattern(/^[a-zA-Z0-9-_]+$/)
    .default("enterprise-app-2"),

  // Application Proxy Configuration
  internalUrl1: Joi.string().uri().optional(),
  externalUrl1: Joi.string().uri().optional(),
  internalUrl2: Joi.string().uri().optional(),
  externalUrl2: Joi.string().uri().optional(),
});

// Validation middleware
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

// Logging utility
function log(level, message, data = {}) {
  const logEntry = {
    timestamp: new Date().toISOString(),
    level,
    message,
    ...data,
  };
  console.log(JSON.stringify(logEntry));
}

// Azure Resource Manager class
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
}

// Graph API Service class with complete functionality
class GraphApiService {
  constructor() {
    this.accessToken = null;
    this.credential = null;
  }

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
          isExisting: true,
        };
      }

      // Create new application
      const applicationData = {
        displayName: config.name,
        signInAudience: "AzureADMyOrg",
        requiredResourceAccess: [
          {
            resourceAppId: "00000003-0000-0000-c000-000000000000",
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

      return {
        appId: createdApp.appId,
        objectId: createdApp.id,
        displayName: createdApp.displayName,
        clientSecret: clientSecret.secretText,
        servicePrincipalId: servicePrincipal.id,
        redirectUris: config.redirectUris,
        type: config.type,
        isExisting: false,
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

      // Only add SAML configuration if this is a SAML-enabled app
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

      // Only set SAML SSO mode if this is a SAML-enabled app
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

  async configureCrossApplicationPermissions(appRegistrations) {
    try {
      if (appRegistrations.length < 3) {
        console.warn(
          "Not enough app registrations for cross-permissions configuration"
        );
        return;
      }

      const [app1, app2, app3] = appRegistrations;

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

      console.log("Cross-application permissions configured successfully");
    } catch (error) {
      console.error("Failed to configure cross permissions:", error.message);
      throw new Error(
        `Failed to configure cross permissions: ${error.message}`
      );
    }
  }

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

app.get("/api/health", (req, res) => {
  res.json({
    status: "healthy",
    timestamp: new Date().toISOString(),
    version: "2.0.0",
    features: [
      "Duplicate Detection and Reuse",
      "Configurable App Registration Names",
      "Custom Redirect URIs",
      "SAML + Proxy Configuration",
      "Cross-Application Permissions",
      "Enhanced Status Reporting",
      "Domain Verification Fix",
      "Production-Ready Security",
    ],
  });
});

// Main provisioning endpoint with complete functionality
app.post(
  "/api/provision",
  validateRequest(provisioningSchema),
  async (req, res) => {
    const startTime = Date.now();
    const requestId = uuidv4();

    try {
      log("info", "Starting Azure resource provisioning", {
        requestId,
        resourceGroup: req.validatedData.resourceGroupName,
      });

      const {
        tenantId,
        subscriptionId,
        resourceGroupName,
        location,
        environment,
        applicationPrefix,
        clientId,
        clientSecret,

        // App Registration Configuration
        app1Name,
        app1RedirectUri,
        app2Name,
        app2RedirectUri,
        app3Name,
        app3RedirectUri,
        enableCrossPermissions,
        generateSecrets,

        // Enterprise Application Configuration
        enterprise1Name,
        enterprise2Name,

        // Application Proxy Configuration
        internalUrl1,
        externalUrl1,
        internalUrl2,
        externalUrl2,
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

      // Step 2: Create App Registrations with custom configuration
      const appConfigs = [
        {
          name: `${applicationPrefix}-${environment}-${app1Name}`,
          scopes: ["user.read"],
          type: "web",
          redirectUris: [
            app1RedirectUri ||
              `https://${applicationPrefix}-${environment}-app1.azurewebsites.net/signin-oidc`,
          ],
          generateSecret: generateSecrets,
        },
        {
          name: `${applicationPrefix}-${environment}-${app2Name}`,
          scopes: ["api.access"],
          type: "web",
          redirectUris: [
            app2RedirectUri ||
              `https://${applicationPrefix}-${environment}-app2.azurewebsites.net/signin-oidc`,
          ],
          generateSecret: generateSecrets,
        },
        {
          name: `${applicationPrefix}-${environment}-${app3Name}`,
          scopes: ["resource.manage"],
          type: "spa",
          redirectUris: [
            app3RedirectUri ||
              `https://${applicationPrefix}-${environment}-app3.azurewebsites.net/auth/callback`,
          ],
          generateSecret: generateSecrets,
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
            isExisting: appResult.isExisting,
          });
        } catch (error) {
          const errorMsg = `App Registration ${config.name} failed: ${error.message}`;
          provisioningResults.errors.push(errorMsg);
          log("error", errorMsg, { requestId });
        }
      }

      // Step 3: Create Enterprise Applications with different configurations
      const enterpriseConfigs = [
        {
          name: `${applicationPrefix}-${environment}-${enterprise1Name}`,
          type: "saml", // This one has SAML + Proxy
          samlSettings: {
            // Use external URL from proxy configuration for SAML
            identifier: `api://${applicationPrefix}-${environment}-ent1`,
            replyUrl: `${
              externalUrl1 || "https://app1-external.company.com"
            }/saml2/acs`,
            signOnUrl: `${
              externalUrl1 || "https://app1-external.company.com"
            }/login`,
          },
          proxySettings: {
            internalUrl: internalUrl1 || "http://internal-app1.company.com",
            externalUrl: externalUrl1 || "https://app1-external.company.com",
          },
        },
        {
          name: `${applicationPrefix}-${environment}-${enterprise2Name}`,
          type: "proxy-only", // This one has ONLY proxy configuration
          samlSettings: null, // No SAML configuration
          proxySettings: {
            internalUrl: internalUrl2 || "http://internal-app2.company.com",
            externalUrl: externalUrl2 || "https://app2-external.company.com",
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
            isExisting: enterpriseResult.isExisting,
          });
        } catch (error) {
          const errorMsg = `Enterprise App ${config.name} failed: ${error.message}`;
          provisioningResults.errors.push(errorMsg);
          log("error", errorMsg, { requestId });
        }
      }

      // Step 4: Configure cross-application permissions (if enabled)
      if (
        enableCrossPermissions &&
        provisioningResults.appRegistrations.length >= 3
      ) {
        try {
          await graphService.configureCrossApplicationPermissions(
            provisioningResults.appRegistrations
          );
          log("info", "Cross-application permissions configured", {
            requestId,
          });
          provisioningResults.warnings.push(
            "Cross-application permissions configured - admin consent may be required"
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
      provisioningResults.warnings.push(
        "Admin consent required for API permissions"
      );

      const duration = Date.now() - startTime;

      res.json({
        success: true,
        message: "Azure resources provisioned successfully",
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
          errorsCount: provisioningResults.errors.length,
          warningsCount: provisioningResults.warnings.length,
        },
      });
    } catch (error) {
      const duration = Date.now() - startTime;
      log("error", "Provisioning failed", { requestId, error: error.message });

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

// Error handling middleware
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

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: "Not found",
    message: `Route ${req.method} ${req.path} not found`,
  });
});

app.listen(port, () => {
  log("info", "Server started", {
    port,
    environment: process.env.NODE_ENV || "development",
  });
  console.log(`🚀 Azure Provisioner server running on port ${port}`);
  console.log(`📱 Open http://localhost:${port} to access the application`);
  console.log(
    `✨ Features: Duplicate Detection, Custom App Config, SAML+Proxy, Cross-Permissions`
  );
});

module.exports = app;
