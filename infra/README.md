# Infrastructure as Code (Terraform)

13 Azure リソース + RBAC 10件 + Key Vault シークレット 9件 + AI Search オブジェクト 6件を宣言的に管理する。

## Quick Start

```bash
# 1. クリーンアップ（壊れた環境がある場合）
bash cleanup.sh

# 2. 初期化
terraform init

# 3. 既存 Storage を import
terraform import azurerm_storage_account.docs \
  /subscriptions/<SUB_ID>/resourceGroups/rg-sprag-poc-jpe/providers/Microsoft.Storage/storageAccounts/stspragpocjpe
terraform import azurerm_storage_container.documents \
  https://stspragpocjpe.blob.core.windows.net/sharepoint-documents

# 4. tfvars 設定
cp terraform.tfvars.example terraform.tfvars
# subscription_id, graph_client_secret を記入

# 5. デプロイ
terraform plan
terraform apply
```

## ファイル構成

| ファイル | 内容 |
|---------|------|
| `providers.tf` | azurerm + azuread provider |
| `variables.tf` | 全入力変数 |
| `main.tf` | Resource Group (data) + 共通タグ |
| `entra.tf` | Entra ID アプリ参照 (data) |
| `openai.tf` | Azure OpenAI + モデル x2 |
| `di.tf` | Document Intelligence S0 |
| `cognitive.tf` | Cognitive Services マルチサービス S0 |
| `storage.tf` | Storage x2 (文書用=import, Functions用) |
| `search.tf` | AI Search S1 + search objects |
| `cosmosdb.tf` | Cosmos DB サーバーレス |
| `keyvault.tf` | Key Vault + シークレット 9件 |
| `appinsights.tf` | Application Insights + Log Analytics |
| `functions.tf` | Functions (Y1) + KV参照アプリ設定 |
| `appservice.tf` | App Service (B1, East Asia) |
| `rbac.tf` | RBAC 10件 |
| `outputs.tf` | エンドポイント出力 |
| `cleanup.sh` | apply 前のリソース削除 |
