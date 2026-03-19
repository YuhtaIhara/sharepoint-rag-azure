variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Existing Resource Group name"
  type        = string
  default     = "rg-sprag-poc-jpe"
}

variable "location" {
  description = "Primary Azure region"
  type        = string
  default     = "japaneast"
}

variable "openai_location" {
  description = "Azure OpenAI region (model availability determines region)"
  type        = string
  default     = "eastus2"
}

variable "webapp_location" {
  description = "App Service region (Japan East quota unavailable, using East Asia)"
  type        = string
  default     = "eastasia"
}

variable "project" {
  description = "Project identifier used in resource naming"
  type        = string
  default     = "sprag-poc"
}

variable "graph_client_secret" {
  description = "Entra ID App client secret for Graph API (sp_to_blob sync)"
  type        = string
  sensitive   = true
}

variable "entra_app_display_name" {
  description = "Display name of existing Entra ID application"
  type        = string
  default     = "app-sprag-poc"
}

variable "sp_site_hostname" {
  description = "SharePoint site hostname for sync trigger"
  type        = string
  default     = ""
}

variable "sp_site_path" {
  description = "SharePoint site path"
  type        = string
  default     = ""
}

variable "sp_document_library" {
  description = "SharePoint document library name"
  type        = string
  default     = "Shared Documents"
}
