/*
This deploys the worker & master nodes necessary for the Certified Kubernetes Developer training
provided by the Linux Academy.
Still todo:
- Private cluster with Jumbox VM
*/


@description('Location for all resources.')
param deployRegion string = resourceGroup().location

@description('Tags to apply to deployed resources.')
param deploymentTags object = {}

@description('The unique name of your deployment.')
param deploymentName string = 'ckadScenario'

@description('Additional KeyVault users. Needs to include the user principal id deploying the module.')
param keyVaultUserPrincipalIds array = []

@description('Name of the VNET.')
param virtualNetworkName string = '${deploymentName}-vnet'

@description('Username for the Virtual Machine.')
param vmAdminUsername string = 'ckadAdmin'

// Secret & Identity config
var keyVaultName = '${deploymentName}-kv'
var identityName = '${deploymentName}-identity'
var sshKeyPrefix = deploymentName
var additionalKeyVaultUserConfigs = [for principalId in keyVaultUserPrincipalIds: {
  objectId: principalId
  tenantId: subscription().tenantId
  permissions: {
    secrets: [
      'get'
      'list'
      'set'
    ]
  }
}]

// Networking
var vmSubnetAddressPrefix = '10.1.0.0/24'
var vmSubnet = 'k8s-workloads'
var addressPrefix = '10.1.0.0/16'

/*
  Identity allows script access to KeyVault.
*/
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: identityName
  location: deployRegion
  tags: deploymentTags
}


resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: virtualNetworkName
  location: deployRegion
  tags: deploymentTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: vmSubnet
          properties: {
            addressPrefix: vmSubnetAddressPrefix
            privateEndpointNetworkPolicies: 'Enabled'
            privateLinkServiceNetworkPolicies: 'Enabled'
          }
      }
    ]
  }
}

/*
  Key Vault is used to host public & private SSH keypair for k8s nodes.
*/
resource keyVault 'Microsoft.KeyVault/vaults@2021-11-01-preview' = {
  location: deployRegion
  name: keyVaultName
  tags: deploymentTags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    accessPolicies: concat(additionalKeyVaultUserConfigs, array({
      objectId: identity.properties.principalId
      tenantId: subscription().tenantId
      permissions: {
        secrets: [
          'get'
          'list'
          'set'
        ]
      }
    }))
    enabledForTemplateDeployment: true
    enabledForDeployment: true
  }
}

module createSshKeys '../bicep/add-or-get-kv-sshkey.bicep' = {
  name: 'createSshKeypair'
  dependsOn: [
    keyVault
  ]
  params: {
    secretTags: deploymentTags
    deployRegion: deployRegion
    secretName: sshKeyPrefix
    vaultName: keyVault.name
    keyType: 'rsa'
    identityId: identity.id
  }
}


module createMasterNode './k8s-vm.bicep' = {
  name: 'createMasterNode'
  dependsOn: [
    keyVault //! Bicep will compolain this isn't needed. It is for the getSecret method below.
    createSshKeys
  ]
  params: {
    nodeType: 'master'
    deploymentTags: deploymentTags
    deploymentName: deploymentName
    adminUsername: vmAdminUsername
    adminSshKey: keyVault.getSecret(createSshKeys.outputs.publicKeySecretName)  
    subnetId: vnet.properties.subnets[0].id
    deployRegion: deployRegion
    autoShutdownOptions: {
      enabled: true
      time: '1700' // 5pm
      timeZoneId: 'Eastern Standard Time'
    }
  }
}

module createWorkerNode './k8s-vm.bicep' = {
  name: 'createWorkerNode'
  dependsOn: [
    keyVault //! Bicep will compolain this isn't needed. It is for the getSecret method below.
    createSshKeys
  ]
  params: {
    nodeType: 'worker'
    deploymentTags: deploymentTags
    deploymentName: deploymentName
    adminUsername: vmAdminUsername
    adminSshKey: keyVault.getSecret(createSshKeys.outputs.publicKeySecretName)
    subnetId: vnet.properties.subnets[0].id
    deployRegion: deployRegion
    autoShutdownOptions: {
      enabled: true
      time: '1700' // 5pm
      timeZoneId: 'Eastern Standard Time'
    }
  }
}
