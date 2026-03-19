# App Service Plan — B1 (East Asia: Japan East quota unavailable)
resource "azurerm_service_plan" "webapp" {
  name                = "plan-app-${var.project}-ea"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.webapp_location
  os_type             = "Linux"
  sku_name            = "B1"
  tags                = local.tags
}

# App Service (webapp)
resource "azurerm_linux_web_app" "main" {
  name                = "app-${var.project}-ea"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.webapp_location
  service_plan_id     = azurerm_service_plan.webapp.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      node_version = "22-lts"
    }
  }

  app_settings = {
    "BACKEND_API_URL" = "https://${azurerm_linux_function_app.main.default_hostname}"
    "FUNCTIONS_KEY"   = "" # Set after first deployment via post-apply.sh
  }

  tags = local.tags
}
