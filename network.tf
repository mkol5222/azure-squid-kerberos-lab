resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "lab" {
  name                = "vnet-${local.name_suffix}"
  address_space       = [var.vnet_cidr]
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  # Route ALL name resolution in this VNet through the DC once it exists.
  # See README.md "Why DNS works despite the DC not existing yet".
  dns_servers = [var.dc_private_ip]
  tags        = local.tags
}

resource "azurerm_subnet" "dc" {
  name                 = "snet-dc"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.dc_subnet_cidr]
}

resource "azurerm_subnet" "proxy" {
  name                 = "snet-proxy"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.proxy_subnet_cidr]
}

resource "azurerm_subnet" "client" {
  count                = var.deploy_test_client ? 1 : 0
  name                 = "snet-client"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.client_subnet_cidr]
}

# Name is fixed by Azure -- Bastion will not deploy into a subnet with any
# other name.
resource "azurerm_subnet" "bastion" {
  count                = var.deploy_bastion ? 1 : 0
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.bastion_subnet_cidr]
}

# ---------------------------------------------------------------------------
# NSGs. Azure attaches a default "AllowVnetInBound" rule (priority 65000) to
# every NSG, which would otherwise let any subnet reach any other subnet on
# any port. Each NSG below adds an explicit low-priority deny that overrides
# it, so only the specific allows listed actually get through -- real
# micro-segmentation per Check Point's Network Security Policy, not just a
# perimeter check.
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "dc" {
  name                = "nsg-dc"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  dynamic "security_rule" {
    for_each = var.deploy_bastion ? [1] : []
    content {
      name                       = "Allow-RDP-From-Bastion"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3389"
      source_address_prefix      = var.bastion_subnet_cidr
      destination_address_prefix = var.dc_subnet_cidr
    }
  }

  security_rule {
    name                       = "Allow-AD-Auth-Ports"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["53", "88", "389", "464", "636"]
    source_address_prefix      = var.vnet_cidr
    destination_address_prefix = var.dc_subnet_cidr
  }

  dynamic "security_rule" {
    for_each = var.deploy_test_client ? [1] : []
    content {
      name                       = "Allow-AD-FullJoin-Ports-From-Client"
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_ranges    = ["135", "445", "3268", "3269", "49152-65535"]
      source_address_prefix      = var.client_subnet_cidr
      destination_address_prefix = var.dc_subnet_cidr
    }
  }

  security_rule {
    name                       = "Deny-VnetInBound-Override"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }
}

resource "azurerm_network_security_group" "proxy" {
  name                = "nsg-proxy"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  dynamic "security_rule" {
    for_each = var.deploy_bastion ? [1] : []
    content {
      name                       = "Allow-SSH-From-Bastion"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = var.bastion_subnet_cidr
      destination_address_prefix = var.proxy_subnet_cidr
    }
  }

  security_rule {
    name                       = "Allow-ProxyPort-From-Vnet"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3128"
    source_address_prefix      = var.vnet_cidr
    destination_address_prefix = var.proxy_subnet_cidr
  }

  security_rule {
    name                       = "Deny-VnetInBound-Override"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }
}

resource "azurerm_network_security_group" "client" {
  count               = var.deploy_test_client ? 1 : 0
  name                = "nsg-client"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  dynamic "security_rule" {
    for_each = var.deploy_bastion ? [1] : []
    content {
      name                       = "Allow-RDP-From-Bastion"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3389"
      source_address_prefix      = var.bastion_subnet_cidr
      destination_address_prefix = var.client_subnet_cidr
    }
  }

  security_rule {
    name                       = "Deny-VnetInBound-Override"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }
}

resource "azurerm_subnet_network_security_group_association" "dc" {
  subnet_id                 = azurerm_subnet.dc.id
  network_security_group_id = azurerm_network_security_group.dc.id
}

resource "azurerm_subnet_network_security_group_association" "proxy" {
  subnet_id                 = azurerm_subnet.proxy.id
  network_security_group_id = azurerm_network_security_group.proxy.id
}

resource "azurerm_subnet_network_security_group_association" "client" {
  count                     = var.deploy_test_client ? 1 : 0
  subnet_id                 = azurerm_subnet.client[0].id
  network_security_group_id = azurerm_network_security_group.client[0].id
}
