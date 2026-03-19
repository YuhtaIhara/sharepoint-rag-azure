# Document Intelligence — S0 (DI Layout スキル用)
resource "azurerm_cognitive_account" "di" {
  name                  = "di-${var.project}-jpe"
  resource_group_name   = data.azurerm_resource_group.main.name
  location              = var.location
  kind                  = "FormRecognizer"
  sku_name              = "S0"
  custom_subdomain_name = "di-${var.project}-jpe"
  tags                  = local.tags
}
