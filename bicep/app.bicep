//scope
targetScope = 'resourceGroup'

//parameters
param on_prem_ip_ranges array = []
param vm_admin_password string {
  secure: true
}
param sql_admin_password string {
  secure: true
}
param vnet_name string
param vnet_resource_group string
param subnet_name string

//UTC now string - used for generating random strings later
param now string = utcNow('u')
//AAD object id
param aad_object_id string

//variables
var kv_name_prefix = 'kv-sql-bi'
var vm_name_prefix = 'vm-sql-bi'
var vm_name = '${vm_name_prefix}-${name_suffix}'
var kv_name = '${kv_name_prefix}-${name_suffix}'
var vm_size = 'Standard_DS3_v2'
var vm_admin_username = 'vmadmin'
var vm_image_reference = {
  publisher: 'MicrosoftSQLServer'
  offer: 'SQL2016SP2-WS2016'
  sku: 'Enterprise'
  version: 'latest'
}
var vm_data_disks = [
  {
    name: 'data_disk_1'
    diskSizeGB: 256
    lun: 1
    createOption: 'Empty'
  }
  {
    name: 'data_disk_2'
    diskSizeGB: 256
    lun: 2
    createOption: 'Empty'
  }
  {
    name: 'log_disk_1'
    diskSizeGB: 128
    lun: 3
    createOption: 'Empty'
  }
  {
    name: 'log_disk_2'
    diskSizeGB: 128
    lun: 4
    createOption: 'Empty'
  }
  {
    name: 'temp_db_1disk_1'
    diskSizeGB: 64
    lun: 5
    createOption: 'Empty'
  }
  // drive extensions
  {
    name: 'data_disk_3'
    diskSizeGB: 256
    lun: 6
    createOption: 'Empty'
  }
  {
    name: 'data_disk_4'
    diskSizeGB: 256
    lun: 7
    createOption: 'Empty'
  }
]

var sql_vm_config = {
  sql_license_type: 'AHUB'
  r_services_enabled: false
  sql_connectivity_port: 1433
  sql_connectivity_type: 'PRIVATE'
  sql_connectivity_update_username: 'sqladmin'
  sql_connectivity_update_password: 'change-it-later'
  sql_workload_type: 'OLTP'
  storage_workload_type: 'OLTP'
}
var sql_disk_config = {
  data_drive_luns: [
    1
    2
  ]
  data_path: 'F:\\SQLData'
  log_drive_luns: [
    3
    4
  ]
  log_path: 'L:\\SQLLogs'
  temp_db_drive_luns: [
    5
  ]
  temp_db_path: 'T:\\TempDB'
}
//namesuffix will be random the current timestamp is used to generate the Uuique string
var name_suffix = substring(uniqueString(resourceGroup().id, now), 0, 5)

// get subnet id
var subnet_id = resourceId(subscription().subscriptionId, vnet_resource_group, 'Microsoft.Network/virtualNetworks/subnets', vnet_name, subnet_name)

//Resoruces

// create key vault
resource kv 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: kv_name
  location: resourceGroup().location
  properties: {
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: true
    enabledForDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: true
    tenantId: subscription().tenantId
    sku: {
      name: 'standard'
      family: 'A'
    }
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: aad_object_id
        permissions: {
          secrets: [
            'get'
            'list'
            'backup'
            'delete'
            'set'
            'purge'
            'recover'
          ]
          storage: [
            'get'
            'list'
            'set'
          ]
        }
      }
    ]

    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: on_prem_ip_ranges
      virtualNetworkRules: [
        {
          id: subnet_id
        }
      ]
    }
  }
}

// store vm admin password in the KV
resource kv_secret_vm_admin_password 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  name: '${kv.name}/vm-admin-password'
  properties: {
    value: vm_admin_password
  }
}

// store vm admin user name in the KV
resource kv_secret_vm_admin_username 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  name: '${kv.name}/vm-admin-username'
  properties: {
    value: vm_admin_username
  }
}

