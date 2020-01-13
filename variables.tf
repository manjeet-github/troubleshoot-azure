##############################################################################
# Variables File
# 
# Here is where we store the default values for all the variables used in our
# Terraform code. If you create a variable with no default, the user will be
# prompted to enter it (or define it via config file or command line flags.)

variable "prefix" {
  description = "This prefix will be included in the name of most resources."
}

variable "name" {
  description = "This prefix will be included in the name of most resources."
  default     = "se-hangout-01102020"
}

variable "location" {
  description = "The region where the virtual network is created."
  default     = "East US"
}

variable "tags" {
  description = "Optional map of tags to set on resources, defaults to empty map."
  type        = map(string)
  default     = {}
}

// - Note the below variables can be pulled from HashiCorp Vault.
variable "storeWindows_UserName" {
  description = "Define the admin UserName to be used for provisioning the VM's"
}

variable "storeWindows_Password" {
  description = "Define the admin Password to be used for provisioning the VM's"
}

variable "dns_servers" {
  description = "array of dns servers"
}

// - variable definitions for network resources.
variable "address_space" {
  description = "The address space that is used by the virtual network. You can supply more than one address space. Changing this forces a new resource to be created."
  default     = "10.0.0.0/16"
}

variable "subnet_prefix" {
  description = "The address prefix to use for the subnet."
  default     = "10.0.10.0/24"
}

# - Variables below for the virtual machines - Win AD Server, Win Client
# - The password associated with the local administrator account on the virtual machine
# - This is stored in Vault and is fetched from the Vault

variable "vault_id_for_password" {
  description = "secret name in vault which stores the password for windows vm"
}

# - The username associated with the local administrator account on the virtual machine
# - This is stored in Vault and is fetched from the Vault
variable "vault_id_for_username" {
  description = "secret name in vault which stores the username for windows vm"
}

variable "vm_name" {
  description = "Name of the virtual machine"
  default     = "win-vm"
}

variable "vm_name_ad" {
  description = "Name of the virtual machine"
  default     = "windows-vm"
}

variable "winclient_vmcount" {
  description = "number of virtual machines"
  default     = "1"
}

variable "vmsize" {
  description = "VM Size for the Production Environment"
  type        = map(string)

  default = {
    small      = "Standard_DS1_v2"
    medium     = "Standard_D2s_v3"
    large      = "Standard_D4s_v3"
    extralarge = "Standard_D8s_v3"
  }
}

variable "os_ms" {
  description = "Operating System Image - MS Windows"
  type        = map(string)

  default = {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }
}

variable "active_directory_domain" {
  description = "The name of the Active Directory domain, for example `hashisingh.local`"
}

variable "active_directory_netbios_name" {
  description = "The netbios name of the Active Directory domain, for example `hashisingh`"
}

variable "vault_instance_password" {
  description = "Password for the vault instances"
  default = "Pass0000rdDonotUse"
}

variable "vault_instance_username" {
  description = "Username for the vault instances"
  default     = "TestAdmin"
}

variable "vault_instance_reference" {
  description = "URL for the image"
  default     = "/subscriptions/14692f20-9428-451b-8298-102ed4e39c2a/resourceGroups/pncvaultpoc2019img/providers/Microsoft.Compute/images/RHEL-7_Vault-2019-12-18-143051"
}


variable "vault_instance_count" {
  description = "Size of the cluster"
  default     = "1"
}

variable "vault_instance_name_prefix" {
  description = "name prefix for the vault VM"
  default     = "vaultprefix"
}

