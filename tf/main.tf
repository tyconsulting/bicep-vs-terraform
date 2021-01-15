locals {
  vnet_name           = "vnet-spoke-w0101"
  vnet_resource_group = "rg-network-spoke-101"
  subnet_name         = "ResourceSubnet1"
  kv_name_prefix      = "kv-sql-tf"
  vm_name_prefix      = "vm-sql-tf"
  rg_name             = "rg-sql-tf"
  location            = "Australia East"
  vm_size             = "Standard_DS3_v2"
  vm_admin_username   = "vmadmin"
  vm_image_reference = {
    publisher = "MicrosoftSQLServer"
    offer     = "SQL2016SP2-WS2016"
    sku       = "Enterprise"
    version   = "latest"
  }

  vm_data_disks = [
    {
      name         = "data_disk_1"
      disk_size_gb = 256
      lun          = 1
    },
    {
      name         = "data_disk_2"
      disk_size_gb = 256
      lun          = 2
    },
    {
      name         = "log_disk_1"
      disk_size_gb = 128
      lun          = 3
    },
    {
      name         = "log_disk_2"
      disk_size_gb = 128
      lun          = 4
    },
    {
      name         = "temp_db_1disk_1"
      disk_size_gb = 64
      lun          = 5
    },
    # drive extensions
    {
      name         = "data_disk_3"
      disk_size_gb = 256
      lun          = 6
    },
    {
      name         = "data_disk_4"
      disk_size_gb = 256
      lun          = 7
    },
  ]

  sql_vm_config = {
    sql_license_type                 = "AHUB"
    r_services_enabled               = false
    sql_connectivity_port            = 1433
    sql_connectivity_type            = "PRIVATE"
    sql_connectivity_update_username = "sqladmin"
    sql_connectivity_update_password = random_password.sql_admin_password.result
    storage_workload_type            = "OLTP"
  }
  sql_disk_config = {
    data_drive_luns    = [1, 2]
    data_path          = "F:\\SQLData"
    log_drive_luns     = [3, 4]
    log_path           = "L:\\SQLLogs"
    temp_db_drive_luns = [5]
    temp_db_path       = "T:\\TempDB"
  }
}

data "azurerm_client_config" "current" {}

# get existing subnet
data "azurerm_subnet" "vm_subnet" {
  name                 = local.subnet_name
  virtual_network_name = local.vnet_name
  resource_group_name  = local.vnet_resource_group
}

# create resource group
resource "azurerm_resource_group" "rg" {
  name     = local.rg_name
  location = local.location
}

# generate random VM admin password
resource "random_password" "vm_admin_password" {
  length           = 12
  special          = true
  override_special = "_%@"
}

# generate random SQL admin password
resource "random_password" "sql_admin_password" {
  length           = 12
  special          = true
  override_special = "_%@"
}

# generate random name suffix
resource "random_string" "name_suffix" {
  length  = 5
  special = false
  upper   = false
}

# create key vault
resource "azurerm_key_vault" "kv" {
  name                            = "${local.kv_name_prefix}-${random_string.name_suffix.result}"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  enabled_for_disk_encryption     = true
  enabled_for_template_deployment = true
  enabled_for_deployment          = true
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  soft_delete_enabled             = true
  soft_delete_retention_days      = 7
  purge_protection_enabled        = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "get",
      "list",
      "backup",
      "delete",
      "set",
      "purge",
      "recover"
    ]

    storage_permissions = [
      "get",
      "list",
      "set"
    ]
  }

  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = [data.azurerm_subnet.vm_subnet.id]
    ip_rules                   = var.on_prem_ip_ranges
  }

}

# store vm admin password in the KV
resource "azurerm_key_vault_secret" "vm_admin_password" {
  name         = "vm-admin-password"
  value        = random_password.vm_admin_password.result
  key_vault_id = azurerm_key_vault.kv.id
}

# store vm admin user name in the KV
resource "azurerm_key_vault_secret" "vm_admin_username" {
  name         = "vm-admin-username"
  value        = local.vm_admin_username
  key_vault_id = azurerm_key_vault.kv.id
}

