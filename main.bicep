targetScope = 'subscription'
@description('Location for the deployment')
param location string = deployment().location

var random = uniqueString(subscription().id)
var prefix = 'viedoc-ctms-bridge-'

var resourceGroupName = '${prefix}${random}'
var defaultName = '${prefix}${random}'
var storageAccountName = take(toLower(replace('${defaultName}','-','')),23)
var fileShareName = 'data'
var workspaceName = '${defaultName}-log-analytics'
var applicationInsightsName = '${defaultName}-insights'
var appServicePlanName = '${defaultName}-farm'
var functionAppName = defaultName

resource rg 'Microsoft.Resources/resourceGroups@2021-01-01' = {
  name: resourceGroupName
  location: location
}

module infrastructure 'infrastructure.bicep'= {
  name: '${prefix}infrastructure-module'
  scope: rg
  params:{
    storageAccountName: storageAccountName
    fileShareName: fileShareName
    workspaceName: workspaceName
    applicationInsightsName: applicationInsightsName
    location: location
    appServicePlanName: appServicePlanName
    functionAppName: functionAppName
  }
}

output resourceGroupName string = rg.name
output storageAccountName string = infrastructure.outputs.storageAccountName
output storageAccountId string = infrastructure.outputs.storageAccountId
output url string = 'https://${infrastructure.outputs.defaultHostName}'
