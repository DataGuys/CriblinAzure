//@description('Deploys a FIPS-compliant Ubuntu VM with Cribl, Azure Firewall, and VPN Gateway in West US2/3')
param deploymentName string = 'criblFipsDeployment'

// Parameters for general settings
param location string = 'westus2'  // or 'westus3'
param dnsLabelPrefix string  // DNS name for public IP
param adminUsername string  // Admin username for VM
@secure()
param adminPassword string  // Password (if using password auth)
param adminSSHKey string = '' // SSH public key
param vmSize string = 'Standard_B2ms'  // VM SKU
param vmName string = 'vm-cribl-fips'
param vnetName string = 'vnet-cribl'
param addressSpace string = '10.0.0.0/16'

// Networking parameters (subnet prefixes)
param subnetWorkloadPrefix string = '10.0.1.0/24'  // Subnet for the VM
param subnetFirewallPrefix string = '10.0.2.0/26'  // Subnet for Azure Firewall (must be /26)
param subnetGatewayPrefix string = '10.0.3.0/27'   // Subnet for VPN Gateway (/27 recommended)

// VPN parameters
param deployVpnGateway bool = true
param onPremPublicIP string = ''  // On-prem VPN device IP
param onPremAddressSpace string = '192.168.0.0/24'  // On-prem network range
param vpnSharedKey string = 'YourSuperSecureKey'  // Pre-shared key for VPN

// Derived names for resources
var firewallName = '${deploymentName}-azfw'
var firewallPIPName = '${firewallName}-pip'
var vpnGwName = '${deploymentName}-vpn'
var vpnGwPIPName = '${vpnGwName}-pip'
var localGwName = '${deploymentName}-onprem'
var vnetAddressPrefixes = [ addressSpace ]

// Ubuntu 22.04 FIPS image (URN for Gen2)
var ubuntuFipsImage = {
  publisher: 'Canonical'
  offer: '0001-com-ubuntu-pro-jammy-fips'
  sku: 'pro-fips-22_04'
  version: 'latest'
}

// Resource: Virtual Network with subnets
resource vnet 'Microsoft.Network/virtualNetworks@2023-02-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: vnetAddressPrefixes
    }
    subnets: [
      {
        name: 'WorkloadSubnet'
        properties: {
          addressPrefix: subnetWorkloadPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
          routeTable: {
            id: udr.id
          }
        }
      }
      {
        name: 'AzureFirewallSubnet'  // must use this exact name
        properties: {
          addressPrefix: subnetFirewallPrefix
        }
      }
      {
        name: 'GatewaySubnet'       // exact name required for VPN Gateway
        properties: {
          addressPrefix: subnetGatewayPrefix
        }
      }
    ]
  }
  dependsOn: [
    nsg
    udr
  ]
}

// Resource: Network Security Group for Workload Subnet
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-02-01' = {
  name: 'nsg-workload'
  location: location
  properties: {
    securityRules: [
      // Allow from AzureFirewallSubnet to VM ports 443, 6514, 80
      {
        name: 'Allow-FW-HTTPS'
        properties: {
          description: 'Allow HTTPS from Azure Firewall to VMs'
          protocol: 'Tcp'
          sourceAddressPrefix: subnetFirewallPrefix
          destinationAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationPortRanges: ['443','6514','80']
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      // Allow Syslog TLS from on-prem via VPN
      {
        name: 'Allow-OnPrem-SyslogTLS'
        properties: {
          description: 'Allow syslog over TLS from on-prem network'
          protocol: 'Tcp'
          sourceAddressPrefix: onPremAddressSpace
          destinationAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationPortRange: '6514'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Resource: Public IP for Azure Firewall (with DNS label)
resource firewallPIP 'Microsoft.Network/publicIPAddresses@2023-02-01' = {
  name: firewallPIPName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    allocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: dnsLabelPrefix
    }
  }
}

// Resource: Azure Firewall
resource azureFirewall 'Microsoft.Network/azureFirewalls@2023-05-01' = {
  name: firewallName
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'  // standard SKU
      tier: 'Standard'
    }
    ipConfigurations: [
      {
        name: 'fw-ipconfig'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/AzureFirewallSubnet'
          }
          publicIPAddress: {
            id: firewallPIP.id
          }
        }
      }
    ]
    threatIntelMode: 'Alert'
  }
  dependsOn: [
    vnet
  ]
}

// Resource: User-Defined Route table
resource udr 'Microsoft.Network/routeTables@2023-02-01' = {
  name: 'udr-workload'
  location: location
  properties: {
    routes: [
      {
        name: 'DefaultRouteToFirewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: azureFirewall.properties.ipConfigurations[0].properties.privateIPAddress
        }
      }
    ]
  }
}

// Network Rules for Firewall
resource fwNetRules 'Microsoft.Network/azureFirewalls/networkRuleCollections@2023-05-01' = {
  parent: azureFirewall
  name: 'rc-net-AllowAllOut'
  properties: {
    priority: 100
    action: {
      type: 'Allow'
    }
    rules: [
      {
        name: 'AllowAll'
        protocols: ['Any']
        sourceAddresses: ['*']
        destinationAddresses: ['*']
        destinationPorts: ['*']
      }
    ]
  }
}

