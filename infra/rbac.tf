# --- AI Search MI ---

# 1. AI Search → Storage (文書用): Blob Data Reader
resource "azurerm_role_assignment" "search_blob_reader" {
  scope                = azurerm_storage_account.docs.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_search_service.main.identity[0].principal_id
}

# 2. AI Search → OpenAI: Cognitive Services OpenAI User
resource "azurerm_role_assignment" "search_openai_user" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_search_service.main.identity[0].principal_id
}

# --- Functions MI ---

# 3. Functions → Key Vault: Key Vault Secrets User
resource "azurerm_role_assignment" "functions_kv_reader" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# 4. Functions → Storage (文書用): Blob Data Contributor
resource "azurerm_role_assignment" "functions_blob_contributor" {
  scope                = azurerm_storage_account.docs.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# 5. Functions → OpenAI: Cognitive Services OpenAI User
resource "azurerm_role_assignment" "functions_openai_user" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# --- App Service MI ---

# 6. App Service → Key Vault: Key Vault Secrets User
resource "azurerm_role_assignment" "webapp_kv_reader" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

# --- Current User (Terraform 実行者) ---

# 7. current_user → AI Search: Search Index Data Contributor
resource "azurerm_role_assignment" "current_user_search_index_contributor" {
  scope                = azurerm_search_service.main.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# 8. current_user → AI Search: Search Index Data Reader
resource "azurerm_role_assignment" "current_user_search_index_reader" {
  scope                = azurerm_search_service.main.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = data.azurerm_client_config.current.object_id
}

# 9. current_user → AI Search: Search Service Contributor
resource "azurerm_role_assignment" "current_user_search_contributor" {
  scope                = azurerm_search_service.main.id
  role_definition_name = "Search Service Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# 10. current_user → Key Vault: Key Vault Secrets Officer
resource "azurerm_role_assignment" "current_user_kv_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
