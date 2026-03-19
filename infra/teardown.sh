#!/usr/bin/env bash
# teardown.sh — コスト止血用: 課金リソースを全て削除
#
# cleanup.sh との違い:
#   cleanup.sh = terraform apply 前のクリーンアップ（既存リソース掃除）
#   teardown.sh = apply 済み環境のコスト止血（高額リソースから順に削除）
#
# 残すリソース:
#   - stspragpocjpe (Storage 文書用) → terraform import で再管理
#   - app-sprag-poc (Entra ID App)  → data 参照（RG 外）
#
# 再構築: terraform apply 一発で復元可能
#
# Usage: bash infra/teardown.sh

set -euo pipefail

RG="rg-sprag-poc-jpe"

echo "=== コスト止血: 課金リソース削除 ==="
echo "Resource Group: $RG"
echo ""

echo "--- 現在のリソース一覧 ---"
az resource list --resource-group "$RG" --output table
echo ""

read -r -p "全課金リソースを削除します。続行？ [y/N] " response
case "$response" in
  [yY]) ;;
  *) echo "中断"; exit 1 ;;
esac

# === 優先度1: AI Search S1 (~$245/月, 停止不可) ===
echo ""
echo "=== [1] AI Search 削除 (~\$245/月) ==="
az search service delete --name "srch-sprag-poc-jpe" --resource-group "$RG" --yes 2>/dev/null \
  || echo "  (存在しないかすでに削除済み)"

# === 優先度2: App Service B1 (~$13/月) ===
echo "=== [2] App Service 削除 (~\$13/月) ==="
az webapp delete --name "app-sprag-poc-ea" --resource-group "$RG" 2>/dev/null \
  || echo "  (存在しないかすでに削除済み)"
az appservice plan delete --name "plan-app-sprag-poc-ea" --resource-group "$RG" --yes 2>/dev/null \
  || echo "  (存在しないかすでに削除済み)"

# === 優先度3: Functions (従量課金だが関連リソースあり) ===
echo "=== [3] Functions 削除 ==="
az functionapp delete --name "func-sprag-poc-ea" --resource-group "$RG" 2>/dev/null \
  || echo "  (存在しないかすでに削除済み)"
az appservice plan delete --name "plan-func-sprag-poc-ea" --resource-group "$RG" --yes 2>/dev/null \
  || echo "  (存在しないかすでに削除済み)"
az storage account delete --name "stfuncspragpoc" --resource-group "$RG" --yes 2>/dev/null \
  || echo "  (存在しないかすでに削除済み)"

# === 優先度4: Azure OpenAI (S0) ===
echo "=== [4] Azure OpenAI 削除 ==="
az cognitiveservices account delete --name "oai-sprag-poc-eastus2" --resource-group "$RG" 2>/dev/null \
  || echo "  (存在しないかすでに削除済み)"

# === 優先度5: Cognitive Services / Document Intelligence ===
echo "=== [5] Cognitive Services 削除 ==="
az cognitiveservices account delete --name "cog-sprag-poc-jpe" --resource-group "$RG" 2>/dev/null \
  || echo "  (存在しないかすでに削除済み)"
az cognitiveservices account delete --name "di-sprag-poc-jpe" --resource-group "$RG" 2>/dev/null \
  || echo "  (存在しないかすでに削除済み)"

# === 優先度6: Cosmos DB (Serverless, ほぼ $0 だが掃除) ===
echo "=== [6] Cosmos DB 削除 ==="
az cosmosdb delete --name "cosmos-sprag-poc-jpe" --resource-group "$RG" --yes 2>/dev/null \
  || echo "  (存在しないかすでに削除済み)"

# === 優先度7: 監視系 ===
echo "=== [7] App Insights + Log Analytics 削除 ==="
for name in "appi-sprag-poc-jpe" "app-sprag-poc-jpe" "func-sprag-poc-jpe"; do
  az monitor app-insights component delete --app "$name" --resource-group "$RG" 2>/dev/null || true
done
for ws in $(az monitor log-analytics workspace list --resource-group "$RG" --query "[].name" -o tsv 2>/dev/null); do
  az monitor log-analytics workspace delete --workspace-name "$ws" --resource-group "$RG" --force --yes 2>/dev/null || true
done

# === 優先度8: Key Vault secrets purge + KV 削除 ===
echo "=== [8] Key Vault secrets purge + KV 削除 ==="
# secrets を個別に削除+purge（KV 削除後だと purge できなくなるため先にやる）
for secret in AZURE-OPENAI-KEY AZURE-OPENAI-ENDPOINT SEARCH-API-KEY SEARCH-ENDPOINT COSMOS-CONNECTION-STRING STORAGE-CONNECTION-STRING GRAPH-CLIENT-ID GRAPH-CLIENT-SECRET GRAPH-TENANT-ID; do
  az keyvault secret delete --vault-name kv-sprag-poc-jpe --name "$secret" 2>/dev/null || true
  az keyvault secret purge --vault-name kv-sprag-poc-jpe --name "$secret" 2>/dev/null || true
done
echo "  secrets purged"
az keyvault delete --name "kv-sprag-poc-jpe" --resource-group "$RG" 2>/dev/null \
  || echo "  (存在しないかすでに削除済み)"
az keyvault purge --name "kv-sprag-poc-jpe" 2>/dev/null \
  || echo "  (purge 不要またはすでに purge 済み)"

# === Cognitive Services purge ===
echo "=== Cognitive Services purge ==="
for name in "oai-sprag-poc-eastus2" "cog-sprag-poc-jpe" "di-sprag-poc-jpe"; do
  location=$(az cognitiveservices account list-deleted --query "[?name=='$name'].location" -o tsv 2>/dev/null || echo "")
  if [ -n "$location" ]; then
    echo "  purge: $name ($location)"
    az cognitiveservices account purge --name "$name" --resource-group "$RG" --location "$location" 2>/dev/null || true
  fi
done

echo ""
echo "=== 止血完了 ==="
echo ""
echo "--- 残りのリソース ---"
az resource list --resource-group "$RG" --output table
echo ""
echo "期待: stspragpocjpe (Storage) のみ残存"
echo "再構築: cd infra && terraform init && terraform import ... && terraform apply"
