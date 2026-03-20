#!/usr/bin/env bash
# rebuild.sh — teardown 後のフル再構築 or 差分再インデックス
#
# 前提:
#   - teardown.sh 済み（Storage + Entra ID App のみ残存）
#   - az login 済み
#   - terraform.tfvars が設定済み
#
# Usage:
#   bash scripts/rebuild.sh                    # 差分再インデックス（変更検知により変更分のみ処理）
#   FORCE_REINDEX=true bash scripts/rebuild.sh # フルリビルド（インデックス削除→全件再処理）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
INFRA_DIR="$ROOT_DIR/infra"
SEARCH_DIR="$ROOT_DIR/search"

SUB=$(az account show --query id -o tsv)
RG="rg-sprag-poc-jpe"
FORCE_REINDEX="${FORCE_REINDEX:-false}"

if [ "$FORCE_REINDEX" = "true" ]; then
  echo "*** FORCE_REINDEX=true: フルリビルド（インデックス削除→全件再処理）***"
else
  echo "*** 差分再インデックス（変更があったドキュメントのみ処理）***"
fi
echo ""

echo "=== [1/13] Cognitive Services 論理削除からの復元 ==="
echo "  (purge 権限がないため restore:true で復元)"
for name_loc_kind in "cog-sprag-poc-jpe:japaneast:CognitiveServices" "oai-sprag-poc-eastus2:eastus2:OpenAI"; do
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
echo "=== [2/13] KV secrets 論理削除の purge ==="
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
echo "=== [3/13] Terraform init ==="
cd "$INFRA_DIR"
terraform init -input=false

echo ""
echo "=== [4/13] Terraform state cleanup + import ==="
# 復元した Cognitive Services を import（state になければ）
for res_id in \
  "azurerm_cognitive_account.cognitive:/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/cog-sprag-poc-jpe" \
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
echo "=== [5/13] Terraform apply ==="
terraform apply -auto-approve

echo ""
echo "=== [6/13] Search objects デプロイ ==="
SEARCH_ENDPOINT=$(terraform output -raw search_endpoint)
SEARCH_KEY=$(az search admin-key show --resource-group "$RG" --service-name srch-sprag-poc-jpe --query primaryKey -o tsv)
OPENAI_ENDPOINT=$(terraform output -raw openai_endpoint)
OPENAI_KEY=$(az cognitiveservices account keys list --resource-group "$RG" --name oai-sprag-poc-eastus2 --query key1 -o tsv)
COG_KEY=$(az cognitiveservices account keys list --resource-group "$RG" --name cog-sprag-poc-jpe --query key1 -o tsv)

API_VERSION="2025-05-01-Preview"
cd "$ROOT_DIR"

