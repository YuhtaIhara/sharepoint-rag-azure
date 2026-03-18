"""
SP → Blob 同期スクリプト
SharePoint 文書を ACL メタデータ付きで Azure Blob Storage にアップロードする。

Usage:
    python sp_to_blob.py              # 実行
    python sp_to_blob.py --dry-run    # アップロードせずに確認のみ
"""

import argparse
import json as _json
import logging
import os
import sys
import time
from urllib.parse import quote

import requests
from azure.storage.blob import BlobServiceClient, ContentSettings
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
GRAPH_CLIENT_ID = os.environ["GRAPH_CLIENT_ID"]
GRAPH_CLIENT_SECRET = os.environ["GRAPH_CLIENT_SECRET"]
GRAPH_TENANT_ID = os.environ["GRAPH_TENANT_ID"]
STORAGE_CONNECTION_STRING = os.environ["STORAGE_CONNECTION_STRING"]
SP_SITE_HOSTNAME = os.getenv("SP_SITE_HOSTNAME", "example.sharepoint.com")
SP_SITE_PATH = os.getenv("SP_SITE_PATH", "")
SP_DOCUMENT_LIBRARY = os.getenv("SP_DOCUMENT_LIBRARY", "Shared Documents")
BLOB_CONTAINER = "sharepoint-documents"

# 対象フォルダ（空 = 全フォルダ、指定 = 部分一致でフィルタ）
TARGET_FOLDERS_CSV = os.getenv("SP_TARGET_FOLDERS", "")
TARGET_FOLDERS = [f.strip() for f in TARGET_FOLDERS_CSV.split(",") if f.strip()] if TARGET_FOLDERS_CSV else []

GRAPH_BASE = "https://graph.microsoft.com/v1.0"


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------
def get_access_token() -> str:
    """Client credentials flow でアクセストークンを取得"""
    url = f"https://login.microsoftonline.com/{GRAPH_TENANT_ID}/oauth2/v2.0/token"
    resp = requests.post(url, data={
        "client_id": GRAPH_CLIENT_ID,
        "client_secret": GRAPH_CLIENT_SECRET,
        "scope": "https://graph.microsoft.com/.default",
        "grant_type": "client_credentials",
    }, timeout=30)
    resp.raise_for_status()
    return resp.json()["access_token"]


# ---------------------------------------------------------------------------
# Graph API helpers
# ---------------------------------------------------------------------------
def get_site_id(token: str) -> str:
    """サイト ID を取得"""
    if SP_SITE_PATH:
        url = f"{GRAPH_BASE}/sites/{SP_SITE_HOSTNAME}:/{SP_SITE_PATH}"
    else:
        url = f"{GRAPH_BASE}/sites/{SP_SITE_HOSTNAME}:/"
    headers = {"Authorization": f"Bearer {token}"}
    resp = requests.get(url, headers=headers, timeout=30)
    resp.raise_for_status()
    return resp.json()["id"]


def get_drive_id(token: str, site_id: str) -> str:
    """ドキュメントライブラリの drive ID を取得"""
    url = f"{GRAPH_BASE}/sites/{site_id}/drives"
    headers = {"Authorization": f"Bearer {token}"}
    resp = requests.get(url, headers=headers, timeout=30)
    resp.raise_for_status()
    for drive in resp.json().get("value", []):
        if drive["name"] == SP_DOCUMENT_LIBRARY:
            return drive["id"]
    # フォールバック: 最初のドライブ
    drives = resp.json().get("value", [])
    if drives:
        log.warning("ライブラリ '%s' が見つからず、'%s' を使用", SP_DOCUMENT_LIBRARY, drives[0]["name"])
        return drives[0]["id"]
    raise RuntimeError("ドライブが見つかりません")


def _graph_get_with_retry(url: str, headers: dict, max_retries: int = 3) -> requests.Response:
    """リトライ付き GET リクエスト"""
    for attempt in range(max_retries):
        try:
            resp = requests.get(url, headers=headers, timeout=60)
            resp.raise_for_status()
            return resp
        except (requests.exceptions.ConnectionError, requests.exceptions.Timeout) as e:
            if attempt < max_retries - 1:
                wait = 2 ** attempt * 3
                log.warning("接続エラー (attempt %d/%d), %d秒後にリトライ: %s", attempt + 1, max_retries, wait, e)
                time.sleep(wait)
            else:
                raise


