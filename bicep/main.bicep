//scope
targetScope = 'subscription'

//parameters
param on_prem_ip_ranges array = []
param vm_admin_password string {
  secure: true
}
param sql_admin_password string {
  secure: true
}
param aad_object_id string

//variables
var rg_name = 'rg-sql-bicep'
var rg_location = 'Australia East'
var vnet_name = 'vnet-spoke-w0101'
var vnet_resource_group = 'rg-network-spoke-101'
var subnet_name = 'ResourceSubnet1'
//Resoruces
//Resource group
resource rg 'Microsoft.Resources/resourceGroups@2020-06-01' = {
  name: rg_name
  location: rg_location
}

//everything else (KV, Storage Account, VM, SQL VM, disks, NIC, etc.)
module app './app.bicep' = {
  name: 'appDeploy'
  scope: resourceGroup(rg.name)
  params: {
    on_prem_ip_ranges: on_prem_ip_ranges
    vm_admin_password: vm_admin_password
    sql_admin_password: sql_admin_password
    aad_object_id: aad_object_id
    vnet_name: vnet_name
    vnet_resource_group: vnet_resource_group
    subnet_name: subnet_name
  }
}

//sql vm disk extension
module sql_disk_ext './sql-disk-ext.bicep' = {
  name: 'sqlDiskExtDeploy'
  scope: resourceGroup(rg.name)
  params: {
    sql_data_disk_luns: [
      6
      7
    ]
    vm_name: app.outputs.virtual_machine_name
    sql_license_type: app.outputs.sql_license_type
    storage_workload_type: app.outputs.sql_storage_workload_type
  }
  dependsOn: [
    app
  ]
}

//outputs
output resource_group_name string = rg_name

output location string = rg_location

output key_vault_id string = app.outputs.key_vault_id

output vm_id string = app.outputs.vm_id

output vm_name string = app.outputs.virtual_machine_name

output sql_vm_id string = app.outputs.sql_vm_id