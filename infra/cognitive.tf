# Cognitive Services マルチサービス — DI Layout スキルの課金先
resource "azurerm_cognitive_account" "cognitive" {
  name                  = "cog-${var.project}-jpe"
  resource_group_name   = data.azurerm_resource_group.main.name
  location              = var.location
  kind                  = "CognitiveServices"
  sku_name              = "S0"
  custom_subdomain_name = "cog-${var.project}-jpe"
  tags                  = local.tags
}