// NAT Rules for Firewall
resource fwNatRules 'Microsoft.Network/azureFirewalls/natRuleCollections@2023-05-01' = {
  parent: azureFirewall
  name: 'rc-nat-InboundDNAT'
  properties: {
    priority: 110
    action: {
      type: 'Dnat'
    }
    rules: [
      {
        name: 'DNAT-HTTPS'
        protocols: ['TCP']
        sourceAddresses: ['*']
        destinationAddresses: [firewallPIP.properties.ipAddress]
        destinationPorts: ['443']
        translatedAddress: vmNic.properties.ipConfigurations[0].properties.privateIPAddress
        translatedPort: '443'
      }
      {
        name: 'DNAT-HTTP'
        protocols: ['TCP']
        sourceAddresses: ['*']
        destinationAddresses: [firewallPIP.properties.ipAddress]
        destinationPorts: ['80']
        translatedAddress: vmNic.properties.ipConfigurations[0].properties.privateIPAddress
        translatedPort: '80'
      }
      {
        name: 'DNAT-SyslogTLS'
        protocols: ['TCP']
        sourceAddresses: ['*']
        destinationAddresses: [firewallPIP.properties.ipAddress]
        destinationPorts: ['6514']
        translatedAddress: vmNic.properties.ipConfigurations[0].properties.privateIPAddress
        translatedPort: '6514'
      }
    ]
  }
}

// Resource: Network Interface for VM
resource vmNic 'Microsoft.Network/networkInterfaces@2023-02-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/WorkloadSubnet'
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
  dependsOn: [
    vnet
  ]
}

// Resource: Virtual Machine (Ubuntu FIPS)
resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: ubuntuFipsImage
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
      dataDisks: [
        {
          lun: 0
          name: '${vmName}-data0'
          createOption: 'Empty'
          diskSizeGB: 1024  // 1 TB data disk
          managedDisk: { storageAccountType: 'Premium_LRS' }
        }
      ]
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: length(adminSSHKey) == 0 ? adminPassword : null
      linuxConfiguration: {
        disablePasswordAuthentication: length(adminSSHKey) > 0
        ssh: empty(adminSSHKey) ? null : {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminSSHKey
            }
          ]
        }
      }
      customData: base64( 
        '''
        #cloud-config
        package_update: true
        packages:
          - apt-transport-https
          - ca-certificates
          - curl
          - gnupg
          - lsb-release
        runcmd:
          - curl -L https://download.cribl.io/stream/latest/cribl-linux-x64.tgz -o /tmp/cribl.tgz
          - mkdir -p /opt/cribl && tar -xzf /tmp/cribl.tgz -C /opt/cribl --strip-components=1
          - useradd -m -d /opt/cribl -s /bin/bash cribl && chown -R cribl:cribl /opt/cribl
          - echo "RUN_IN_FIPS_MODE=true" >> /opt/cribl/bin/cribl.rc
          - su -c "/opt/cribl/bin/cribl boot-start create" cribl
          - systemctl enable cribl.service
          - systemctl start cribl.service
        '''
      )
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: vmNic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: { enabled: true }
    }
  }
  dependsOn: [
    vmNic
  ]
}

// Resources: VPN Gateway (optional)
resource vpnPIP 'Microsoft.Network/publicIPAddresses@2023-02-01' = if (deployVpnGateway) {
  name: vpnGwPIPName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    allocationMethod: 'Dynamic'
  }
}

resource vpnGw 'Microsoft.Network/virtualNetworkGateways@2023-02-01' = if (deployVpnGateway) {
  name: vpnGwName
  location: location
  properties: {
    sku: {
      name: 'VpnGw1'
      tier: 'VpnGw1'
    }
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    enableBgp: false
    ipConfigurations: [
      {
        name: 'vpngw-ipconfig'
        properties: {
          publicIPAddress: {
            id: vpnPIP.id
          }
          subnet: {
            id: '${vnet.id}/subnets/GatewaySubnet'
          }
        }
      }
    ]
    vpnClientConfiguration: null
  }
  dependsOn: [
    vnet
    vpnPIP
  ]
}

resource localGw 'Microsoft.Network/localNetworkGateways@2023-02-01' = if (deployVpnGateway) {
  name: localGwName
  location: location
  properties: {
    localNetworkAddressSpace: {
      addressPrefixes: [ onPremAddressSpace ]
    }
    gatewayIpAddress: onPremPublicIP
  }
}

resource vpnConnection 'Microsoft.Network/connections@2023-02-01' = if (deployVpnGateway) {
  name: '${deploymentName}-vpnConnection'
  location: location
  properties: {
    connectionType: 'IPsec'
    virtualNetworkGateway1: {
      id: vpnGw.id
    }
    localNetworkGateway2: {
      id: localGw.id
    }
    routingWeight: 10
    sharedKey: vpnSharedKey
  }
  dependsOn: [
    vpnGw
    localGw
  ]
}

// Outputs
output firewallPublicIP string = firewallPIP.properties.ipAddress
output firewallFQDN string = firewallPIP.properties.dnsSettings.fqdn
output vmPrivateIP string = vmNic.properties.ipConfigurations[0].properties.privateIPAddress
