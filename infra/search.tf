# AI Search — Basic (ベクトル検索・セマンティック検索対応、PoC 規模で十分)
# Basic: 15 indexes, 5 indexers, 2GB/index — PoC (1 index, 2 indexers, 275 docs) は制限内
# SKU 変更はサービス再作成が必要（terraform apply で自動的に destroy/create）
resource "azurerm_search_service" "main" {
  name                = "srch-${var.project}-jpe"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.location
  sku                 = "basic"

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

# Search オブジェクト (index / datasource / skillset / indexer)
# → scripts/deploy-search-objects.sh で手動デプロイ
# Terraform の local-exec provisioner は Windows 互換性問題があるため、
# Search objects は Terraform 管理外とし、rebuild.sh に統合する
