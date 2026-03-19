"""チャットオーケストレーション — メインフロー"""

import logging
import os
import uuid

from . import history, llm, search

log = logging.getLogger(__name__)


def handle_chat(body: dict) -> dict:
    message = body.get("message", "").strip()
    session_id = body.get("session_id") or str(uuid.uuid4())
    user_id = body.get("user_id", "anonymous")
    user_groups = body.get("user_groups", [])

    if not message:
        return {
            "answer": "メッセージを入力してください。",
            "citations": [],
            "session_id": session_id,
        }

    if len(message) > 2000:
        return {
            "answer": "メッセージが長すぎます（最大2000文字）。",
            "citations": [],
            "session_id": session_id,
        }

    # 1. 会話履歴取得（失敗しても続行）
    conv_history = []
    try:
        conv_history = history.get_history(session_id)
    except Exception as e:
        log.warning("会話履歴の取得に失敗（初回接続の可能性）: %s", e)

    # 2. マルチクエリ生成 + 検索
    queries = llm.rewrite_query_multi(message, conv_history)
    log.info("Multi-query variants: %s", queries)

    # 3. 各クエリで検索し、結果をマージ（chunk_id で重複排除）
    seen_ids = set()
    all_results = []
    for q in queries:
        hits = search.hybrid_search(q, user_groups)
        for r in hits:
            cid = r.get("chunk_id", "")
            if cid not in seen_ids:
                seen_ids.add(cid)
                all_results.append(r)

    # reranker_score 降順でソートし上位を採用
    all_results.sort(key=lambda r: r.get("reranker_score", 0), reverse=True)
    max_results = int(os.environ.get("MAX_SEARCH_RESULTS", "7"))
    results = all_results[:max_results]

    log.info("Merged results: %d docs (from %d total), titles: %s",
             len(results), len(all_results), [r.get("title", "") for r in results])

    # 4. HyDE フォールバック: 検索結果が少ない or スコアが低い場合
    top_score = results[0].get("reranker_score", 0) if results else 0
    if len(results) < 2 or top_score < 1.5:
        log.info("HyDE fallback triggered (results=%d, top_score=%.2f)", len(results), top_score)
        hyde_query = llm.generate_hyde_query(message)
        log.info("HyDE query: %.100s", hyde_query)
        hyde_hits = search.hybrid_search(hyde_query, user_groups)
        for r in hyde_hits:
            cid = r.get("chunk_id", "")
            if cid not in seen_ids:
                seen_ids.add(cid)
                results.append(r)
        results.sort(key=lambda r: r.get("reranker_score", 0), reverse=True)
        results = results[:max_results]
        log.info("After HyDE: %d docs", len(results))

    # チャンク内容のデバッグ（先頭100文字）
    for i, r in enumerate(results):
        log.info("  chunk[%d] len=%d score=%.2f preview=%.100s",
                 i, len(r.get("chunk", "")), r.get("reranker_score", 0), r.get("chunk", ""))

    # 4. 回答生成
    answer, citations = llm.generate_answer(message, results, conv_history)

    # 5. 会話履歴保存（失敗しても続行）
    try:
        history.save_turn(session_id, user_id, "user", message)
        history.save_turn(session_id, user_id, "assistant", answer)
    except Exception as e:
        log.warning("会話履歴の保存に失敗: %s", e)

    return {
        "answer": answer,
        "citations": citations,
        "session_id": session_id,
    }
