"""
SP → Blob 差分同期 + インデックスメタデータ更新

Timer Trigger から呼び出される。
SP の lastModifiedDateTime と Blob の Last-Modified を比較し、
変更があるファイルだけ同期する。
"""

import base64
import json
import logging
import os
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone

import requests
from azure.storage.blob import BlobServiceClient, ContentSettings

log = logging.getLogger(__name__)

GRAPH_BASE = "https://graph.microsoft.com/v1.0"
BLOB_CONTAINER = "sharepoint-documents"
INDEX_NAME = "sprag-index"
API_VERSION = "2024-07-01"


def run_sync(full: bool = False):
    """SP → Blob 差分同期を実行し、変更があればインデックスメタデータを更新する"""
    sp_hostname = os.environ.get("SP_SITE_HOSTNAME", "")
    if not sp_hostname:
        log.warning("SP_SITE_HOSTNAME not set, skipping sync")
        return

    client_id = os.environ["GRAPH_CLIENT_ID"]
    client_secret = os.environ["GRAPH_CLIENT_SECRET"]
    tenant_id = os.environ["GRAPH_TENANT_ID"]
    storage_conn = os.environ["STORAGE_CONNECTION_STRING"]

    # Auth
    token = _get_access_token(tenant_id, client_id, client_secret)

    # SP site/drive
    site_path = os.environ.get("SP_SITE_PATH", "")
    doc_lib = os.environ.get("SP_DOCUMENT_LIBRARY", "Shared Documents")
    site_id = _get_site_id(token, sp_hostname, site_path)
    drive_id = _get_drive_id(token, site_id, doc_lib)

    # SP files
    sp_items = _list_items_recursive(token, drive_id)
    log.info("SP files: %d", len(sp_items))

    # Blob list
    blob_service = BlobServiceClient.from_connection_string(storage_conn)
    container = blob_service.get_container_client(BLOB_CONTAINER)
    blobs = {}
    for blob in container.list_blobs(include=["metadata"]):
        blobs[blob.name] = blob

    # Sync
    sp_blob_names = set()
    synced = 0
    skipped = 0
    folder_permissions = {}

    for item in sp_items:
        folder_path = item.get("_folder_path", "")
        filename = item["name"]
        blob_name = f"{folder_path}/{filename}" if folder_path else filename
        sp_blob_names.add(blob_name)

        # Diff check
        if blob_name in blobs and not full:
            sp_modified = item.get("lastModifiedDateTime", "")
            if sp_modified:
                sp_dt = datetime.fromisoformat(sp_modified.replace("Z", "+00:00"))
                blob_dt = blobs[blob_name].last_modified
                if blob_dt and sp_dt <= blob_dt:
                    skipped += 1
                    continue

        # ACL (cached per folder)
        if folder_path not in folder_permissions:
            folder_permissions[folder_path] = _get_folder_permissions(
                token, drive_id, folder_path
            )
        allowed = folder_permissions[folder_path]

        # Download
        content = _download_file(token, item)
        category = folder_path.split("/")[0] if folder_path else "uncategorized"
        source_url = item.get("webUrl", "")

        metadata = {
            "source_url": urllib.parse.quote(source_url, safe=":/&?="),
            "title": base64.b64encode(filename.encode("utf-8")).decode("ascii"),
            "category": base64.b64encode(category.encode("utf-8")).decode("ascii"),
            "allowed_groups": json.dumps(allowed),
        }

        blob_client = container.get_blob_client(blob_name)
        blob_client.upload_blob(
            content,
            overwrite=True,
            content_settings=ContentSettings(content_type=_get_content_type(filename)),
            metadata=metadata,
        )
        synced += 1
        log.info("Synced: %s (%d bytes)", blob_name, len(content))

    # Delete orphaned blobs
    deleted = 0
    for blob_name in list(blobs.keys()):
        if blob_name not in sp_blob_names:
            container.delete_blob(blob_name)
            deleted += 1
            log.info("Deleted orphaned: %s", blob_name)

    log.info(
        "Sync complete: synced=%d, skipped=%d, deleted=%d", synced, skipped, deleted
    )

    # Update index metadata if changes occurred
    if synced > 0 or deleted > 0:
        _update_index_metadata(storage_conn)