def list_items_recursive(token: str, drive_id: str, folder_path: str = "") -> list[dict]:
    """ドライブ内のファイルを再帰的にリスト"""
    headers = {"Authorization": f"Bearer {token}"}
    if folder_path:
        url = f"{GRAPH_BASE}/drives/{drive_id}/root:/{quote(folder_path)}:/children"
    else:
        url = f"{GRAPH_BASE}/drives/{drive_id}/root/children"

    items = []
    while url:
        resp = _graph_get_with_retry(url, headers)
        data = resp.json()
        for item in data.get("value", []):
            if "folder" in item:
                sub_path = f"{folder_path}/{item['name']}" if folder_path else item["name"]
                # TARGET_FOLDERS が指定されていたらルートレベルでフィルタ
                if not folder_path and TARGET_FOLDERS:
                    if not any(t in item["name"] for t in TARGET_FOLDERS):
                        log.info("  スキップ (対象外フォルダ): %s", item["name"])
                        continue
                items.extend(list_items_recursive(token, drive_id, sub_path))
                time.sleep(0.5)  # レートリミット対策
            elif "file" in item:
                item["_folder_path"] = folder_path
                items.append(item)
        url = data.get("@odata.nextLink")
    return items


def get_folder_permissions(token: str, drive_id: str, folder_path: str) -> list[str]:
    """
    フォルダの権限を取得し、閲覧可能なユーザーの UPN リストを返す。

    継承権限（権限が明示的に設定されていない）の場合は ["*"] を返す。
    "*" は「全員アクセス可」を意味し、検索時の ACL フィルタで特別扱いする。
    """
    headers = {"Authorization": f"Bearer {token}"}

    # トップレベルフォルダの権限を取得（フォルダ単位 ACL）
    top_folder = folder_path.split("/")[0] if folder_path else ""
    if top_folder:
        url = f"{GRAPH_BASE}/drives/{drive_id}/root:/{quote(top_folder)}:/permissions"
    else:
        return ["*"]  # ルート直下は全員アクセス可

    resp = requests.get(url, headers=headers, timeout=30)
    if resp.status_code == 404:
        log.warning("権限取得失敗 (404): %s — 継承権限と判断", top_folder)
        return ["*"]
    resp.raise_for_status()

    allowed_users = []
    for perm in resp.json().get("value", []):
        # ユーザー情報を抽出
        granted = perm.get("grantedToV2") or perm.get("grantedTo") or {}
        user = granted.get("user") or granted.get("siteUser") or {}
        if user.get("email"):
            allowed_users.append(user["email"].lower())
        elif user.get("loginName"):
            allowed_users.append(user["loginName"].lower())

        # グループの場合
        group = granted.get("group") or granted.get("siteGroup") or {}
        if group.get("email"):
            allowed_users.append(group["email"].lower())

        # grantedToIdentitiesV2 (複数ユーザー)
        for identity in perm.get("grantedToIdentitiesV2", perm.get("grantedToIdentities", [])):
            u = identity.get("user", {})
            if u.get("email"):
                allowed_users.append(u["email"].lower())

    if not allowed_users:
        # 明示的権限なし = 継承 = 全員アクセス可
        log.info("  フォルダ '%s' の明示的権限なし → 継承（全員アクセス可）", top_folder)
        return ["*"]

    return list(set(allowed_users))


def download_file(token: str, item: dict) -> bytes:
    """ファイルのコンテンツをダウンロード"""
    headers = {"Authorization": f"Bearer {token}"}
    download_url = item.get("@microsoft.graph.downloadUrl")
    if download_url:
        resp = requests.get(download_url, timeout=120)
    else:
        url = f"{GRAPH_BASE}/drives/{item['parentReference']['driveId']}/items/{item['id']}/content"
        resp = requests.get(url, headers=headers, timeout=120)
    resp.raise_for_status()
    return resp.content


