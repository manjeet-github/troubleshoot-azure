locals {
  virtual_machine_name = "${var.vm_name}-client"
  custom_data_params  = "Param($ComputerName = \"${local.virtual_machine_name}\")"
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
  location            = "${azurerm_resource_group.example.location}"
  resource_group_name = "${azurerm_resource_group.example.name}"
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

resource "azurerm_key_vault_certificate" "example" {
  name         = "${local.virtual_machine_name}-cert"
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

      subject            = "CN=${local.virtual_machine_name}"
      validity_in_months = 12
    }
  }
}


resource "azurerm_virtual_network" "example" {
  name                = "${var.prefix}-network"
  address_space       = ["10.0.0.0/16"]
  location            = "${azurerm_resource_group.example.location}"
  resource_group_name = "${azurerm_resource_group.example.name}"
}

resource "azurerm_subnet" "example" {
  name                 = "internal"
  resource_group_name  = "${azurerm_resource_group.example.name}"
  virtual_network_name = "${azurerm_virtual_network.example.name}"
  address_prefix       = "10.0.2.0/24"
}


# - PROVISION NETWORK RESOURCES
resource "azurerm_public_ip" "windows-public-ip" {
  count               = "${var.vmcount}"
  name                = "win-vm-public-ip-${count.index}"
  resource_group_name = "${data.azurerm_resource_group.myresourcegroup.name}"
  location            = "${data.azurerm_resource_group.myresourcegroup.location}"
  allocation_method   = "Dynamic"
  domain_name_label   = "${lower(var.prefix)}-client-${count.index}"

  tags = "${merge(
    map(
      "Name", "win-vm-public-ip-${count.index}",
      "Description", "This is public ip object to be attached to the network card"
    ), var.tags)
  }"
}

resource "azurerm_network_interface" "windows-vm-nic" {
  count                     = "${var.vmcount}"
  name                      = "win-client-vm-nic-${count.index}"
  resource_group_name       = "${data.azurerm_resource_group.myresourcegroup.name}"
  location                  = "${data.azurerm_resource_group.myresourcegroup.location}"
  network_security_group_id = "${data.azurerm_network_security_group.nw_sg.id}"
  dns_servers               = ["10.0.12.4"]

  ip_configuration {
    name                          = "nic-ipconfig-${count.index}"
    subnet_id                     = "${data.azurerm_subnet.subnet.id}"
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = "${element(azurerm_public_ip.windows-public-ip.*.id, count.index)}"
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
  name                  = local.virtual_machine_name_ad
  resource_group_name   = azurerm_resource_group.example.name
  location              = var.location
  network_interface_ids = ["${azurerm_network_interface.windows-ad-vm-nic.id}"]
  vm_size               = var.vmsize["medium"]
  tags                  = var.tags

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
    computer_name  = local.virtual_machine_name
    admin_username = var.storeWindows_UserName
    admin_password = var.storeWindows_Password
    custom_data    = local.custom_data_content
  }

  os_profile_secrets {
    source_vault_id = "${azurerm_key_vault.example.id}"

    vault_certificates {
      certificate_url   = "${azurerm_key_vault_certificate.example.secret_id}"
      certificate_store = "My"
    }
  }

  os_profile_windows_config {
    provision_vm_agent        = true
    enable_automatic_upgrades = true

    winrm {
      protocol        = "https"
      certificate_url = azurerm_key_vault_certificate.ad_vm_certificate.secret_id
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
      host     = azurerm_public_ip.windows-public-ip.fqdn
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

// this provisions a single node configuration with no redundancy.
resource "azurerm_virtual_machine_extension" "create-active-directory-forest" {
  name                 = "create-active-directory-forest"
  resource_group_name = azurerm_resource_group.example.name
  location            = var.location
  virtual_machine_name = azurerm_virtual_machine.windows-ad-vm.name
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  settings = <<SETTINGS
    {
        "commandToExecute": "powershell.exe -Command \"${local.powershell_command}\""
    }
SETTINGS
}