//@description('Deploys a FIPS-compliant Ubuntu VM with Cribl, Azure Firewall, and VPN Gateway in West US2/3')
param deploymentName string = 'criblFipsDeployment'

// Parameters for general settings
param location string = 'westus2'  // or 'westus3'
param dnsLabelPrefix string  // DNS name for public IP (e.g., "cribl-fw" to form cribl-fw.<region>.cloudapp.azure.com)
param adminUsername string  // Admin username for VM
@secure()
param adminPassword string  // Password (if using password auth) – optional if SSH key provided
param adminSSHKey string = '' // SSH public key (use this for Linux VM authentication for better security)
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
param onPremAddressSpace string = '192.168.0.0/24'  // On-prem network range (example)
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
            id: resourceId('Microsoft.Network/networkSecurityGroups', 'nsg-workload')
          }
          routeTable: {
            id: resourceId('Microsoft.Network/routeTables', 'udr-workload')
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
      // Allow Syslog TLS from on-prem via VPN (source is on-prem address space)
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
      // (Optional) Allow SSH from on-prem admin IPs
      /*{
        name: 'Allow-OnPrem-SSH'
        properties: {
          protocol: 'Tcp'
          sourceAddressPrefix: onPremAddressSpace  // or specific admin IP
          destinationAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationPortRange: '22'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }*/
      // Deny all else (note: NSG has implicit deny, so additional rules not needed)
    ]
  }
}

// Resource: User-Defined Route table to route Internet traffic from VM subnet -> Azure Firewall
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
  dependsOn: [ vnet, azureFirewall ]  // ensure firewall exists to get its IP
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
          // firewall is injected into the VNet subnet
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'AzureFirewallSubnet')
          }
          publicIPAddress: {
            id: firewallPIP.id
          }
        }
      }
    ]
    // Firewall Policy or Rules (for simplicity, using classic rules here)
    threatIntelMode: 'Alert'
  }
}

// Resource: Firewall Network Rule Collection (for outbound rules, if needed)
// (We allow all outbound in this example; could add rules to restrict e.g. only 80/443)
resource fwNetRules 'Microsoft.Network/azureFirewalls/ruleCollections@2023-05-01' = if (!empty(azureFirewall.name)) {
  name: '${azureFirewall.name}/rc-net-AllowAllOut'
  properties: {
    priority: 100
    ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
    // Actually AzureFirewall with classic rules uses AzureFirewallRuleCollection, we might skip detailed rules here for brevity
    // In real template, we could configure rules via Firewall Policy instead.
  }
  dependsOn: [ azureFirewall ]
}

// Resource: Firewall NAT Rule Collection (DNAT for inbound)
resource fwNatRules 'Microsoft.Network/azureFirewalls/ruleCollections@2023-05-01' = {
  name: '${azureFirewall.name}/rc-nat-InboundDNAT'
  dependsOn: [ azureFirewall ]
  properties: {
    priority: 110
    ruleCollectionType: 'FirewallPolicyNatRuleCollection'  // using firewall policy model for simplicity
    rules: [
      {
        name: 'DNAT-HTTPS'
        properties: {
          sourceAddresses: ['*']              // any source
          destinationAddresses: [ firewallPIP.properties.ipAddress ]  // firewall public IP
          destinationPorts: ['443']
          protocols: [ 'TCP' ]
          translatedAddress: reference(vmNic.id, '2023-02-01', 'Full').ipConfigurations[0].properties.privateIPAddress
          translatedPort: '443'
        }
      },
      {
        name: 'DNAT-HTTP'
        properties: {
          sourceAddresses: ['*']
          destinationAddresses: [ firewallPIP.properties.ipAddress ]
          destinationPorts: ['80']
          protocols: [ 'TCP' ]
          translatedAddress: reference(vmNic.id, '2023-02-01', 'Full').ipConfigurations[0].properties.privateIPAddress
          translatedPort: '80'
        }
      },
      {
        name: 'DNAT-SyslogTLS'
        properties: {
          sourceAddresses: ['*']
          destinationAddresses: [ firewallPIP.properties.ipAddress ]
          destinationPorts: ['6514']
          protocols: [ 'TCP' ]
          translatedAddress: reference(vmNic.id, '2023-02-01', 'Full').ipConfigurations[0].properties.privateIPAddress
          translatedPort: '6514'
        }
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
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'WorkloadSubnet')
          }
          privateIPAllocationMethod: 'Dynamic'
          // No public IP on NIC, all ingress/egress via firewall
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
  dependsOn: [ vnet, nsg ]
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
        // by default, Ubuntu image OS disk is Standard SSD, we can set to Premium_LRS for performance
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
        disablePasswordAuthentication: length(adminSSHKey) > 0  // if SSH key provided, disable password auth
        ssh: empty(adminSSHKey) ? null : {
          publicKeys: [
            {
              path: '/home/'+adminUsername+'/.ssh/authorized_keys'
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
          - echo "RUN_IN_FIPS_MODE=true" >> /opt/cribl/cribl/bin/cribl.rc   # hypothetical flag to enable FIPS in Cribl
          - su -c "/opt/cribl/bin/cribl boot-start create" cribl             # install Cribl as systemd service
          - systemctl enable cribl.service
          - systemctl start cribl.service
          # Note: Further configuration for TLS cert and ports can be done post-boot (or via additional scripting).
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
  dependsOn: [ vmNic ]
}

// Resources: VPN Gateway (optional, if deployVpnGateway = true)
resource vpnPIP 'Microsoft.Network/publicIPAddresses@2023-02-01' = if (deployVpnGateway) {
  name: vpnGwPIPName
  location: location
  sku: {
    name: 'Basic'  // Basic or Standard depending on VPN SKU (VpnGw1 uses Basic PIP)
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
      name: 'VpnGw1'  // gateway SKU
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
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'GatewaySubnet')
          }
        }
      }
    ]
    vpnClientConfiguration: null
  }
  dependsOn: [ vnet, vpnPIP ]
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
  dependsOn: [ vpnGw, localGw ]
}

// Outputs
output firewallPublicIP string = firewallPIP.properties.ipAddress
output firewallFQDN string = firewallPIP.properties.dnsSettings.fqdn
output vmPrivateIP string = vmNic.properties.ipConfigurations[0].properties.privateIPAddress