deploy_search_object() {
  local type="$1" name="$2" file="$3"
  echo "  ${type}: ${name}..."
  local JSON
  JSON=$(python3 -c "
import json
with open('${file}','r',encoding='utf-8') as f: data=json.load(f)
raw=json.dumps(data,ensure_ascii=True)
raw=raw.replace('\${AZURE_OPENAI_ENDPOINT}','$OPENAI_ENDPOINT')
raw=raw.replace('\${AZURE_OPENAI_API_KEY}','$OPENAI_KEY')
raw=raw.replace('\${COGNITIVE_SERVICES_KEY}','$COG_KEY')
raw=raw.replace('\${SUBSCRIPTION_ID}','$SUB')
raw=raw.replace('\${RESOURCE_GROUP}','$RG')
raw=raw.replace('\${STORAGE_ACCOUNT_NAME}','stspragpocjpe')
print(raw)
")
  curl -sf -X PUT "${SEARCH_ENDPOINT}/${type}/${name}?api-version=${API_VERSION}" \
    -H "api-key: ${SEARCH_KEY}" -H "Content-Type: application/json" \
    -d "$JSON" -o /dev/null
  echo "  OK"
}

# シノニムマップ（インデックスが参照するため先に作成）
# ※ 日本語を含むため変数渡しだと文字化けする → ファイル経由で送信
echo "  synonym map: jp-enterprise-synonyms..."
SYNONYM_TMP="${TEMP:-/tmp}/synonyms_out.json"
python3 -c "
import json, os
with open('search/synonyms.json','r',encoding='utf-8') as f: data=json.load(f)
out = os.environ.get('TEMP', '/tmp') + '/synonyms_out.json'
with open(out,'w',encoding='utf-8') as f: json.dump(data,f,ensure_ascii=False)
"
curl -sf -X PUT "${SEARCH_ENDPOINT}/synonymmaps/jp-enterprise-synonyms?api-version=${API_VERSION}" \
  -H "api-key: ${SEARCH_KEY}" -H "Content-Type: application/json; charset=utf-8" \
  --data-binary "@${SYNONYM_TMP}" -o /dev/null
echo "  OK"

if [ "$FORCE_REINDEX" = "true" ]; then
  echo "  Deleting existing index for clean recreation..."
  curl -sf -X DELETE "${SEARCH_ENDPOINT}/indexes/sprag-index?api-version=${API_VERSION}" \
    -H "api-key: ${SEARCH_KEY}" -o /dev/null 2>/dev/null || echo "  (index not found, skip)"
else
  echo "  Incremental mode: index DELETE をスキップ"
fi

# Index
deploy_search_object "indexes" "sprag-index" "search/index.json"

# Datasource
deploy_search_object "datasources" "sprag-datasource" "search/datasource.json"

# Primary skillset (DI Layout)
deploy_search_object "skillsets" "sprag-skillset" "search/skillset.json"

# Fallback skillset (SplitSkill for .doc/.csv)
deploy_search_object "skillsets" "sprag-skillset-fallback" "search/skillset-fallback.json"

# Primary indexer (DI Layout: .pdf, .docx, .xlsx, .pptx)
deploy_search_object "indexers" "sprag-indexer" "search/indexer.json"

# Fallback indexer (.doc, .csv)
deploy_search_object "indexers" "sprag-indexer-fallback" "search/indexer-fallback.json"

echo ""
echo "=== [7/13] セマンティック検索有効化 ==="
az search service update --resource-group "$RG" --name srch-sprag-poc-jpe --semantic-search free -o none 2>&1
echo "  OK"

echo ""
echo "=== [8/13] インデクサーリセット + 実行 ==="
if [ "$FORCE_REINDEX" = "true" ]; then
  echo "  resetting indexers (force full reprocess)..."
  curl -sf -X POST "${SEARCH_ENDPOINT}/indexers/sprag-indexer/reset?api-version=${API_VERSION}" \
    -H "api-key: ${SEARCH_KEY}" -H "Content-Type: application/json" -H "Content-Length: 0" || true
  curl -sf -X POST "${SEARCH_ENDPOINT}/indexers/sprag-indexer-fallback/reset?api-version=${API_VERSION}" \
    -H "api-key: ${SEARCH_KEY}" -H "Content-Type: application/json" -H "Content-Length: 0" || true
else
  echo "  Incremental mode: indexer reset をスキップ（変更検知で差分処理）"
fi
echo "  triggering indexers..."
curl -sf -X POST "${SEARCH_ENDPOINT}/indexers/sprag-indexer/run?api-version=${API_VERSION}" \
  -H "api-key: ${SEARCH_KEY}" -H "Content-Type: application/json" -H "Content-Length: 0" || echo "  (already running)"
curl -sf -X POST "${SEARCH_ENDPOINT}/indexers/sprag-indexer-fallback/run?api-version=${API_VERSION}" \
  -H "api-key: ${SEARCH_KEY}" -H "Content-Type: application/json" -H "Content-Length: 0" || echo "  (already running)"

echo ""
echo "=== [9/13] インデクサー完了待ち ==="
wait_indexer() {
  local name="$1" max_wait=1800 elapsed=0
  echo "  waiting for $name..."
  while [ $elapsed -lt $max_wait ]; do
    STATUS=$(curl -sf "${SEARCH_ENDPOINT}/indexers/${name}/status?api-version=${API_VERSION}" \
      -H "api-key: ${SEARCH_KEY}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('lastResult',{}).get('status','unknown'))" 2>/dev/null || echo "unknown")
    if [ "$STATUS" = "success" ]; then
      echo "  $name: $STATUS (${elapsed}s)"
      return 0
    fi
    sleep 15
    elapsed=$((elapsed + 15))
    echo "  $name: running... (${elapsed}s)"
  done
  echo "  WARNING: $name がタイムアウト（${max_wait}s）"
  return 1
}
wait_indexer "sprag-indexer"
wait_indexer "sprag-indexer-fallback"

echo ""
echo "=== [10/13] ACL メタデータ同期 ==="
echo "  Blob → Index のメタデータ同期（allowed_groups, category, source_url）..."
cd "$ROOT_DIR"
python3 scripts/update_index_metadata.py
echo "  OK"

echo ""
echo "=== [11/13] FUNCTIONS_KEY 設定 ==="
FUNC_NAME="func-${PROJECT:-sprag-poc}-ea"
WEBAPP_NAME="app-${PROJECT:-sprag-poc}-ea"

FUNCTIONS_KEY=$(az functionapp keys list \
  --name "$FUNC_NAME" \
  --resource-group "$RG" \
  --query "functionKeys.default" -o tsv 2>/dev/null || echo "")

if [ -n "$FUNCTIONS_KEY" ]; then
  az webapp config appsettings set \
    --name "$WEBAPP_NAME" \
    --resource-group "$RG" \
    --settings "FUNCTIONS_KEY=$FUNCTIONS_KEY" \
    -o none
  echo "  FUNCTIONS_KEY set on $WEBAPP_NAME"
else
  echo "  WARNING: FUNCTIONS_KEY を取得できませんでした"
  echo "  CI/CD デプロイ後に以下を実行:"
  echo "    FKEY=\$(az functionapp keys list --name $FUNC_NAME -g $RG --query 'functionKeys.default' -o tsv)"
  echo "    az webapp config appsettings set --name $WEBAPP_NAME -g $RG --settings \"FUNCTIONS_KEY=\$FKEY\""
fi

echo ""
echo "=== [12/13] EasyAuth v2 設定 ==="
WEBAPP_NAME="app-${PROJECT:-sprag-poc}-ea"
ENTRA_CLIENT_ID=$(az keyvault secret show --vault-name kv-sprag-poc-jpe --name GRAPH-CLIENT-ID --query value -o tsv 2>/dev/null || echo "")
TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null)
CLIENT_SECRET=$(az keyvault secret show --vault-name kv-sprag-poc-jpe --name GRAPH-CLIENT-SECRET --query value -o tsv 2>/dev/null || echo "")

