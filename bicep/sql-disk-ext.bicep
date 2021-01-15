//parameters
param sql_data_disk_luns array
param sql_data_path string = 'F:\\SQLData'
param vm_name string
param sql_license_type string = 'AHUB'
param storage_workload_type string = 'OLTP'

//Resoruces

// extending sql data drive. this works in Bicep / ARM, but wont work in Terraform
resource sql_vm_data_disk_extension 'Microsoft.SqlVirtualMachine/sqlVirtualMachines@2017-03-01-preview' = {
  name: vm_name
  location: resourceGroup().location
  properties: {
    virtualMachineResourceId: resourceId('Microsoft.Compute/virtualMachines', vm_name)
    sqlServerLicenseType: sql_license_type

    storageConfigurationSettings: {
      diskConfigurationType: 'EXTEND'
      storageWorkloadType: storage_workload_type
      sqlDataSettings: {
        luns: sql_data_disk_luns
      }
    }
  }
}