// store sql admin password in the KV
resource kv_secret_sql_admin_password 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  name: '${kv.name}/sql-admin-password'
  properties: {
    value: sql_admin_password
  }
}

// store sql admin user name in the KV
resource kv_secret_sql_admin_username 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  name: '${kv.name}/sql-admin-username'
  properties: {
    value: sql_vm_config.sql_connectivity_update_username
  }
}

//Storage account - for SQL DB backup - SQL DB backup is not implemented in AzureRM TF provider
resource stg 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: 'sa${name_suffix}' // must be globally unique
  location: resourceGroup().location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
}

// create Windows VM
// nic
resource nic 'Microsoft.Network/networkInterfaces@2020-06-01' = {
  name: 'nic-${vm_name}'
  location: resourceGroup().location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnet_id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// vm
resource vm 'Microsoft.Compute/virtualMachines@2020-06-01' = {
  name: vm_name
  location: resourceGroup().location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vm_size
    }
    storageProfile: {
      imageReference: vm_image_reference
      osDisk: {
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
      dataDisks: vm_data_disks
    }
    osProfile: {
      computerName: '${vm_name_prefix}-${name_suffix}'
      adminUsername: vm_admin_username
      adminPassword: vm_admin_password
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: true
        timeZone: 'AUS Eastern Standard Time'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            primary: true
          }
        }
      ]
    }
    licenseType: 'Windows_Server'
  }
}

//SQL server
resource sql_vm 'Microsoft.SqlVirtualMachine/sqlVirtualMachines@2017-03-01-preview' = {
  name: vm.name
  location: resourceGroup().location

  properties: {
    virtualMachineResourceId: vm.id
    sqlManagement: 'Full'
    sqlServerLicenseType: sql_vm_config.sql_license_type
    autoPatchingSettings: {
      enable: false
    }
    autoBackupSettings: {
      // not supported in TF
      enable: true
      retentionPeriod: 30
      storageAccountUrl: stg.properties.primaryEndpoints.blob
      storageAccessKey: listKeys(stg.id, stg.apiVersion).keys[0].value
      enableEncryption: false
      backupSystemDbs: true
      backupScheduleType: 'Manual'
      fullBackupFrequency: 'Daily'
      fullBackupStartTime: 23
      fullBackupWindowHours: 2
      logBackupFrequency: 60
    }
    serverConfigurationsManagementSettings: {
      sqlConnectivityUpdateSettings: {
        connectivityType: sql_vm_config.sql_connectivity_type
        port: sql_vm_config.sql_connectivity_port
        sqlAuthUpdateUserName: sql_vm_config.sql_connectivity_update_username
        sqlAuthUpdatePassword: sql_vm_config.sql_connectivity_update_password
      }
      additionalFeaturesServerConfigurations: {
        isRServicesEnabled: false
      }
    }
    storageConfigurationSettings: {
      diskConfigurationType: 'NEW'
      storageWorkloadType: sql_vm_config.storage_workload_type
      sqlDataSettings: {
        defaultFilePath: sql_disk_config.data_path
        luns: sql_disk_config.data_drive_luns
      }
      sqlLogSettings: {
        defaultFilePath: sql_disk_config.log_path
        luns: sql_disk_config.log_drive_luns
      }
      sqlTempDbSettings: {
        defaultFilePath: sql_disk_config.temp_db_path
        luns: sql_disk_config.temp_db_drive_luns
      }
    }
  }
}

//outputs
output key_vault_id string = kv.id

output vm_id string = vm.id

output virtual_machine_name string = vm.name

output sql_vm_id string = sql_vm.id

output sql_data_path string = sql_disk_config.data_path

output sql_log_path string = sql_disk_config.log_path

output sql_tempdb_path string = sql_disk_config.temp_db_path

output sql_license_type string = sql_vm_config.sql_license_type

output sql_storage_workload_type string = sql_vm_config.storage_workload_type