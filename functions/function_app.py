"""Azure Functions v2 Python — SP RAG チャットボット"""

import json
import logging
import os

import azure.functions as func
import requests

from chat.orchestrator import handle_chat
from sync_trigger.sync import run_sync

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)


@app.route(route="chat", methods=["POST"])
def chat(req: func.HttpRequest) -> func.HttpResponse:
    """チャット API エンドポイント"""
    try:
        body = req.get_json()
    except ValueError:
        return func.HttpResponse(
            json.dumps({"error": "Invalid JSON"}, ensure_ascii=False),
            status_code=400,
            mimetype="application/json",
        )

    try:
        result = handle_chat(body)
        return func.HttpResponse(
            json.dumps(result, ensure_ascii=False),
            mimetype="application/json",
        )
    except Exception as e:
        logging.exception("Chat error")
        return func.HttpResponse(
            json.dumps({"error": str(e)}, ensure_ascii=False),
            status_code=500,
            mimetype="application/json",
        )


@app.route(route="health", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def health(req: func.HttpRequest) -> func.HttpResponse:
    """ヘルスチェック / ウォームアップ用"""
    return func.HttpResponse(
        json.dumps({"status": "ok"}),
        mimetype="application/json",
    )


@app.timer_trigger(schedule="0 0 * * * *", arg_name="timer", run_on_startup=False)
def sync_trigger(timer: func.TimerRequest) -> None:
    """SP → Blob 差分同期 (毎時0分)"""
    logging.info("SP sync timer triggered (past_due=%s)", timer.past_due)
    try:
        run_sync()
        logging.info("SP sync completed")
    except Exception:
        logging.exception("SP sync failed")


@app.route(route="ingest", methods=["POST"])
def ingest_trigger(req: func.HttpRequest) -> func.HttpResponse:
    """AI Search インデクサーを手動実行"""
    endpoint = os.environ["AZURE_SEARCH_ENDPOINT"]
    api_key = os.environ["AZURE_SEARCH_API_KEY"]
    indexer_name = "sprag-indexer"

    try:
        # インデクサー実行
        run_url = f"{endpoint}/indexers/{indexer_name}/run?api-version=2024-07-01"
        resp = requests.post(run_url, headers={
            "api-key": api_key,
            "Content-Type": "application/json",
        }, timeout=30)

        # ステータス取得
        status_url = f"{endpoint}/indexers/{indexer_name}/status?api-version=2024-07-01"
        status_resp = requests.get(status_url, headers={"api-key": api_key}, timeout=30)
        status_data = status_resp.json() if status_resp.ok else {}

        return func.HttpResponse(
            json.dumps({
                "message": "Indexer triggered",
                "run_status_code": resp.status_code,
                "indexer_status": status_data.get("lastResult", {}),
            }, ensure_ascii=False),
            mimetype="application/json",
        )
    except Exception as e:
        logging.exception("Ingest trigger error")
        return func.HttpResponse(
            json.dumps({"error": str(e)}, ensure_ascii=False),
            status_code=500,
            mimetype="application/json",
        )
