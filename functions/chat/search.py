"""AI Search クライアント — ハイブリッド検索 + ACL フィルタ"""

import os

from azure.core.credentials import AzureKeyCredential
from azure.search.documents import SearchClient
from azure.search.documents.models import VectorizableTextQuery

_client = None


def get_search_client() -> SearchClient:
    global _client
    if _client is None:
        _client = SearchClient(
            endpoint=os.environ["AZURE_SEARCH_ENDPOINT"],
            index_name=os.environ.get("AZURE_SEARCH_INDEX_NAME", "sprag-index"),
            credential=AzureKeyCredential(os.environ["AZURE_SEARCH_API_KEY"]),
        )
    return _client


def hybrid_search(
    query: str,
    user_groups: list[str],
    top: int = 5,
) -> list[dict]:
    """ハイブリッド検索 + セマンティックランカー + ACL フィルタ"""
    client = get_search_client()

    # ACL フィルタ構築
    acl_filter = None
    if user_groups:
        escaped = ",".join(f"'{g.replace(chr(39), chr(39)+chr(39))}'" for g in user_groups)
        acl_filter = (
            f"(allowed_groups/any(g: search.in(g, {escaped})) "
            f"or allowed_groups/any(g: g eq '*'))"
        )

    # ベクトルクエリ
    vector_query = VectorizableTextQuery(
        text=query,
        k_nearest_neighbors=top,
        fields="text_vector",
    )

    results = client.search(
        search_text=query,
        vector_queries=[vector_query],
        filter=acl_filter,
        query_type="semantic",
        semantic_configuration_name="sprag-semantic-config",
        top=top,
        select=["chunk_id", "chunk", "title", "source_url", "category"],
    )

    docs = []
    for r in results:
        docs.append({
            "chunk_id": r["chunk_id"],
            "chunk": r["chunk"],
            "title": r.get("title", ""),
            "source_url": r.get("source_url", ""),
            "category": r.get("category", ""),
            "score": r.get("@search.score", 0),
        })
    return docs
