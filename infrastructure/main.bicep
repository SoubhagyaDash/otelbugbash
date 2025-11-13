@description('Azure region for resources')
param location string = resourceGroup().location

@description('Admin username for VM')
param adminUsername string = 'azureuser'

@description('SSH public key for VM access')
@secure()
param sshPublicKey string

@description('Name prefix for resources')
param namePrefix string = 'otelbugbash'

@description('ACR name (must be globally unique, alphanumeric only)')
param acrName string = '${namePrefix}acr${uniqueString(resourceGroup().id)}'

@description('VM size for the virtual machine')
param vmSize string = 'Standard_B2s'

@description('VM size for AKS nodes')
param aksNodeSize string = 'Standard_B2s'

// Variables
var vmName = '${namePrefix}-vm'
var aksName = '${namePrefix}-aks'
var vnetName = '${namePrefix}-vnet'
var nsgName = '${namePrefix}-nsg'
var publicIpName = '${namePrefix}-pip'
var nicName = '${namePrefix}-nic'
var aksNodeCount = 2
var adminPassword = 'OtelBugBash2025!'

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'vm-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
      {
        name: 'aks-subnet'
        properties: {
          addressPrefix: '10.0.2.0/23'
        }
      }
    ]
  }
}

// Network Security Group
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowHTTP'
        properties: {
          priority: 1001
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5000'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// Public IP for VM
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${namePrefix}-${uniqueString(resourceGroup().id)}'
    }
  }
}

// Network Interface
resource nic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/vm-subnet'
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

// Virtual Machine
resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: location
  tags: {
    SkipLinuxAzSecPack: 'True'
    SkipASMAzSecPack: 'True'
    SkipWindowsAzSecPack: 'True'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

// Azure Monitor Linux Agent Extension
resource vmAzureMonitorAgent 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = {
  parent: vm
  name: 'AzureMonitorLinuxAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    settings: {
      azureMonitorConfiguration: {
        enable: true
      }
      genevaConfiguration: {
        enable: false
      }
    }
  }
}

// Note: Docker and application setup is done via SSH in deploy-all.sh/ps1
// This avoids flaky custom script extensions and provides better error handling

// Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
  }
}

// AKS Cluster
resource aks 'Microsoft.ContainerService/managedClusters@2023-08-01' = {
  name: aksName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: aksName
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: aksNodeCount
        vmSize: aksNodeSize
        osType: 'Linux'
        mode: 'System'
        vnetSubnetID: '${vnet.id}/subnets/aks-subnet'
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      serviceCidr: '10.1.0.0/16'
      dnsServiceIP: '10.1.0.10'
    }
  }
}

// Role assignment to allow AKS to pull from ACR
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aks.id, acr.id, 'acrpull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull role
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output vmPublicIp string = publicIp.properties.ipAddress
output vmFqdn string = publicIp.properties.dnsSettings.fqdn
output aksClusterName string = aks.name
output aksResourceGroup string = resourceGroup().name
output sshCommand string = 'ssh ${adminUsername}@${publicIp.properties.ipAddress}'
output sshPasswordCommand string = 'ssh ${adminUsername}@${publicIp.properties.ipAddress} (password: ${adminPassword})'
output adminUsername string = adminUsername
output adminPassword string = adminPassword
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
