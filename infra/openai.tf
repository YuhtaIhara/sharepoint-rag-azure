# Azure OpenAI — East US 2 (model availability)
resource "azurerm_cognitive_account" "openai" {
  name                  = "oai-${var.project}-eastus2"
  resource_group_name   = data.azurerm_resource_group.main.name
  location              = var.openai_location
  kind                  = "OpenAI"
  sku_name              = "S0"
  custom_subdomain_name = "oai-${var.project}-eastus2"
  tags                  = local.tags
}

resource "azurerm_cognitive_deployment" "gpt4o_mini" {
  name                 = "gpt-4o-mini"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "gpt-4o-mini"
    version = "2024-07-18"
  }

  sku {
    name     = "Standard"
    capacity = 10
  }
}

resource "azurerm_cognitive_deployment" "embedding" {
  name                 = "text-embedding-3-large"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "text-embedding-3-large"
    version = "1"
  }

  sku {
    name     = "Standard"
    capacity = 10
  }

  depends_on = [azurerm_cognitive_deployment.gpt4o_mini]
}
