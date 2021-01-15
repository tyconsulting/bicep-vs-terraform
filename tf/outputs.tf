output "resource_group_name" {
  value = local.rg_name
}
output "location" {
  value = local.location
}
output "key_vault_id" {
  value = azurerm_key_vault.kv.id
}
output "vm_id" {
  value = azurerm_virtual_machine.vm.id
}
output "sql_vm_id" {
  value = azurerm_mssql_virtual_machine.sql_vm.id
}