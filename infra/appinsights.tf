# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.project}-jpe"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# Application Insights
resource "azurerm_application_insights" "main" {
  name                = "appi-${var.project}-jpe"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = local.tags
}
