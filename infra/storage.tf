# Storage (文書用) — 既存リソースを terraform import で管理下に
# import command:
#   terraform import azurerm_storage_account.docs /subscriptions/<SUB_ID>/resourceGroups/rg-sprag-poc-jpe/providers/Microsoft.Storage/storageAccounts/stspragpocjpe
#   terraform import azurerm_storage_container.documents https://stspragpocjpe.blob.core.windows.net/sharepoint-documents
resource "azurerm_storage_account" "docs" {
  name                     = "stspragpocjpe"
  resource_group_name      = data.azurerm_resource_group.main.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = local.tags
}

resource "azurerm_storage_container" "documents" {
  name               = "sharepoint-documents"
  storage_account_id = azurerm_storage_account.docs.id
}

# Storage (Functions 用) — 新規作成
resource "azurerm_storage_account" "functions" {
  name                     = "stfuncspragpoc"
  resource_group_name      = data.azurerm_resource_group.main.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = local.tags
}