# ---------------------------------------------------------------------------
# Blob helpers
# ---------------------------------------------------------------------------
def get_content_type(filename: str) -> str:
    """ファイル名から Content-Type を推定"""
    ext = os.path.splitext(filename)[1].lower()
    mapping = {
        ".pdf": "application/pdf",
        ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        ".doc": "application/msword",
        ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        ".xls": "application/vnd.ms-excel",
        ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        ".ppt": "application/vnd.ms-powerpoint",
        ".txt": "text/plain",
    }
    return mapping.get(ext, "application/octet-stream")


def extract_category(folder_path: str) -> str:
    """トップレベルフォルダ名をカテゴリとして抽出"""
    if not folder_path:
        return "uncategorized"
    return folder_path.split("/")[0]


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def sync(dry_run: bool = False):
    log.info("=== SP → Blob 同期開始 ===")

    # 1. 認証
    log.info("Graph API トークン取得中...")
    token = get_access_token()
    log.info("トークン取得完了")

    # 2. サイト・ドライブ特定
    site_id = get_site_id(token)
    log.info("サイト ID: %s", site_id)
    drive_id = get_drive_id(token, site_id)
    log.info("ドライブ ID: %s", drive_id)

    # 3. ファイル一覧取得
    log.info("ファイル一覧を取得中...")
    items = list_items_recursive(token, drive_id)
    log.info("ファイル数: %d", len(items))

    if not items:
        log.warning("ファイルが見つかりません")
        return

    # 4. フォルダ権限キャッシュ
    folder_permissions: dict[str, list[str]] = {}

    # 5. Blob クライアント
    if not dry_run:
        blob_service = BlobServiceClient.from_connection_string(STORAGE_CONNECTION_STRING)
        container_client = blob_service.get_container_client(BLOB_CONTAINER)
        try:
            container_client.get_container_properties()
        except Exception:
            container_client.create_container()
            log.info("コンテナ '%s' を作成しました", BLOB_CONTAINER)

    # 6. 各ファイルを処理
    for i, item in enumerate(items, 1):
        filename = item["name"]
        folder_path = item.get("_folder_path", "")
        category = extract_category(folder_path)
        blob_name = f"{folder_path}/{filename}" if folder_path else filename

        # SP URL 構築
        source_url = item.get("webUrl", "")

        # ACL 取得（フォルダ単位でキャッシュ）
        if folder_path not in folder_permissions:
            log.info("  権限取得: %s", folder_path or "(root)")
            folder_permissions[folder_path] = get_folder_permissions(token, drive_id, folder_path)
        allowed = folder_permissions[folder_path]

        log.info("[%d/%d] %s (category=%s, ACL=%s)", i, len(items), blob_name, category, allowed or "inherited")

        if dry_run:
            continue

        # ダウンロード
        content = download_file(token, item)

        # メタデータ（Blob メタデータは ASCII のみ → 非ASCII は URL エンコード）
        import base64
        metadata = {
            "source_url": quote(source_url, safe=":/&?="),
            "title": base64.b64encode(filename.encode("utf-8")).decode("ascii"),
            "category": base64.b64encode(category.encode("utf-8")).decode("ascii"),
        }
        # JSON 配列文字列で格納（AI Search の jsonArrayToStringCollection で変換）
        metadata["allowed_groups"] = _json.dumps(allowed)

        # アップロード
        blob_client = container_client.get_blob_client(blob_name)
        blob_client.upload_blob(
            content,
            overwrite=True,
            content_settings=ContentSettings(content_type=get_content_type(filename)),
            metadata=metadata,
        )
        log.info("  → アップロード完了: %s (%d bytes)", blob_name, len(content))

    log.info("=== 同期完了: %d ファイル ===", len(items))
    if dry_run:
        log.info("(dry-run モード: 実際のアップロードは行っていません)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="SharePoint → Blob 同期")
    parser.add_argument("--dry-run", action="store_true", help="アップロードせずに確認のみ")
    args = parser.parse_args()
    try:
        sync(dry_run=args.dry_run)
    except Exception:
        log.exception("同期失敗")
        sys.exit(1)
