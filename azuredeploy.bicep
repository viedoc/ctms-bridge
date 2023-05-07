@description('Resource group location')
param location string = resourceGroup().location

var random = uniqueString(subscription().id)
var prefix = 'viedoc-ctms-bridge-'

@secure()
param ViedocApiClientId string = '92ac892a-f27c-4931-b9bc-1f4f66e30743'
@secure()
param ViedocApiClientSecret string = 'bV_tWwfjrVgdaOHm8jTO9aSZtisrkTw8u2kokfZrxFw'

param ViedocApiUrl string = 'https://externaltest4api.viedoc.net'
param ViedocApiTokenUrl string = 'https://externaltest4sts.viedoc.net/connect/token'

param secret1Name string = 'BsiClientId'
@secure()
param secret1Value string = 'ctms_api_user'

param secret2Name string = 'BsiClientSecret'
@secure()
param secret2Value string = '62lmGf$gfK!a27Fmgd'

var defaultName = '${prefix}${random}'
var storageAccountName = take(toLower(replace('${defaultName}', '-', '')), 23)
var fileShareName = 'data'
var workspaceName = '${defaultName}-log-analytics'
var applicationInsightsName = '${defaultName}-insights'
var keyVaultName = 'v-${random}-vault'
var appServicePlanName = '${defaultName}-farm'
var functionAppName = defaultName

// Storage account
resource sa 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  parent: sa
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      allowPermanentDelete: false
      enabled: false
    }
  }
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2022-09-01' = {
  name: 'default'
  parent: sa
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2022-09-01' = {
  name: fileShareName
  parent: fileService
}

// Log analytics workspace
resource workspace 'Microsoft.OperationalInsights/workspaces@2020-10-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

// Application insights
resource ai 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    RetentionInDays: 90
    IngestionMode: 'LogAnalytics'
    WorkspaceResourceId: workspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Key vault
resource keyVault 'Microsoft.KeyVault/vaults@2021-11-01-preview' = {
  name: keyVaultName
  location: location
  properties: {
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    tenantId: subscription().tenantId
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: true
    accessPolicies: []
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource apiClientIdSecret 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'viedoc-api-client-id'
  properties: {
    value: secret1Value
  }
}

resource apiClientSecretSecret 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'viedoc-api-client-secret'
  properties: {
    value: secret1Value
  }
}

var userSecrets = [
  {
    name: 'UserSecret__${secret1Name}'
    value: secret1Value
  }
  {
    name: 'UserSecret__${secret2Name}'
    value: secret2Value
  }
]

resource userSecretsSecrets1 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' =  {
  parent: keyVault
  name: toLower(replace(userSecrets[0].name,'__','-'))
  properties: {
    value: userSecrets[0].value
  }
}
resource userSecretsSecrets2 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' =  {
  parent: keyVault
  name: toLower(replace(userSecrets[1].name,'__','-'))
  properties: {
    value: userSecrets[1].value
  }
}


// Server farm
resource plan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  kind: 'linux'
  properties: {
    reserved: true

  }
  sku: {
    name: 'B1'
  }
}

// Function app
var storageAccountKey = sa.listKeys().keys[1].value
var storageAccountConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${sa.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccountKey}'
var alwaysOn = true

