@description('The type of k8s node')
@allowed([
  'worker'
  'master'
])
param nodeType string

@description('Tags to apply to deployed resources.')
param deploymentTags object = {}

@description('The unique name of your deployment.')
param deploymentName string

@description('Username for the Virtual Machine.')
param adminUsername string

@description('SSH Key for the Virtual Machine.')
@secure()
param adminSshKey string


@description('The Ubuntu version for the VM. This will pick a fully patched image of this given Ubuntu version.')
@allowed([
  '18.04-LTS'
])
param ubuntuOSVersion string = '18.04-LTS'

@description('Location for all resources.')
param deployRegion string

@description('The size of the VM')
param vmSize string = 'Standard_D2_v5' // recommended 2VCPU & 8GB 

@description('Resource ID of the target virtual networ subnet.')
param subnetId string

@description('Unique identifier for the VM. To differentiate between multiple worker/master nodes.')
param vmIdentifier string = ''

@description('Configuration to auto shutdown the VM on a schedule. Defaults to false. Time is in 24 hour notation.')
param autoShutdownOptions object = {
  enabled: false
  time: '1700'
  timeZoneId: 'Eastern Standard Time'
}

var vmName = '${deploymentName}${nodeType}${vmIdentifier}'


var publicIPAddressName = '${vmName}-PublicIP'
var networkInterfaceName = '${vmName}-NetInt'
var osDiskType = 'Standard_LRS'
var networkSecurityGroupName = 'SecGroupNet'

resource nsg 'Microsoft.Network/networkSecurityGroups@2020-06-01' = {
  name: networkSecurityGroupName
  location: deployRegion
  tags: deploymentTags
  properties: {
    securityRules: [
      {
        name: 'SSH'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

resource publicIP 'Microsoft.Network/publicIPAddresses@2020-06-01' = {
  name: publicIPAddressName
  location: deployRegion
  tags: deploymentTags
  sku: {
    name: 'Basic'
  }
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: toLower(vmName)
    }
    idleTimeoutInMinutes: 4
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: networkInterfaceName
  location: deployRegion
  tags: deploymentTags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIP.id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}




resource vm 'Microsoft.Compute/virtualMachines@2020-06-01' = {
  name: vmName
  location: deployRegion
  tags: deploymentTags
  properties: {
    
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskType
        }
      }
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: ubuntuOSVersion
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminSshKey
            }
          ]
        }
      }
    }
  }
}

resource autoshutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = if (autoShutdownOptions.enabled) {
  name: 'shutdown-computevm-${vmName}'
  location: deployRegion
  tags: deploymentTags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoShutdownOptions.time
    }
    timeZoneId: autoShutdownOptions.timeZoneId
    targetResourceId: vm.id
  }
}

output adminUsername string = adminUsername
output hostname string = publicIP.properties.dnsSettings.fqdn
output sshCommand string = 'ssh ${adminUsername}@${publicIP.properties.dnsSettings.fqdn}'
