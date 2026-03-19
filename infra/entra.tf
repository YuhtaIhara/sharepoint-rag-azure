# Entra ID App — 既存リソース参照（温存）
data "azuread_application" "main" {
  display_name = var.entra_app_display_name
}
