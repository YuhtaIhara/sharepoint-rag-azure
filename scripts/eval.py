#!/usr/bin/env python3
"""回答精度評価スクリプト

Usage:
    python scripts/eval.py                    # Functions 経由（デフォルト）
    python scripts/eval.py --direct           # Search API 直接
    python scripts/eval.py --baseline s1      # 結果に "s1" タグを付けて保存

必須環境変数:
    FUNCTIONS_ENDPOINT  — Functions のベースURL（例: https://func-sprag-poc-ea.azurewebsites.net）
    FUNCTIONS_KEY       — Functions の API キー
  --direct 時:
    AZURE_SEARCH_ENDPOINT
    AZURE_SEARCH_API_KEY
    AZURE_OPENAI_ENDPOINT
    AZURE_OPENAI_API_KEY
"""

import argparse
import json
import logging
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import requests

logging.basicConfig(level=logging.INFO, format="%(message)s")
log = logging.getLogger(__name__)

EVAL_DIR = Path(__file__).resolve().parent.parent / "search" / "eval"
QUESTIONS_FILE = EVAL_DIR / "questions.json"
RESULTS_DIR = EVAL_DIR / "results"


def load_questions() -> list[dict]:
    with open(QUESTIONS_FILE, encoding="utf-8") as f:
        return json.load(f)


def call_chat_api(question: str, user_groups: list[str]) -> dict:
    """Functions の /api/chat を呼び出す"""
    endpoint = os.environ["FUNCTIONS_ENDPOINT"].rstrip("/")
    key = os.environ["FUNCTIONS_KEY"]
    resp = requests.post(
        f"{endpoint}/api/chat?code={key}",
        json={
            "message": question,
            "user_groups": user_groups,
            "session_id": f"eval-{int(time.time())}",
        },
        timeout=60,
    )
    resp.raise_for_status()
    return resp.json()


def call_search_direct(question: str, user_groups: list[str]) -> dict:
    """Search API を直接呼び出す（LLM なし、検索結果のみ）"""
    endpoint = os.environ["AZURE_SEARCH_ENDPOINT"].rstrip("/")
    api_key = os.environ["AZURE_SEARCH_API_KEY"]

    # ACL フィルタ構築
    escaped = ",".join(f"'{g}'" for g in user_groups)
    acl_filter = (
        f"(allowed_groups/any(g: g eq '*') or "
        f"allowed_groups/any(g: search.in(g, {escaped})))"
    )

    body = {
        "search": question,
        "filter": acl_filter,
        "queryType": "semantic",
        "semanticConfiguration": "sprag-semantic-config",
        "top": 5,
        "select": "chunk_id,title,chunk,category",
    }

    resp = requests.post(
        f"{endpoint}/indexes/sprag-index/docs/search?api-version=2024-07-01",
        headers={"api-key": api_key, "Content-Type": "application/json"},
        json=body,
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()
    results = data.get("value", [])
    return {
        "answer": results[0].get("chunk", "") if results else "",
        "citations": [
            {"title": r.get("title", ""), "category": r.get("category", "")}
            for r in results
        ],
        "result_count": len(results),
    }


def evaluate_result(q: dict, result: dict) -> dict:
    """質問定義と回答を比較して判定"""
    answer = result.get("answer", "")
    citations = result.get("citations", [])

    if q.get("expect_no_answer"):
        # ハルシネーションチェック: 回答に情報がないことを示す表現を含むか
        no_answer_phrases = ["見つかりません", "該当する情報", "情報がありません", "確認できません"]
        passed = any(p in answer for p in no_answer_phrases) or not answer.strip()
        return {
            "passed": passed,
            "reason": "ハルシネーションなし" if passed else "該当なし情報で回答を生成してしまった",
        }

    # キーワードチェック
    keywords = q.get("expected_keywords", [])
    found_keywords = [kw for kw in keywords if kw in answer]
    keyword_hit = len(found_keywords) / len(keywords) if keywords else 1.0

    # カテゴリチェック（citations のカテゴリに期待カテゴリが含まれるか）
    expected_cat = q.get("expected_category")
    if expected_cat and citations:
        cat_titles = [c.get("category", "") or c.get("title", "") for c in citations]
        category_hit = any(expected_cat in t for t in cat_titles)
    else:
        category_hit = expected_cat is None

    passed = keyword_hit >= 0.5 and category_hit
    reasons = []
    if keyword_hit < 0.5:
        reasons.append(f"キーワード不足 ({len(found_keywords)}/{len(keywords)})")
    if not category_hit:
        reasons.append(f"期待カテゴリ '{expected_cat}' が citations に含まれない")

    return {
        "passed": passed,
        "keyword_hit_rate": keyword_hit,
        "category_hit": category_hit,
        "reason": "OK" if passed else "; ".join(reasons),
    }


def run_eval(direct: bool = False, tag: str = "") -> dict:
    questions = load_questions()
    results = []
    passed_count = 0

    for q in questions:
        log.info("[%s] %s", q["id"], q["question"])
        try:
            if direct:
                result = call_search_direct(q["question"], q["user_groups"])
            else:
                result = call_chat_api(q["question"], q["user_groups"])

            evaluation = evaluate_result(q, result)
            status = "PASS" if evaluation["passed"] else "FAIL"
            if evaluation["passed"]:
                passed_count += 1
            log.info("  → %s: %s", status, evaluation["reason"])

            results.append({
                "id": q["id"],
                "question": q["question"],
                "status": status,
                "evaluation": evaluation,
                "answer_preview": result.get("answer", "")[:200],
                "citation_count": len(result.get("citations", [])),
            })
        except Exception as e:
            log.error("  → ERROR: %s", e)
            results.append({
                "id": q["id"],
                "question": q["question"],
                "status": "ERROR",
                "error": str(e),
            })

    summary = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "tag": tag,
        "mode": "direct" if direct else "chat_api",
        "total": len(questions),
        "passed": passed_count,
        "failed": len(questions) - passed_count,
        "pass_rate": f"{passed_count / len(questions) * 100:.0f}%",
        "results": results,
    }

    # 結果をファイルに保存
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    tag_suffix = f"_{tag}" if tag else ""
    filename = f"eval_{datetime.now().strftime('%Y%m%d_%H%M%S')}{tag_suffix}.json"
    output_path = RESULTS_DIR / filename
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    log.info("")
    log.info("=== 評価結果 ===")
    log.info("合格: %d/%d (%s)", passed_count, len(questions), summary["pass_rate"])
    log.info("結果: %s", output_path)

    return summary


def main():
    parser = argparse.ArgumentParser(description="RAG 回答精度評価")
    parser.add_argument("--direct", action="store_true", help="Search API 直接呼び出し（LLM なし）")
    parser.add_argument("--baseline", default="", help="結果にタグを付ける（例: s1, basic）")
    args = parser.parse_args()

    run_eval(direct=args.direct, tag=args.baseline)


if __name__ == "__main__":
    main()