# store sql admin password in the KV
resource "azurerm_key_vault_secret" "sql_admin_password" {
  name         = "sql-admin-password"
  value        = random_password.sql_admin_password.result
  key_vault_id = azurerm_key_vault.kv.id
}

# store sql admin user name in the KV
resource "azurerm_key_vault_secret" "sql_admin_username" {
  name         = "sql-admin-username"
  value        = local.sql_vm_config.sql_connectivity_update_username
  key_vault_id = azurerm_key_vault.kv.id
}

# create Windows VM
resource "azurerm_network_interface" "nic" {
  name                = "nic-${local.vm_name_prefix}-${random_string.name_suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = data.azurerm_subnet.vm_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_virtual_machine" "vm" {
  name                  = "${local.vm_name_prefix}-${random_string.name_suffix.result}"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.nic.id]
  vm_size               = local.vm_size
  identity {
    type = "SystemAssigned"
  }

  delete_os_disk_on_termination = true

  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = local.vm_image_reference.publisher
    offer     = local.vm_image_reference.offer
    sku       = local.vm_image_reference.sku
    version   = local.vm_image_reference.version
  }
  storage_os_disk {
    name              = "${local.vm_name_prefix}-${random_string.name_suffix.result}-os-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  dynamic "storage_data_disk" {
    for_each = local.vm_data_disks == null ? [] : local.vm_data_disks

    content {
      name          = storage_data_disk.value.name
      caching       = "ReadOnly"
      create_option = "Empty"
      disk_size_gb  = storage_data_disk.value.disk_size_gb
      lun           = storage_data_disk.value.lun
    }
  }
  os_profile {
    computer_name  = "${local.vm_name_prefix}-${random_string.name_suffix.result}"
    admin_username = local.vm_admin_username
    admin_password = random_password.vm_admin_password.result
  }
  os_profile_windows_config {
    provision_vm_agent        = true
    enable_automatic_upgrades = true
    timezone                  = "AUS Eastern Standard Time"
  }
}

resource "azurerm_mssql_virtual_machine" "sql_vm" {
  virtual_machine_id               = azurerm_virtual_machine.vm.id
  sql_license_type                 = local.sql_vm_config.sql_license_type
  r_services_enabled               = local.sql_vm_config.r_services_enabled
  sql_connectivity_port            = local.sql_vm_config.sql_connectivity_port
  sql_connectivity_type            = local.sql_vm_config.sql_connectivity_type
  sql_connectivity_update_password = local.sql_vm_config.sql_connectivity_update_password
  sql_connectivity_update_username = local.sql_vm_config.sql_connectivity_update_username
  storage_configuration {
    disk_type             = "NEW"
    storage_workload_type = local.sql_vm_config.storage_workload_type
    data_settings {
      default_file_path = local.sql_disk_config.data_path
      luns              = local.sql_disk_config.data_drive_luns
    }
    log_settings {
      default_file_path = local.sql_disk_config.log_path
      luns              = local.sql_disk_config.log_drive_luns
    }
    temp_db_settings {
      default_file_path = local.sql_disk_config.temp_db_path
      luns              = local.sql_disk_config.temp_db_drive_luns
    }
  }
}

/*
# extending sql data drive. this wont work in Terraform
resource "azurerm_mssql_virtual_machine" "sql_vm_data_disk_extension" {
  virtual_machine_id = azurerm_virtual_machine.vm.id
  sql_license_type   = local.sql_vm_config.sql_license_type
  #r_services_enabled               = local.sql_vm_config.r_services_enabled
  storage_configuration {
    disk_type             = "EXTEND"
    storage_workload_type = local.sql_vm_config.storage_workload_type
    data_settings {
      default_file_path = local.sql_disk_config.data_path
      luns              = [6, 7]
    }
  }
  depends_on = [
    azurerm_mssql_virtual_machine.sql_vm
  ]
}
*/
