#!/usr/bin/env bash
# rebuild.sh — teardown 後のフル再構築を一発で実行
#
# 前提:
#   - teardown.sh 済み（Storage + Entra ID App のみ残存）
#   - az login 済み
#   - terraform.tfvars が設定済み
#
# Usage: bash scripts/rebuild.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
INFRA_DIR="$ROOT_DIR/infra"
SEARCH_DIR="$ROOT_DIR/search"

SUB="REDACTED_SUBSCRIPTION_ID"
RG="rg-sprag-poc-jpe"

echo "=== [1/8] Cognitive Services 論理削除からの復元 ==="
echo "  (purge 権限がないため restore:true で復元)"
for name_loc_kind in "cog-sprag-poc-jpe:japaneast:CognitiveServices" "di-sprag-poc-jpe:japaneast:FormRecognizer" "oai-sprag-poc-eastus2:eastus2:OpenAI"; do
  name="${name_loc_kind%%:*}"
  rest="${name_loc_kind#*:}"
  loc="${rest%%:*}"
  kind="${rest##*:}"

  # 論理削除状態か確認
  DELETED=$(az cognitiveservices account list-deleted --query "[?name=='$name'].name" -o tsv 2>/dev/null || echo "")
  if [ -n "$DELETED" ]; then
    echo "  restore: $name ($loc, $kind)"
    MSYS_NO_PATHCONV=1 az rest --method PUT \
      --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$name?api-version=2023-05-01" \
      --body "{\"location\":\"$loc\",\"kind\":\"$kind\",\"sku\":{\"name\":\"S0\"},\"properties\":{\"restore\":true,\"customSubDomainName\":\"$name\"}}" \
      -o none 2>&1 || echo "  (既に存在 or 復元失敗)"
  else
    echo "  skip: $name (not in deleted state)"
  fi
done

echo ""
echo "=== [2/8] KV secrets 論理削除の purge ==="
# KV が存在する場合のみ
if az keyvault show --name kv-sprag-poc-jpe --resource-group "$RG" > /dev/null 2>&1; then
  for secret in AZURE-OPENAI-KEY AZURE-OPENAI-ENDPOINT SEARCH-API-KEY SEARCH-ENDPOINT COSMOS-CONNECTION-STRING STORAGE-CONNECTION-STRING GRAPH-CLIENT-ID GRAPH-CLIENT-SECRET GRAPH-TENANT-ID; do
    az keyvault secret delete --vault-name kv-sprag-poc-jpe --name "$secret" 2>/dev/null || true
    az keyvault secret purge --vault-name kv-sprag-poc-jpe --name "$secret" 2>/dev/null || true
  done
  echo "  KV secrets purged"
else
  echo "  skip: KV not found (will be created by terraform)"
fi

echo ""
echo "=== [3/8] Terraform init ==="
cd "$INFRA_DIR"
terraform init -input=false

echo ""
echo "=== [4/8] Terraform state cleanup + import ==="
# 復元した Cognitive Services を import（state になければ）
for res_id in \
  "azurerm_cognitive_account.cognitive:/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/cog-sprag-poc-jpe" \
  "azurerm_cognitive_account.di:/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/di-sprag-poc-jpe" \
  "azurerm_cognitive_account.openai:/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/oai-sprag-poc-eastus2"; do
  res="${res_id%%:*}"
  id="${res_id#*:}"
  if ! terraform state show "$res" > /dev/null 2>&1; then
    echo "  import: $res"
    MSYS_NO_PATHCONV=1 terraform import "$res" "$id" || true
  fi
done

# OpenAI deployments (復元時に一緒に戻る)
for res_id in \
  "azurerm_cognitive_deployment.gpt4o_mini:/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/oai-sprag-poc-eastus2/deployments/gpt-4o-mini" \
  "azurerm_cognitive_deployment.embedding:/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/oai-sprag-poc-eastus2/deployments/text-embedding-3-large"; do
  res="${res_id%%:*}"
  id="${res_id#*:}"
  if ! terraform state show "$res" > /dev/null 2>&1; then
    echo "  import: $res"
    MSYS_NO_PATHCONV=1 terraform import "$res" "$id" || true
  fi
done

echo ""
echo "=== [5/8] Terraform apply ==="
terraform apply -auto-approve

echo ""
echo "=== [6/8] Search objects デプロイ ==="
SEARCH_ENDPOINT=$(terraform output -raw search_endpoint)
SEARCH_KEY=$(az search admin-key show --resource-group "$RG" --service-name srch-sprag-poc-jpe --query primaryKey -o tsv)
OPENAI_ENDPOINT=$(terraform output -raw openai_endpoint)
OPENAI_KEY=$(az cognitiveservices account keys list --resource-group "$RG" --name oai-sprag-poc-eastus2 --query key1 -o tsv)

API_VERSION="2024-07-01"
cd "$ROOT_DIR"

# Index
echo "  index..."
INDEX_JSON=$(python3 -c "
import json
with open('search/index.json','r',encoding='utf-8') as f: data=json.load(f)
raw=json.dumps(data,ensure_ascii=True)
raw=raw.replace('\${AZURE_OPENAI_ENDPOINT}','$OPENAI_ENDPOINT')
raw=raw.replace('\${AZURE_OPENAI_API_KEY}','$OPENAI_KEY')
print(raw)
")
curl -sf -X PUT "${SEARCH_ENDPOINT}/indexes/sprag-index?api-version=${API_VERSION}" \
  -H "api-key: ${SEARCH_KEY}" -H "Content-Type: application/json" \
  -d "$INDEX_JSON" -o /dev/null
echo "  OK"

# Datasource
echo "  datasource..."
DS_JSON=$(python3 -c "
import json
with open('search/datasource.json','r',encoding='utf-8') as f: data=json.load(f)
raw=json.dumps(data,ensure_ascii=True)
raw=raw.replace('\${SUBSCRIPTION_ID}','$SUB')
raw=raw.replace('\${RESOURCE_GROUP}','$RG')
raw=raw.replace('\${STORAGE_ACCOUNT_NAME}','stspragpocjpe')
print(raw)
")
curl -sf -X PUT "${SEARCH_ENDPOINT}/datasources/sprag-datasource?api-version=${API_VERSION}" \
  -H "api-key: ${SEARCH_KEY}" -H "Content-Type: application/json" \
  -d "$DS_JSON" -o /dev/null
echo "  OK"

# Skillset
echo "  skillset..."
SKILL_JSON=$(python3 -c "
import json,os
with open('search/skillset.json','r',encoding='utf-8') as f: data=json.load(f)
raw=json.dumps(data,ensure_ascii=True)
raw=raw.replace('\${AZURE_OPENAI_ENDPOINT}','$OPENAI_ENDPOINT')
raw=raw.replace('\${AZURE_OPENAI_API_KEY}','$OPENAI_KEY')
print(raw)
")
curl -sf -X PUT "${SEARCH_ENDPOINT}/skillsets/sprag-skillset?api-version=${API_VERSION}" \
  -H "api-key: ${SEARCH_KEY}" -H "Content-Type: application/json" \
  -d "$SKILL_JSON" -o /dev/null
echo "  OK"

# Indexer
echo "  indexer..."
curl -sf -X PUT "${SEARCH_ENDPOINT}/indexers/sprag-indexer?api-version=${API_VERSION}" \
  -H "api-key: ${SEARCH_KEY}" -H "Content-Type: application/json" \
  -d @search/indexer.json -o /dev/null
echo "  OK"

echo ""
echo "=== [7/8] セマンティック検索有効化 ==="
az search service update --resource-group "$RG" --name srch-sprag-poc-jpe --semantic-search free -o none 2>&1
echo "  OK"

echo ""
echo "=== [8/8] インデクサー実行 ==="
curl -sf -X POST "${SEARCH_ENDPOINT}/indexers/sprag-indexer/run?api-version=${API_VERSION}" \
  -H "api-key: ${SEARCH_KEY}" -H "Content-Type: application/json" || echo "  (already running)"
echo ""
echo "  インデクサーを手動トリガーしました"

echo ""
echo "=== rebuild 完了 ==="
echo "インデクサーがバックグラウンドで実行中。完了後に検証してください。"
echo "検証: https://app-sprag-poc-ea.azurewebsites.net"
