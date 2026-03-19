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
    # TODO: Phase 2 で Entra ID グループベースの ACL を実装
    # 現状は PoC のため ACL フィルタを無効化（全文書にアクセス可能）
    acl_filter = None

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

    RERANKER_THRESHOLD = 2.0

    docs = []
    for r in results:
        reranker_score = r.get("@search.rerankerScore", 0) or 0
        if reranker_score < RERANKER_THRESHOLD:
            continue
        docs.append({
            "chunk_id": r["chunk_id"],
            "chunk": r["chunk"],
            "title": r.get("title", ""),
            "source_url": r.get("source_url", ""),
            "category": r.get("category", ""),
            "score": r.get("@search.score", 0),
            "reranker_score": reranker_score,
        })
    return docs
