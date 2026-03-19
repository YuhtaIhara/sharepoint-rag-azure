# Functions Service Plan — Consumption Y1 (Japan East quota=0 のため East Asia)
resource "azurerm_service_plan" "functions" {
  name                = "plan-func-${var.project}-ea"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.webapp_location
  os_type             = "Linux"
  sku_name            = "Y1"
  tags                = local.tags
}

# Functions App
resource "azurerm_linux_function_app" "main" {
  name                       = "func-${var.project}-ea"
  resource_group_name        = data.azurerm_resource_group.main.name
  location                   = var.webapp_location
  service_plan_id            = azurerm_service_plan.functions.id
  storage_account_name       = azurerm_storage_account.functions.name
  storage_account_access_key = azurerm_storage_account.functions.primary_access_key

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      python_version = "3.12"
    }
    application_insights_connection_string = azurerm_application_insights.main.connection_string
  }

  app_settings = {
    # Key Vault references (sensitive)
    "AZURE_OPENAI_API_KEY"     = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=AZURE-OPENAI-KEY)"
    "AZURE_OPENAI_ENDPOINT"    = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=AZURE-OPENAI-ENDPOINT)"
    "AZURE_SEARCH_API_KEY"     = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=SEARCH-API-KEY)"
    "AZURE_SEARCH_ENDPOINT"    = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=SEARCH-ENDPOINT)"
    "COSMOS_CONNECTION_STRING"  = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=COSMOS-CONNECTION-STRING)"
    "STORAGE_CONNECTION_STRING" = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=STORAGE-CONNECTION-STRING)"
    "GRAPH_CLIENT_ID"           = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=GRAPH-CLIENT-ID)"
    "GRAPH_CLIENT_SECRET"       = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=GRAPH-CLIENT-SECRET)"
    "GRAPH_TENANT_ID"           = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=GRAPH-TENANT-ID)"

    # Non-sensitive
    "AZURE_OPENAI_CHAT_DEPLOYMENT"      = "gpt-4o-mini"
    "AZURE_OPENAI_EMBEDDING_DEPLOYMENT" = "text-embedding-3-large"
    "AZURE_SEARCH_INDEX_NAME"           = "sprag-index"
    "COSMOS_DB_DATABASE"                = "ChatDB"
    "COSMOS_DB_CONTAINER"               = "conversations"
    "BLOB_CONTAINER_NAME"               = "sharepoint-documents"

    # Search tuning
    "RERANKER_THRESHOLD" = "0"

    # SP sync config
    "SP_SITE_HOSTNAME"    = var.sp_site_hostname
    "SP_SITE_PATH"        = var.sp_site_path
    "SP_DOCUMENT_LIBRARY" = var.sp_document_library
  }

  tags = local.tags
}
