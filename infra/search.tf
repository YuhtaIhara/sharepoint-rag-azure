# AI Search — S1 (ベクトル検索・セマンティック検索対応)
resource "azurerm_search_service" "main" {
  name                = "srch-${var.project}-jpe"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.location
  sku                 = "standard"

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

# Search オブジェクト (index / datasource / skillset / indexer)
# → scripts/deploy-search-objects.sh で手動デプロイ
# Terraform の local-exec provisioner は Windows 互換性問題があるため、
# Search objects は Terraform 管理外とし、rebuild.sh に統合する