# ---------------------------------------------------------------------------
# Graph API helpers (adapted from scripts/sp_to_blob.py)
# ---------------------------------------------------------------------------
def _get_access_token(tenant_id: str, client_id: str, client_secret: str) -> str:
    url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"
    resp = requests.post(
        url,
        data={
            "client_id": client_id,
            "client_secret": client_secret,
            "scope": "https://graph.microsoft.com/.default",
            "grant_type": "client_credentials",
        },
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()["access_token"]


def _get_site_id(token: str, hostname: str, site_path: str) -> str:
    headers = {"Authorization": f"Bearer {token}"}
    url = f"{GRAPH_BASE}/sites/{hostname}:/{site_path}" if site_path else f"{GRAPH_BASE}/sites/{hostname}:/"
    resp = requests.get(url, headers=headers, timeout=30)
    resp.raise_for_status()
    return resp.json()["id"]


def _get_drive_id(token: str, site_id: str, library_name: str) -> str:
    headers = {"Authorization": f"Bearer {token}"}
    resp = requests.get(
        f"{GRAPH_BASE}/sites/{site_id}/drives", headers=headers, timeout=30
    )
    resp.raise_for_status()
    for drive in resp.json().get("value", []):
        if drive["name"] == library_name:
            return drive["id"]
    drives = resp.json().get("value", [])
    if drives:
        return drives[0]["id"]
    raise RuntimeError("No drives found")


def _list_items_recursive(
    token: str, drive_id: str, folder_path: str = ""
) -> list[dict]:
    headers = {"Authorization": f"Bearer {token}"}
    if folder_path:
        url = f"{GRAPH_BASE}/drives/{drive_id}/root:/{urllib.parse.quote(folder_path)}:/children"
    else:
        url = f"{GRAPH_BASE}/drives/{drive_id}/root/children"

    items = []
    while url:
        resp = requests.get(url, headers=headers, timeout=60)
        resp.raise_for_status()
        data = resp.json()
        for item in data.get("value", []):
            if "folder" in item:
                sub = f"{folder_path}/{item['name']}" if folder_path else item["name"]
                items.extend(_list_items_recursive(token, drive_id, sub))
                time.sleep(0.5)
            elif "file" in item:
                item["_folder_path"] = folder_path
                items.append(item)
        url = data.get("@odata.nextLink")
    return items


def _get_folder_permissions(
    token: str, drive_id: str, folder_path: str
) -> list[str]:
    if not folder_path:
        return ["*"]
    headers = {"Authorization": f"Bearer {token}"}
    top_folder = folder_path.split("/")[0]
    url = f"{GRAPH_BASE}/drives/{drive_id}/root:/{urllib.parse.quote(top_folder)}:/permissions"
    resp = requests.get(url, headers=headers, timeout=30)
    if resp.status_code == 404:
        return ["*"]
    resp.raise_for_status()

    allowed = []
    for perm in resp.json().get("value", []):
        granted = perm.get("grantedToV2") or perm.get("grantedTo") or {}
        user = granted.get("user") or granted.get("siteUser") or {}
        if user.get("email"):
            allowed.append(user["email"].lower())
        group = granted.get("group") or granted.get("siteGroup") or {}
        if group.get("email"):
            allowed.append(group["email"].lower())
        for identity in perm.get("grantedToIdentitiesV2", perm.get("grantedToIdentities", [])):
            u = identity.get("user", {})
            if u.get("email"):
                allowed.append(u["email"].lower())

    return list(set(allowed)) if allowed else ["*"]


def _download_file(token: str, item: dict) -> bytes:
    headers = {"Authorization": f"Bearer {token}"}
    download_url = item.get("@microsoft.graph.downloadUrl")
    if download_url:
        resp = requests.get(download_url, timeout=120)
    else:
        url = f"{GRAPH_BASE}/drives/{item['parentReference']['driveId']}/items/{item['id']}/content"
        resp = requests.get(url, headers=headers, timeout=120)
    resp.raise_for_status()
    return resp.content


def _get_content_type(filename: str) -> str:
    ext = os.path.splitext(filename)[1].lower()
    return {
        ".pdf": "application/pdf",
        ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    }.get(ext, "application/octet-stream")


# ---------------------------------------------------------------------------
# Index metadata update (adapted from scripts/update_index_metadata.py)
# ---------------------------------------------------------------------------
def _update_index_metadata(storage_conn: str):
    search_endpoint = os.environ.get("AZURE_SEARCH_ENDPOINT", "")
    search_key = os.environ.get("AZURE_SEARCH_API_KEY", "")
    if not search_endpoint or not search_key:
        log.warning("Search config not set, skipping metadata update")
        return

    log.info("Updating index metadata...")

    # Get blob metadata
    blob_service = BlobServiceClient.from_connection_string(storage_conn)
    container = blob_service.get_container_client(BLOB_CONTAINER)
    blob_meta = {}
    for blob in container.list_blobs(include=["metadata"]):
        meta = blob.metadata or {}
        allowed_raw = meta.get("allowed_groups", "[]")
        try:
            allowed = json.loads(allowed_raw)
        except (json.JSONDecodeError, TypeError):
            allowed = [allowed_raw] if allowed_raw else []
        category = meta.get("category", "")
        try:
            category = base64.b64decode(category).decode("utf-8")
        except Exception:
            pass
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

    # Get index docs
    def search_api(method, path, body=None):
        url = f"{search_endpoint}{path}?api-version={API_VERSION}"
        data = json.dumps(body).encode("utf-8") if body else None
        req = urllib.request.Request(
            url,
            data=data,
            method=method,
            headers={
                "api-key": search_key,
                "Content-Type": "application/json; charset=utf-8",
            },
        )
        resp = urllib.request.urlopen(req)
        return json.loads(resp.read().decode("utf-8"))

    docs = []
    skip = 0
    while True:
        result = search_api(
            "POST",
            f"/indexes/{INDEX_NAME}/docs/search",
            {"search": "*", "top": 1000, "skip": skip, "select": "chunk_id,parent_id,title"},
        )
        batch = result.get("value", [])
        if not batch:
            break
        docs.extend(batch)
        skip += len(batch)
        if len(batch) < 1000:
            break

    # Match and update
    filename_map = {}
    for name, meta in blob_meta.items():
        filename_map[name.split("/")[-1]] = meta
        filename_map[name] = meta

    updates = []
    for doc in docs:
        title = doc.get("title", "")
        meta = filename_map.get(title)
        if meta:
            updates.append({
                "@search.action": "merge",
                "chunk_id": doc["chunk_id"],
                "allowed_groups": meta["allowed_groups"],
                "category": meta["category"],
                "source_url": meta["source_url"],
            })

    if updates:
        for i in range(0, len(updates), 100):
            batch = updates[i : i + 100]
            search_api("POST", f"/indexes/{INDEX_NAME}/docs/index", {"value": batch})
        log.info("Updated %d index documents", len(updates))
    else:
        log.info("No metadata updates needed")
