#!/usr/bin/env bash
# cleanup.sh — terraform apply 前のリソース削除
#
# 残すリソース:
#   - stspragpocjpe (Storage 文書用) → terraform import で管理下に
#   - app-sprag-poc (Entra ID App)  → data 参照
#
# Usage: bash infra/cleanup.sh

set -euo pipefail

RG="rg-sprag-poc-jpe"

echo "=== Step 0: terraform apply 前のクリーンアップ ==="
echo "Resource Group: $RG"
echo ""

# 現在のリソース確認
echo "--- 現在のリソース一覧 ---"
az resource list --resource-group "$RG" --output table
echo ""

confirm() {
  read -r -p "続行しますか？ [y/N] " response
  case "$response" in
    [yY]) return 0 ;;
    *) echo "中断しました"; exit 1 ;;
  esac
}

confirm

# 1. Functions App
echo "=== 1/10 Functions App 削除 ==="
az functionapp delete --name "func-sprag-poc-ea" --resource-group "$RG" 2>/dev/null || echo "  (存在しないかすでに削除済み)"

# 2. Service Plan (Functions 付随)
echo "=== 2/10 Service Plan 削除 ==="
az appservice plan delete --name "plan-func-sprag-poc-ea" --resource-group "$RG" --yes 2>/dev/null || echo "  (存在しないかすでに削除済み)"

# 3. Functions 用 Storage
echo "=== 3/10 Functions Storage 削除 ==="
az storage account delete --name "stfuncspragpoc" --resource-group "$RG" --yes 2>/dev/null || echo "  (存在しないかすでに削除済み)"

# 4. Azure OpenAI
echo "=== 4/10 Azure OpenAI 削除 ==="
az cognitiveservices account delete --name "yiha-mmt0c1uq-eastus2" --resource-group "$RG" 2>/dev/null || echo "  (存在しないかすでに削除済み)"

# 5. Document Intelligence
echo "=== 5/10 Document Intelligence 削除 ==="
az cognitiveservices account delete --name "di-sprag-poc-jpe" --resource-group "$RG" 2>/dev/null || echo "  (存在しないかすでに削除済み)"

# 6. Cognitive Services
echo "=== 6/10 Cognitive Services 削除 ==="
az cognitiveservices account delete --name "cog-sprag-poc-jpe" --resource-group "$RG" 2>/dev/null || echo "  (存在しないかすでに削除済み)"

# 7. Cosmos DB
echo "=== 7/10 Cosmos DB 削除 (数分かかる場合があります) ==="
az cosmosdb delete --name "cosmos-sprag-poc-jpe" --resource-group "$RG" --yes 2>/dev/null || echo "  (存在しないかすでに削除済み)"

# 8. App Insights (複数コンポーネント)
echo "=== 8/10 App Insights 削除 ==="
for name in "appi-sprag-poc-jpe" "app-sprag-poc-jpe" "func-sprag-poc-jpe"; do
  az monitor app-insights component delete --app "$name" --resource-group "$RG" 2>/dev/null || true
done

# 9. Log Analytics Workspace
echo "=== 9/10 Log Analytics Workspace 削除 ==="
# 自動生成された workspace を検索して削除
for ws in $(az monitor log-analytics workspace list --resource-group "$RG" --query "[].name" -o tsv 2>/dev/null); do
  echo "  削除: $ws"
  az monitor log-analytics workspace delete --workspace-name "$ws" --resource-group "$RG" --force --yes 2>/dev/null || true
done

# 10. Key Vault (論理削除 + purge)
echo "=== 10/10 Key Vault 削除 + purge ==="
az keyvault delete --name "kv-sprag-poc-jpe" --resource-group "$RG" 2>/dev/null || echo "  (存在しないかすでに削除済み)"
az keyvault purge --name "kv-sprag-poc-jpe" 2>/dev/null || echo "  (purge 不要またはすでに purge 済み)"

# Cognitive Services の purge (論理削除から完全削除)
echo "=== Cognitive Services purge ==="
for name in "yiha-mmt0c1uq-eastus2" "di-sprag-poc-jpe" "cog-sprag-poc-jpe"; do
  echo "  purge: $name"
  location=$(az cognitiveservices account list-deleted --query "[?name=='$name'].location" -o tsv 2>/dev/null || echo "")
  if [ -n "$location" ]; then
    az cognitiveservices account purge --name "$name" --resource-group "$RG" --location "$location" 2>/dev/null || true
  fi
done

echo ""
echo "=== クリーンアップ完了 ==="
echo ""
echo "--- 残りのリソース ---"
az resource list --resource-group "$RG" --output table
echo ""
echo "期待: stspragpocjpe (Storage) のみ残存"
echo "次のステップ: cd infra && terraform init && terraform import ..."
