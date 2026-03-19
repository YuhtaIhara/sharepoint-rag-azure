output "resource_group" {
  value = data.azurerm_resource_group.main.name
}

output "openai_endpoint" {
  value     = azurerm_cognitive_account.openai.endpoint
  sensitive = true
}

output "search_endpoint" {
  value = "https://${azurerm_search_service.main.name}.search.windows.net"
}

output "cosmosdb_endpoint" {
  value = azurerm_cosmosdb_account.main.endpoint
}

output "keyvault_uri" {
  value = azurerm_key_vault.main.vault_uri
}

output "functions_hostname" {
  value = azurerm_linux_function_app.main.default_hostname
}

output "webapp_hostname" {
  value = azurerm_linux_web_app.main.default_hostname
}

output "webapp_url" {
  value = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "functions_principal_id" {
  value = azurerm_linux_function_app.main.identity[0].principal_id
}

output "webapp_principal_id" {
  value = azurerm_linux_web_app.main.identity[0].principal_id
}

output "storage_docs_id" {
  description = "Storage account resource ID (for terraform import reference)"
  value       = azurerm_storage_account.docs.id
}
