# Key Vault — RBAC 認可モデル
resource "azurerm_key_vault" "main" {
  name                       = "kv-${var.project}-jpe"
  resource_group_name        = data.azurerm_resource_group.main.name
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 90
  tags                       = local.tags
}

# --- Secrets (9件) ---

resource "azurerm_key_vault_secret" "openai_key" {
  name         = "AZURE-OPENAI-KEY"
  value        = azurerm_cognitive_account.openai.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.current_user_kv_officer]
}

resource "azurerm_key_vault_secret" "openai_endpoint" {
  name         = "AZURE-OPENAI-ENDPOINT"
  value        = azurerm_cognitive_account.openai.endpoint
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.current_user_kv_officer]
}

resource "azurerm_key_vault_secret" "search_key" {
  name         = "SEARCH-API-KEY"
  value        = azurerm_search_service.main.primary_key
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.current_user_kv_officer]
}

resource "azurerm_key_vault_secret" "search_endpoint" {
  name         = "SEARCH-ENDPOINT"
  value        = "https://${azurerm_search_service.main.name}.search.windows.net"
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.current_user_kv_officer]
}

resource "azurerm_key_vault_secret" "cosmos_connection" {
  name         = "COSMOS-CONNECTION-STRING"
  value        = "AccountEndpoint=${azurerm_cosmosdb_account.main.endpoint};AccountKey=${azurerm_cosmosdb_account.main.primary_key};"
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.current_user_kv_officer]
}

resource "azurerm_key_vault_secret" "storage_connection" {
  name         = "STORAGE-CONNECTION-STRING"
  value        = azurerm_storage_account.docs.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.current_user_kv_officer]
}

resource "azurerm_key_vault_secret" "graph_client_id" {
  name         = "GRAPH-CLIENT-ID"
  value        = data.azuread_application.main.client_id
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.current_user_kv_officer]
}

resource "azurerm_key_vault_secret" "graph_client_secret" {
  name         = "GRAPH-CLIENT-SECRET"
  value        = var.graph_client_secret
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.current_user_kv_officer]
}

resource "azurerm_key_vault_secret" "graph_tenant_id" {
  name         = "GRAPH-TENANT-ID"
  value        = data.azurerm_client_config.current.tenant_id
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.current_user_kv_officer]
}