if [ -n "$CLIENT_SECRET" ]; then
  # v2 にアップグレード（既に v2 なら no-op）
  az webapp auth config-version upgrade -n "$WEBAPP_NAME" -g "$RG" -o none 2>/dev/null || true
  # Microsoft プロバイダー設定
  az webapp auth microsoft update \
    -n "$WEBAPP_NAME" -g "$RG" \
    --client-id "$ENTRA_CLIENT_ID" \
    --client-secret "$CLIENT_SECRET" \
    --issuer "https://login.microsoftonline.com/${TENANT_ID}/v2.0" \
    --yes -o none 2>&1
  # 認証有効化
  az webapp auth update -n "$WEBAPP_NAME" -g "$RG" --enabled true -o none 2>&1
  echo "  EasyAuth v2 configured (Entra ID SSO)"
else
  echo "  WARNING: CLIENT_SECRET を取得できませんでした（KV アクセス不可）"
  echo "  手動で設定してください"
fi

echo ""
echo "=== [13/13] デプロイ状態確認 ==="
echo "  Primary indexer status:"
curl -sf "${SEARCH_ENDPOINT}/indexers/sprag-indexer/status?api-version=${API_VERSION}" \
  -H "api-key: ${SEARCH_KEY}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'    status={d[\"status\"]}, lastResult={d.get(\"lastResult\",{}).get(\"status\",\"none\")}')"
echo ""

echo "=== rebuild 完了 ==="
echo "インデクサーがバックグラウンドで実行中（DI Layout: ~20-30分）"
echo ""
echo "次のステップ:"
echo "  1. gh workflow run 'Deploy Functions' --repo YuhtaIhara/sharepoint-rag-azure"
echo "  2. gh workflow run 'Deploy Webapp' --repo YuhtaIhara/sharepoint-rag-azure"
echo "  3. https://app-sprag-poc-ea.azurewebsites.net で動作確認"
