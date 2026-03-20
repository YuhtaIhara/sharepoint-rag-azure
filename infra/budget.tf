# Budget Alert — コスト超過の早期検知
resource "azurerm_consumption_budget_resource_group" "poc" {
  name              = "budget-${var.project}"
  resource_group_id = data.azurerm_resource_group.main.id
  amount            = 15000
  time_grain        = "Monthly"

  time_period {
    start_date = "2026-04-01T00:00:00Z"
  }

  notification {
    threshold      = 80
    operator       = "GreaterThan"
    contact_emails = [var.alert_email]
  }

  notification {
    threshold      = 100
    operator       = "GreaterThan"
    contact_emails = [var.alert_email]
  }
}
