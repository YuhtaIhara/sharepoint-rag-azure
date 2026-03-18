"""Cosmos DB 会話履歴"""

import os
import uuid
from datetime import datetime, timezone

from azure.cosmos import CosmosClient

_client = None
_container = None


def _get_container():
    global _client, _container
    if _container is None:
        _client = CosmosClient.from_connection_string(os.environ["COSMOS_CONNECTION_STRING"])
        db = _client.get_database_client(os.environ.get("COSMOS_DB_DATABASE", "ChatDB"))
        _container = db.get_container_client(os.environ.get("COSMOS_DB_CONTAINER", "conversations"))
    return _container


def get_history(session_id: str, limit: int = 10) -> list[dict]:
    """セッションの直近の会話履歴を取得"""
    container = _get_container()
    query = (
        "SELECT c.role, c.content, c.timestamp "
        "FROM c WHERE c.sessionId = @sid "
        "ORDER BY c.timestamp DESC "
        "OFFSET 0 LIMIT @limit"
    )
    items = list(container.query_items(
        query=query,
        parameters=[
            {"name": "@sid", "value": session_id},
            {"name": "@limit", "value": limit},
        ],
        partition_key=session_id,
    ))
    # DESC で取得したので逆順にして時系列順に
    items.reverse()
    return [{"role": i["role"], "content": i["content"]} for i in items]


def save_turn(session_id: str, user_id: str, role: str, content: str):
    """1ターン分を保存"""
    container = _get_container()
    container.upsert_item({
        "id": str(uuid.uuid4()),
        "sessionId": session_id,
        "userId": user_id,
        "role": role,
        "content": content,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })
