#!/usr/bin/env bash
# AI Search リソースデプロイスクリプト
# Usage: ./deploy.sh [--run-indexer]
#
# 環境変数:
#   SEARCH_ENDPOINT  - AI Search エンドポイント (例: https://srch-sprag-poc-jpe.search.windows.net)
#   SEARCH_API_KEY   - AI Search 管理キー
#   AZURE_OPENAI_API_KEY - OpenAI API キー (skillset で使用)
#   DI_KEY           - Document Intelligence キー (skillset cognitiveServices で使用)
#   SUBSCRIPTION_ID  - Azure サブスクリプション ID (datasource で使用)

set -euo pipefail

API_VERSION="2024-07-01"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

: "${SEARCH_ENDPOINT:?SEARCH_ENDPOINT is required}"
: "${SEARCH_API_KEY:?SEARCH_API_KEY is required}"
: "${DI_KEY:?DI_KEY is required}"

header="api-key: ${SEARCH_API_KEY}"
ct="Content-Type: application/json"

envsubst_file() {
    envsubst < "$1"
}

echo "=== 1/4 Index 作成 ==="
curl -s -X PUT "${SEARCH_ENDPOINT}/indexes/sprag-index?api-version=${API_VERSION}" \
    -H "$header" -H "$ct" \
    -d "$(envsubst_file "${SCRIPT_DIR}/index.json")" | head -c 200
echo

echo "=== 2/4 Data Source 作成 ==="
curl -s -X PUT "${SEARCH_ENDPOINT}/datasources/sprag-datasource?api-version=${API_VERSION}" \
    -H "$header" -H "$ct" \
    -d "$(envsubst_file "${SCRIPT_DIR}/datasource.json")" | head -c 200
echo

echo "=== 3/4 Skillset 作成 ==="
curl -s -X PUT "${SEARCH_ENDPOINT}/skillsets/sprag-skillset?api-version=${API_VERSION}" \
    -H "$header" -H "$ct" \
    -d "$(envsubst_file "${SCRIPT_DIR}/skillset.json")" | head -c 200
echo

echo "=== 4/4 Indexer 作成 ==="
curl -s -X PUT "${SEARCH_ENDPOINT}/indexers/sprag-indexer?api-version=${API_VERSION}" \
    -H "$header" -H "$ct" \
    -d "$(envsubst_file "${SCRIPT_DIR}/indexer.json")" | head -c 200
echo

if [[ "${1:-}" == "--run-indexer" ]]; then
    echo "=== Indexer 実行 ==="
    curl -s -X POST "${SEARCH_ENDPOINT}/indexers/sprag-indexer/run?api-version=${API_VERSION}" \
        -H "$header" -H "$ct" | head -c 200
    echo
    echo "Indexer を実行しました。状態確認:"
    curl -s "${SEARCH_ENDPOINT}/indexers/sprag-indexer/status?api-version=${API_VERSION}" \
        -H "$header" | python3 -c "import sys,json;d=json.load(sys.stdin);s=d.get('lastResult',{});print(f'Status: {s.get(\"status\",\"N/A\")}, Items: {s.get(\"itemCount\",0)}, Errors: {s.get(\"errorCount\",0)}')" 2>/dev/null || echo "(parse error)"
fi

echo "=== 完了 ==="
