@description('Name of the Virtual Machine')
param vmName string = 'cribl-fips-vm'

@description('Admin username for the VM')
param adminUsername string = 'azureuser'

@description('SSH public key for authentication')
param sshPublicKey string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Virtual Network Name')
param vnetName string = 'criblVNet'

@description('Subnet Name')
param subnetName string = 'criblSubnet'

@description('Public IP Name')
param publicIpName string = 'criblPublicIP'

@description('Network Interface Name')
param nicName string = 'criblNIC'

@description('Network Security Group Name')
param nsgName string = 'criblNSG'

@description('VM Size')
param vmSize string = 'Standard_B2ms'

@description('Cribl Download URL')
param criblDownloadUrl string = 'https://cdn.cribl.io/dl/cribl-4.3.1-12f82b6a-linux-x64.tgz'

@description('Cribl Version')
param criblVersion string = '4.3.1'

@description('Cribl Build')
param criblBuild string = '12f82b6a'

@description('Cribl Architecture')
param criblArch string = 'linux-x64'

@description('Cribl Mode (stream or edge)')
param criblMode string = 'stream'

@description('Enable FIPS mode for Cribl')
param criblFipsMode bool = true

@description('Add data disk for Cribl persistence')
param addDataDisk bool = true

@description('Data disk size in GB')
param dataDiskSizeGB int = 128

@description('Cribl Admin Password')
@secure()
param criblAdminPassword string

@description('Cribl Admin Username')
param criblAdminUsername string = 'admin'

@description('Cribl License Key (optional)')
@secure()
param criblLicenseKey string = ''

@description('DNS Name for Let\'s Encrypt SSL certificate (e.g., cribl.example.com)')
param dnsName string

@description('Email for Let\'s Encrypt SSL certificate')
param emailAddress string

@description('Configure Script URI')
param configScriptUri string = 'https://raw.githubusercontent.com/DataGuys/CriblinAzure/main/configure-cribl.sh'

@description('Use Key Vault for secrets')
param useKeyVault bool = false

@description('Managed Identity ID for VM')
param managedIdentityId string = ''

@description('Managed Identity Principal ID')
param managedIdentityPrincipalId string = ''

// Resource: Network Security Group
resource nsg 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
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
          priority: 1010
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowHTTPS'
        properties: {
          priority: 1020
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowCriblUI'
        properties: {
          priority: 1030
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '9000'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// Resource: Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
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
        name: subnetName
        properties: {
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// Resource: Public IP Address - Static for reliable DNS validation
resource publicIP 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: publicIpName
  location: location
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: toLower(replace(vmName, '_', '-'))
    }
  }
}

// Resource: Network Interface
resource nic 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIP.id
          }
          subnet: {
            id: '${vnet.id}/subnets/${subnetName}'
          }
        }
      }
    ]
  }
  dependsOn: [
    vnet
  ]
}

// Optional: Data Disk for Cribl persistence
resource dataDisk 'Microsoft.Compute/disks@2021-04-01' = if (addDataDisk) {
  name: '${vmName}-datadisk'
  location: location
  properties: {
    creationData: {
      createOption: 'Empty'
    }
    diskSizeGB: dataDiskSizeGB
  }
  sku: {
    name: 'Standard_LRS'
  }
}

// Resource: Virtual Machine
resource vm 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: vmName
  location: location
  identity: useKeyVault ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  } : null
  properties: {
    hardwareProfile: {
      vmSize: vmSize
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
              keyData: sshPublicKey
            }
          ]
        }
      }
      customData: base64(loadTextContent('scripts/custom-script.sh'))
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-pro-fips'
        sku: '22_04-lts-fips'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
      dataDisks: addDataDisk ? [
        {
          managedDisk: {
            id: dataDisk.id
          }
          lun: 0
          createOption: 'Attach'
        }
      ] : []
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

// Add Key Vault module if enabled
module keyVault './key-vault-module.bicep' = if (useKeyVault) {
  name: 'keyVaultDeployment'
  params: {
    location: location
    vmIdentityObjectId: managedIdentityPrincipalId
    criblAdminPassword: criblAdminPassword
    criblLicenseKey: criblLicenseKey
  }
}

// Resource: Custom Script Extension to configure Cribl with SSL
resource customScriptExtension 'Microsoft.Compute/virtualMachines/extensions@2021-07-01' = {
  name: '${vmName}/CustomScript'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      commandToExecute: 'bash /var/lib/waagent/custom-script/download/0/configure-cribl.sh "${criblDownloadUrl}" "${criblVersion}" "${criblMode}" "${criblAdminUsername}" "${criblAdminPassword}" "${dnsName}" "${emailAddress}" "${criblLicenseKey}" "${criblFipsMode}" "${addDataDisk}"'
      fileUris: [
        configScriptUri
      ]
    }
  }
  dependsOn: [
    vm
  ]
}

// Output the Public IP and FQDN
output publicIPAddress string = publicIP.properties.ipAddress
output fqdn string = publicIP.properties.dnsSettings.fqdn
output criblUIUrl string = 'https://${dnsName}:9000'
output keyVaultName string = useKeyVault ? keyVault.outputs.keyVaultName : 'Not deployed'
