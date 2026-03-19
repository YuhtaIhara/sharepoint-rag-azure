# Cosmos DB — サーバーレス (PoC 向け低コスト)
resource "azurerm_cosmosdb_account" "main" {
  name                = "cosmos-${var.project}-jpe"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.location
  offer_type          = "Standard"

  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  tags = local.tags
}

resource "azurerm_cosmosdb_sql_database" "chat" {
  name                = "ChatDB"
  resource_group_name = data.azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

resource "azurerm_cosmosdb_sql_container" "conversations" {
  name                = "conversations"
  resource_group_name = data.azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.chat.name
  partition_key_paths = ["/sessionId"]
}
