"""チャットオーケストレーション — メインフロー"""

import logging
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

    # 2. クエリ書き換え
    rewritten = llm.rewrite_query(message, conv_history)
    log.info("Rewritten query: %s", rewritten)

    # 3. ハイブリッド検索 + ACL フィルタ
    results = search.hybrid_search(rewritten, user_groups)
    log.info("Search results: %d docs, titles: %s", len(results), [r.get("title", "") for r in results])

    # チャンク内容のデバッグ（先頭100文字）
    for i, r in enumerate(results):
        log.info("  chunk[%d] len=%d preview=%.100s", i, len(r.get("chunk", "")), r.get("chunk", ""))

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
