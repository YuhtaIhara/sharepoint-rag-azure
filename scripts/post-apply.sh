#!/usr/bin/env bash
# post-apply.sh — terraform apply 後の初回セットアップ
#
# Terraform ではカバーされない設定を実行:
#   1. Entra ID 認証設定 (App Service)
#   2. Entra ID リダイレクト URI 更新
#   3. インデクサー初回実行 (DI + fallback)
#   4. インデクサー完了待ち
#   5. ACL メタデータ初回更新
#
# Prerequisites:
#   - terraform apply 完了済み
#   - az login 済み
#   - .env に SEARCH_ENDPOINT, SEARCH_API_KEY, STORAGE_CONNECTION_STRING が設定済み
#
# Usage: bash scripts/post-apply.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/../infra"

# Terraform output から値を取得
cd "$INFRA_DIR"
WEBAPP_NAME=$(terraform output -raw webapp_hostname | sed 's/.azurewebsites.net//')
WEBAPP_URL=$(terraform output -raw webapp_url)
FUNCTIONS_NAME=$(terraform output -raw functions_hostname | sed 's/.azurewebsites.net//')
RG=$(terraform output -raw resource_group)
cd "$SCRIPT_DIR"

echo "=== 1/5 Entra ID 認証設定 (App Service) ==="
az webapp auth update \
  --name "$WEBAPP_NAME" \
  --resource-group "$RG" \
  --enabled true \
  --action LoginWithAzureActiveDirectory \
  --aad-allowed-token-audiences "$WEBAPP_URL" \
  --aad-token-issuer-url "https://sts.windows.net/$(az account show --query tenantId -o tsv)/"
echo "  認証設定完了"

echo "=== 2/5 Entra ID リダイレクト URI 更新 ==="
APP_ID=$(cd "$INFRA_DIR" && terraform output -raw webapp_hostname | xargs -I {} echo "https://{}")
echo "  リダイレクト URI: ${WEBAPP_URL}/.auth/login/aad/callback"
echo "  → Azure Portal > App registrations > app-sprag-poc > Authentication で手動設定してください"
echo "  (Graph API での自動設定はアプリ権限が必要なため手動推奨)"

echo "=== 3/5 インデクサー初回実行 ==="
# .env から Search 設定を読み込み
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a; source "$SCRIPT_DIR/.env"; set +a
fi
: "${SEARCH_ENDPOINT:?SEARCH_ENDPOINT is required (set in .env or environment)}"
: "${SEARCH_API_KEY:?SEARCH_API_KEY is required (set in .env or environment)}"

API_VERSION="2025-05-01-Preview"

echo "  DI インデクサー実行..."
curl -sf -X POST "${SEARCH_ENDPOINT}/indexers/sprag-indexer/run?api-version=${API_VERSION}" \
  -H "api-key: ${SEARCH_API_KEY}" -H "Content-Type: application/json" || echo "  (実行済みまたはエラー)"

echo "  Fallback インデクサー実行..."
curl -sf -X POST "${SEARCH_ENDPOINT}/indexers/sprag-indexer-fallback/run?api-version=${API_VERSION}" \
  -H "api-key: ${SEARCH_API_KEY}" -H "Content-Type: application/json" || echo "  (実行済みまたはエラー)"

echo "=== 4/5 インデクサー完了待ち ==="
echo "  sprag-indexer の完了を待機中..."
for i in $(seq 1 30); do
  STATUS=$(curl -sf "${SEARCH_ENDPOINT}/indexers/sprag-indexer/status?api-version=${API_VERSION}" \
    -H "api-key: ${SEARCH_API_KEY}" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('lastResult',{}).get('status','unknown'))" 2>/dev/null || echo "unknown")

  if [ "$STATUS" = "success" ] || [ "$STATUS" = "transientFailure" ]; then
    echo "  インデクサー完了: $STATUS"
    break
  fi
  echo "  状態: $STATUS (${i}/30 - 30秒待機)"
  sleep 30
done

echo "=== 5/5 ACL メタデータ初回更新 ==="
cd "$SCRIPT_DIR"
if [ -f "requirements.txt" ]; then
  pip install -q -r requirements.txt 2>/dev/null || true
fi
python3 update_index_metadata.py

echo ""
echo "=== post-apply 完了 ==="
echo "検証: ${WEBAPP_URL} にアクセスして動作確認してください"
