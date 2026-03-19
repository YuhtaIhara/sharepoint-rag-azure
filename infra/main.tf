data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

locals {
  tags = {
    Environment = "poc"
    Project     = var.project
    ManagedBy   = "terraform"
  }
}
