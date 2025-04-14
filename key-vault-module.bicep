@description('Name of the Key Vault')
param keyVaultName string = 'cribl-kv-${uniqueString(resourceGroup().id)}'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Object ID of the VM managed identity')
param vmIdentityObjectId string

@description('Enable RBAC authorization for Key Vault')
param enableRbacAuthorization bool = true

@description('Cribl Admin Password')
@secure()
param criblAdminPassword string

@description('Cribl License Key (optional)')
@secure()
param criblLicenseKey string = ''

@description('Specifies whether Azure Virtual Machines are permitted to retrieve certificates stored as secrets from the vault.')
param enabledForDeployment bool = true

@description('Specifies whether Azure Resource Manager is permitted to retrieve secrets from the vault.')
param enabledForTemplateDeployment bool = true

// Create Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2021-11-01-preview' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: enableRbacAuthorization
    enabledForDeployment: enabledForDeployment
    enabledForTemplateDeployment: enabledForTemplateDeployment
    accessPolicies: !enableRbacAuthorization ? [
      {
        tenantId: subscription().tenantId
        objectId: vmIdentityObjectId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ] : []
  }
}

// Store admin password in Key Vault
resource adminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'criblAdminPassword'
  properties: {
    value: criblAdminPassword
  }
}

// Store license key in Key Vault if provided
resource licenseKeySecret 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = if (!empty(criblLicenseKey)) {
  parent: keyVault
  name: 'criblLicenseKey'
  properties: {
    value: criblLicenseKey
  }
}

// Assign Key Vault Reader role to VM managed identity if using RBAC
resource keyVaultReaderRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = if (enableRbacAuthorization) {
  scope: keyVault
  name: guid(keyVault.id, vmIdentityObjectId, 'KeyVaultReader')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Reader
    principalId: vmIdentityObjectId
    principalType: 'ServicePrincipal'
  }
}

// Assign Key Vault Secrets User role to VM managed identity if using RBAC
resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = if (enableRbacAuthorization) {
  scope: keyVault
  name: guid(keyVault.id, vmIdentityObjectId, 'KeyVaultSecretsUser')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: vmIdentityObjectId
    principalType: 'ServicePrincipal'
  }
}

output keyVaultName string = keyVault.name
output keyVaultId string = keyVault.id
output adminPasswordSecretUri string = adminPasswordSecret.properties.secretUri
output licenseKeySecretUri string = !empty(criblLicenseKey) ? licenseKeySecret.properties.secretUri : ''
