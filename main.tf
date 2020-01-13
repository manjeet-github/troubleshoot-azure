locals {
  virtual_machine_name_client = "${var.vm_name}-client"
  custom_data_params  = "Param($ComputerName = \"${local.virtual_machine_name_client}\")"
  custom_data_content = "${local.custom_data_params} ${file("./files/winrm.ps1")}"
}

provider "azurerm" {
version = "=1.36.0"
}

// Create the resource groups
resource "azurerm_resource_group" "example" {
  name     = "${var.prefix}-resources"
  location = var.location
  tags     = var.tags
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "example" {
  name                = "${var.prefix}keyvault"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  tenant_id           = "${data.azurerm_client_config.current.tenant_id}"

  enabled_for_deployment          = true
  enabled_for_template_deployment = true

  sku {
    name = "standard"
  }

  access_policy {
    tenant_id = "${data.azurerm_client_config.current.tenant_id}"
    object_id = "${data.azurerm_client_config.current.service_principal_object_id}"

    certificate_permissions = [
      "create",
      "delete",
      "get",
      "update",
    ]

    key_permissions    = []
    secret_permissions = []
  }
}

resource "azurerm_key_vault_certificate" "windows-vm-certs" {
  name         = "${local.virtual_machine_name_client}-cert"
  key_vault_id = "${azurerm_key_vault.example.id}"

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      # Server Authentication = 1.3.6.1.5.5.7.3.1
      # Client Authentication = 1.3.6.1.5.5.7.3.2
      extended_key_usage = ["1.3.6.1.5.5.7.3.1"]

      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]

      subject            = "CN=${local.virtual_machine_name_client}"
      validity_in_months = 12
    }
  }
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  resource_group_name = azurerm_resource_group.example.name
  location            = var.location
  address_space       = ["${var.address_space}"]
  tags = var.tags
}

resource "azurerm_subnet" "subnet" {
  name                 = "${var.prefix}-subnet-1"
  resource_group_name = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefix       = var.subnet_prefix
}

resource "azurerm_network_security_group" "windows-vm-sg" {
  name                = "${var.prefix}-sg"
  resource_group_name = azurerm_resource_group.example.name
  location            = var.location
  tags                = var.tags

  security_rule {
    name                       = "HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "RDP"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule { //Here opened WinRMport http
    name                       = "winrm-http"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5985"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule { //Here opened WinRMport https
    name                       = "winrm-https"
    priority                   = 1011
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5986"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}


# - PROVISION NETWORK RESOURCES
resource "azurerm_public_ip" "windows-client-public-ip" {
  count               = "${var.vmcount}"
  name                = "win-vm-public-ip-${count.index}"
  resource_group_name = azurerm_resource_group.example.name
  location            = var.location
  allocation_method   = "Dynamic"
  domain_name_label   = "${lower(var.prefix)}-client-${count.index}"

  tags = "${merge(
    map(
      "Name", "win-vm-public-ip-${count.index}",
      "Description", "This is public ip object to be attached to the network card"
    ), var.tags)
  }"
}

resource "azurerm_network_interface" "windows-client-vm-nic" {
  count                     = "${var.vmcount}"
  name                      = "win-client-vm-nic-${count.index}"
  resource_group_name = azurerm_resource_group.example.name
  location            = var.location
  network_security_group_id = azurerm_network_security_group.windows-vm-sg.id
  //dns_servers               = [${var.dns_servers}]

  ip_configuration {
    name                          = "nic-ipconfig-${count.index}"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = "${element(azurerm_public_ip.windows-client-public-ip.*.id, count.index)}"
  }

  tags = "${merge(
    map(
      "Name", "win-vm-public-ip-${count.index}",
      "Description", "This is network card interface object"
    ), var.tags)
  }"
}



# - Create a new virtual machine with the following configuration
# - Install and run the powershell script
resource "azurerm_virtual_machine" "windows-ad-vm" {

  count                 = var.vmcount
  name                  = "${local.virtual_machine_name_client}-${count.index}"
  resource_group_name       = azurerm_resource_group.example.name
  location                  = var.location
  network_interface_ids = ["${element(azurerm_network_interface.windows-client-vm-nic.*.id, count.index)}"]
  vm_size               = var.vmsize["medium"]

  tags = merge(
    map(
      "Name", "win-client-virtual-machine-${count.index}",
      "Description", "This is windows vm workstation client for developers"
    ), var.tags)

  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true


  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }

  storage_os_disk {
    name              = "${var.name}vm-osdisk-1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = local.virtual_machine_name_client
    admin_username = var.storeWindows_UserName
    admin_password = var.storeWindows_Password
    custom_data    = local.custom_data_content
  }

  os_profile_secrets {
    source_vault_id = "${azurerm_key_vault.example.id}"

    vault_certificates {
      certificate_url   = azurerm_key_vault_certificate.windows-vm-certs.secret_id
      certificate_store = "My"
    }
  }

  os_profile_windows_config {
    provision_vm_agent        = true
    enable_automatic_upgrades = true

    winrm {
      protocol        = "https"
      certificate_url = azurerm_key_vault_certificate.windows-vm-certs.secret_id
    }

    additional_unattend_config {
      pass         = "oobeSystem"
      component    = "Microsoft-Windows-Shell-Setup"
      setting_name = "AutoLogon"
      content      = "<AutoLogon><Password><Value>var.storeWindows_Password</Value></Password><Enabled>true</Enabled><LogonCount>1</LogonCount><Username>var.storeWindows_UserName</Username></AutoLogon>"
    }

    # Unattend config is to enable basic auth in WinRM, required for the provisioner stage.
    additional_unattend_config {
      pass         = "oobeSystem"
      component    = "Microsoft-Windows-Shell-Setup"
      setting_name = "FirstLogonCommands"
      content      = file("./files/FirstLogonCommands.xml")
    }
  }


  provisioner "remote-exec" {
    connection {
      type     = "winrm"
      host     = element(azurerm_public_ip.windows-client-public-ip.*.fqdn, count.index)
      user     = var.storeWindows_UserName
      password = var.storeWindows_Password
      port     = 5986
      https    = true
      timeout  = "4m"

      # NOTE: if you're using a real certificate, rather than a self-signed one, you'll want this set to `false`/to remove this.
      insecure = true
    }

    inline = [
      "cd C:\\Windows",
      "dir",
      //"powershell.exe -ExecutionPolicy Unrestricted -Command {Install-WindowsFeature -name Web-Server -IncludeManagementTools}",
    ]
  }


}