resource func 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  kind: 'functionapplinux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    enabled: true
    reserved: true
    isXenon: false
    hyperV: false
    vnetRouteAllEnabled: false
    vnetImagePullEnabled: false
    vnetContentShareEnabled: false
    siteConfig: {
      linuxFxVersion: 'DOTNET-ISOLATED|7.0'
      numberOfWorkers: 1
      acrUseManagedIdentityCreds: false
      alwaysOn: alwaysOn
      http20Enabled: true
      functionAppScaleLimit: 2
      minimumElasticInstanceCount: 0
      appSettings: [
          {
            name: userSecrets[0].name
            value: '@Microsoft.KeyVault(SecretUri=${userSecretsSecrets1.properties.secretUri})'
          }
          {
            name: userSecrets[1].name
            value: '@Microsoft.KeyVault(SecretUri=${userSecretsSecrets2.properties.secretUri})'
          }
          {
            name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
            value: ai.properties.ConnectionString
          }
          {
            name: 'AzureWebJobsStorage'
            value: storageAccountConnectionString
          }
          {
            name: 'FUNCTIONS_EXTENSION_VERSION'
            value: '~4'
          }
          {
            name: 'FUNCTIONS_WORKER_RUNTIME'
            value: 'dotnet-isolated'
          }
          {
            name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
            value: storageAccountConnectionString
          }
          {
            name: 'WEBSITE_CONTENTSHARE'
            value: functionAppName
          }
          {
            name: 'WEBSITE_MOUNT_ENABLED'
            value: '1'
          }
          {
            name: 'WEBSITE_RUN_FROM_PACKAGE'
            value: 'https://github.com/viedoc/ctms-bridge/releases/download/0.0.1/viedoc-ctms-bridge-20230507093712.zip'
          }
          {
            name: 'DataBridge__AppSettingsFile'
            value: 'appsettings.json'
          }
          {
            name: 'DataBridge__BasePath'
            value: '/data'
          }
          {
            name: 'DataBridge__ExportConsoleExecutable'
            value: 'Viedoc.Export.Console'
          }
          {
            name: 'DataBridge__ExportConsoleExecutableFolder'
            value: ''
          }
          {
            name: 'DataBridge__MappingsFolder'
            value: ''
          }
          {
            name: 'DataBridge__SyncInterval'
            value: '0 */20 * * * *'
          }
          {
            name: 'ViedocExportConsole__ClientId'
            value: '@Microsoft.KeyVault(SecretUri=${apiClientIdSecret.properties.secretUri})'
          }
          {
            name: 'ViedocExportConsole__ClientSecret'
            value: '@Microsoft.KeyVault(SecretUri=${apiClientSecretSecret.properties.secretUri})'
          }
          {
            name: 'ViedocExportConsole__ApiUrl'
            value: ViedocApiUrl
          }
          {
            name: 'ViedocExportConsole__TokenUrl'
            value: ViedocApiTokenUrl
          }
        ]
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: false
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    httpsOnly: true
    redundancyMode: 'None'
    storageAccountRequired: false
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
  dependsOn: [
  ]
}

resource func_config 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: func
  name: 'web'
  properties: {
    linuxFxVersion: 'DOTNET-ISOLATED|7.0'
    numberOfWorkers: 1
    netFrameworkVersion: 'v4.0'
    requestTracingEnabled: false
    remoteDebuggingEnabled: false
    httpLoggingEnabled: false
    detailedErrorLoggingEnabled: false
    use32BitWorkerProcess: false
    webSocketsEnabled: false
    alwaysOn: alwaysOn
    loadBalancing: 'LeastRequests'
    autoHealEnabled: false
    vnetRouteAllEnabled: false
    vnetPrivatePortsCount: 0
    localMySqlEnabled: false
    scmIpSecurityRestrictionsUseMain: false
    http20Enabled: true
    minTlsVersion: '1.2'
    scmMinTlsVersion: '1.2'
    ftpsState: 'Disabled'
    preWarmedInstanceCount: 0
    functionAppScaleLimit: 2
    functionsRuntimeScaleMonitoringEnabled: false
    minimumElasticInstanceCount: 0
  }
}

resource storageSetting 'Microsoft.Web/sites/config@2021-01-15' = {
  name: 'azurestorageaccounts'
  parent: func
  properties: {
    '${fileShareName}': {
      type: 'AzureFiles'
      shareName: fileShareName
      mountPath: '/data'
      accountName: sa.name
      accessKey: storageAccountKey
    }
  }
}

var KEY_VAULT_SECRETS_USER_ROLE_GUID = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

resource keyVaultWebsiteUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('SecretsUser', func.name)
  scope: keyVault
  properties: {
    principalId: func.identity.principalId
    roleDefinitionId: KEY_VAULT_SECRETS_USER_ROLE_GUID
  }
}

// Deployment script
// Uploads viedoc.export.console to the newly created storage account
resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'deployscript-upload-blob'
  location: location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '7.0'
    timeout: 'PT5M'
    retentionInterval: 'PT1H'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      {
        name: 'FILESHARE_URL'
        secureValue: 'https://${storageAccountName}.file.${environment().suffixes.storage}/${fileShareName}'
      }
      {
        name: 'AZURE_STORAGE_KEY'
        secureValue: storageAccountKey
      }
      {
        name: 'AZURE_STORAGE_ACCOUNT'
        secureValue: storageAccountName
      }
      {
        name: 'SHARE_NAME'
        secureValue: fileShareName
      }
    ]
    scriptContent: '''
    Invoke-WebRequest "https://github.com/viedoc/Viedoc.Export.Console/releases/download/0.0.1/viedoc.export.console-linux-x64.zip" -OutFile "viedoc.export.console.zip"
    Expand-Archive -Path "viedoc.export.console.zip" -DestinationPath "." -Force
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash
    az version
    az storage file upload --source "./Viedoc.Export.Console" --share-name "$($env:SHARE_NAME)" 
    Write-Host "Done"
    '''
  }
  dependsOn: [
    fileShare
  ]
}

output storageAccountName string = storageAccountName
output storageAccountId string = sa.id
output url string = 'https://${func.properties.defaultHostName}'
