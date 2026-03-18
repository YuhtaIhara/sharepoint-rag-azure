"""
インデックス済みドキュメントに ACL メタデータを追加するスクリプト。

Blob のカスタムメタデータ (allowed_groups, category, source_url) を読み取り、
AI Search インデックスの該当ドキュメントを一括更新する。

Usage:
    python update_index_metadata.py
"""

import base64
import json
import logging
import os
import sys
import urllib.parse
import urllib.request

from azure.storage.blob import BlobServiceClient
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

STORAGE_CONNECTION_STRING = os.environ["STORAGE_CONNECTION_STRING"]
BLOB_CONTAINER = "sharepoint-documents"

# Search は KV 参照ではなく直接渡す
SEARCH_ENDPOINT = os.environ.get("SEARCH_ENDPOINT", "")
SEARCH_API_KEY = os.environ.get("SEARCH_API_KEY", "")
INDEX_NAME = "sprag-index"
API_VERSION = "2024-07-01"


def search_api(method: str, path: str, body: dict | None = None) -> dict:
    """AI Search REST API 呼び出し"""
    url = f"{SEARCH_ENDPOINT}{path}?api-version={API_VERSION}"
    data = json.dumps(body).encode("utf-8") if body else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "api-key": SEARCH_API_KEY,
        "Content-Type": "application/json; charset=utf-8",
    })
    resp = urllib.request.urlopen(req)
    return json.loads(resp.read().decode("utf-8"))


def get_all_index_docs() -> list[dict]:
    """インデックスから全ドキュメントを取得（parent_id でグループ化用）"""
    docs = []
    skip = 0
    while True:
        body = {
            "search": "*",
            "top": 1000,
            "skip": skip,
            "select": "chunk_id,parent_id,title",
        }
        result = search_api("POST", f"/indexes/{INDEX_NAME}/docs/search", body)
        new_docs = result.get("value", [])
        if not new_docs:
            break
        docs.extend(new_docs)
        skip += len(new_docs)
        if len(new_docs) < 1000:
            break
    log.info("インデックスから %d ドキュメント取得", len(docs))
    return docs


def get_blob_metadata() -> dict[str, dict]:
    """全 Blob のカスタムメタデータを取得。キー = blob name"""
    blob_service = BlobServiceClient.from_connection_string(STORAGE_CONNECTION_STRING)
    container = blob_service.get_container_client(BLOB_CONTAINER)

    blob_meta = {}
    for blob in container.list_blobs(include=["metadata"]):
        meta = blob.metadata or {}
        allowed_raw = meta.get("allowed_groups", "[]")
        try:
            allowed = json.loads(allowed_raw)
        except (json.JSONDecodeError, TypeError):
            allowed = [allowed_raw] if allowed_raw else []

        # category と title は base64 エンコードされている場合がある
        category = meta.get("category", "")
        try:
            category = base64.b64decode(category).decode("utf-8")
        except Exception:
            pass  # base64 でなければそのまま

        source_url = meta.get("source_url", "")
        try:
            source_url = urllib.parse.unquote(source_url)
        except Exception:
            pass

        blob_meta[blob.name] = {
            "allowed_groups": allowed,
            "category": category,
            "source_url": source_url,
        }
    log.info("Blob メタデータ %d 件取得", len(blob_meta))
    return blob_meta


def match_docs_to_blobs(index_docs: list[dict], blob_meta: dict[str, dict]) -> dict[str, dict]:
    """
    インデックスドキュメントを Blob にマッチさせる。
    title (= ファイル名) を使ってマッチング。
    """
    # blob name → metadata のマッピングをファイル名ベースでも作る
    filename_to_meta = {}
    for blob_name, meta in blob_meta.items():
        filename = blob_name.split("/")[-1]
        filename_to_meta[filename] = meta
        # フルパスでも
        filename_to_meta[blob_name] = meta

    matched = {}
    unmatched = 0
    for doc in index_docs:
        title = doc.get("title", "")
        chunk_id = doc.get("chunk_id", "")

        meta = filename_to_meta.get(title)
        if meta:
            matched[chunk_id] = meta
        else:
            unmatched += 1

    log.info("マッチ: %d, 未マッチ: %d", len(matched), unmatched)
    return matched


def update_index_batch(updates: list[dict]):
    """AI Search インデックスを一括更新"""
    batch_size = 100
    total = len(updates)

    for i in range(0, total, batch_size):
        batch = updates[i:i + batch_size]
        body = {"value": batch}
        try:
            result = search_api("POST", f"/indexes/{INDEX_NAME}/docs/index", body)
            results = result.get("value", [])
            ok = sum(1 for r in results if r.get("statusCode") == 200)
            err = sum(1 for r in results if r.get("statusCode") != 200)
            log.info("バッチ %d-%d/%d: OK=%d, Error=%d", i + 1, min(i + batch_size, total), total, ok, err)
            if err > 0:
                for r in results:
                    if r.get("statusCode") != 200:
                        log.warning("  Error: %s - %s", r.get("key", ""), r.get("errorMessage", ""))
        except Exception as e:
            log.error("バッチ %d-%d 失敗: %s", i + 1, i + batch_size, e)


def main():
    if not SEARCH_ENDPOINT or not SEARCH_API_KEY:
        log.error("SEARCH_ENDPOINT と SEARCH_API_KEY を環境変数で設定してください")
        sys.exit(1)

    log.info("=== インデックスメタデータ更新開始 ===")

    # 1. Blob メタデータ取得
    blob_meta = get_blob_metadata()

    # 2. インデックスドキュメント取得
    index_docs = get_all_index_docs()

    # 3. マッチング
    matched = match_docs_to_blobs(index_docs, blob_meta)

    if not matched:
        log.warning("マッチするドキュメントがありません")
        return

    # 4. 更新ドキュメント作成
    updates = []
    for chunk_id, meta in matched.items():
        doc = {
            "@search.action": "merge",
            "chunk_id": chunk_id,
            "allowed_groups": meta["allowed_groups"],
            "category": meta["category"],
            "source_url": meta["source_url"],
        }
        updates.append(doc)

    log.info("更新対象: %d ドキュメント", len(updates))

    # 5. 一括更新
    update_index_batch(updates)

    log.info("=== 更新完了 ===")


if __name__ == "__main__":
    main()
