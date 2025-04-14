provider "azurerm" {
  features {}
}

# Variables
variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
  default     = "cribl-fips-rg"
}

variable "location" {
  type        = string
  description = "Location for all resources"
  default     = "eastus"
}

variable "vm_name" {
  type        = string
  description = "Name of the Virtual Machine"
  default     = "cribl-fips-vm"
}

variable "admin_username" {
  type        = string
  description = "Admin username for the VM"
  default     = "azureuser"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for authentication"
}

variable "vnet_name" {
  type        = string
  description = "Virtual Network Name"
  default     = "criblVNet"
}

variable "subnet_name" {
  type        = string
  description = "Subnet Name"
  default     = "criblSubnet"
}

variable "public_ip_name" {
  type        = string
  description = "Public IP Name"
  default     = "criblPublicIP"
}

variable "nic_name" {
  type        = string
  description = "Network Interface Name"
  default     = "criblNIC"
}

variable "nsg_name" {
  type        = string
  description = "Network Security Group Name"
  default     = "criblNSG"
}

variable "vm_size" {
  type        = string
  description = "VM Size"
  default     = "Standard_B2ms"
}

variable "cribl_download_url" {
  type        = string
  description = "Cribl Download URL"
  default     = "https://cdn.cribl.io/dl/cribl-4.3.1-12f82b6a-linux-x64.tgz"
}

variable "cribl_version" {
  type        = string
  description = "Cribl Version"
  default     = "4.3.1"
}

variable "cribl_build" {
  type        = string
  description = "Cribl Build"
  default     = "12f82b6a"
}

variable "cribl_arch" {
  type        = string
  description = "Cribl Architecture"
  default     = "linux-x64"
}

variable "cribl_mode" {
  type        = string
  description = "Cribl Mode (stream or edge)"
  default     = "stream"
}

variable "cribl_admin_username" {
  type        = string
  description = "Cribl Admin Username"
  default     = "admin"
}

variable "cribl_admin_password" {
  type        = string
  description = "Cribl Admin Password"
  sensitive   = true
}

variable "cribl_license_key" {
  type        = string
  description = "Cribl License Key (optional)"
  default     = ""
  sensitive   = true
}

variable "dns_name" {
  type        = string
  description = "DNS Name for Let's Encrypt SSL certificate"
}

variable "email_address" {
  type        = string
  description = "Email for Let's Encrypt SSL certificate"
}

variable "cribl_fips_mode" {
  type        = bool
  description = "Enable FIPS mode for Cribl"
  default     = true
}

variable "add_data_disk" {
  type        = bool
  description = "Add data disk for Cribl persistence"
  default     = true
}

variable "data_disk_size_gb" {
  type        = number
  description = "Data disk size in GB"
  default     = 128
}

variable "config_script_uri" {
  type        = string
  description = "Configure Script URI"
  default     = "https://raw.githubusercontent.com/DataGuys/CriblinAzure/main/configure-cribl.sh"
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# Network Security Group
resource "azurerm_network_security_group" "nsg" {
  name                = var.nsg_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 1020
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowCriblUI"
    priority                   = 1030
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Subnet
resource "azurerm_subnet" "subnet" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/24"]
}

# Subnet NSG Association
resource "azurerm_subnet_network_security_group_association" "subnet_nsg" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Public IP
resource "azurerm_public_ip" "public_ip" {
  name                = var.public_ip_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  domain_name_label   = lower(replace(var.vm_name, "_", "-"))
}

# Network Interface
resource "azurerm_network_interface" "nic" {
  name                = var.nic_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

# Data Disk
resource "azurerm_managed_disk" "data_disk" {
  count                = var.add_data_disk ? 1 : 0
  name                 = "${var.vm_name}-datadisk"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.data_disk_size_gb
}

# Virtual Machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                = var.vm_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  size                = var.vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-pro-fips"
    sku       = "22_04-lts-fips"
    version   = "latest"
  }

  custom_data = filebase64("${path.module}/scripts/custom-script.sh")
}

# Attach Data Disk
resource "azurerm_virtual_machine_data_disk_attachment" "data_disk_attachment" {
  count              = var.add_data_disk ? 1 : 0
  managed_disk_id    = azurerm_managed_disk.data_disk[0].id
  virtual_machine_id = azurerm_linux_virtual_machine.vm.id
  lun                = "0"
  caching            = "ReadWrite"
}

# Custom Script Extension
resource "azurerm_virtual_machine_extension" "custom_script" {
  name                 = "CustomScript"
  virtual_machine_id   = azurerm_linux_virtual_machine.vm.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"

  protected_settings = jsonencode({
    "commandToExecute" : "bash /var/lib/waagent/custom-script/download/0/configure-cribl.sh \"${var.cribl_download_url}\" \"${var.cribl_version}\" \"${var.cribl_mode}\" \"${var.cribl_admin_username}\" \"${var.cribl_admin_password}\" \"${var.dns_name}\" \"${var.email_address}\" \"${var.cribl_license_key}\" \"${var.cribl_fips_mode}\" \"${var.add_data_disk}\"",
    "fileUris" : [var.config_script_uri]
  })

  depends_on = [
    azurerm_linux_virtual_machine.vm,
    azurerm_virtual_machine_data_disk_attachment.data_disk_attachment
  ]
}

# Outputs
output "public_ip_address" {
  value = azurerm_public_ip.public_ip.ip_address
}

output "fqdn" {
  value = azurerm_public_ip.public_ip.fqdn
}

output "cribl_ui_url" {
  value = "https://${var.dns_name}:9000"
}
