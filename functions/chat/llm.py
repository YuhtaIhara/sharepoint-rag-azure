"""OpenAI クライアント — クエリ書き換え + 回答生成"""

import os

from openai import AzureOpenAI

SYSTEM_PROMPT = """あなたは社内文書検索アシスタントです。
ユーザーの質問に対して、**検索結果に含まれる情報のみ**を使って回答してください。

## 絶対に守るルール
- **検索結果に書かれていない情報は、絶対に回答に含めない**。一般知識や推測で補完しない
- 検索結果が空の場合、または検索結果が質問の内容と**直接関連しない**場合は「該当する情報が見つかりませんでした」とだけ回答する
- 検索結果の文書にたまたま質問のキーワードが含まれていても、文書の主題が質問と無関係なら「該当なし」と判断する
- 回答は検索結果の要点を整理し、自分の言葉でまとめる（丸コピペではなく要約する）
- 根拠となる文書を [1], [2] のように引用番号で示す
- 回答は日本語で簡潔に行う

## データの特性
- 検索対象は社内のSharePoint文書（契約書、申請書、事業計画、社内規程など）
- 検索結果にはPDF・Word・Excelから抽出されたテキストが含まれる"""

_client = None


def get_client() -> AzureOpenAI:
    global _client
    if _client is None:
        _client = AzureOpenAI(
            azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
            api_key=os.environ["AZURE_OPENAI_API_KEY"],
            api_version="2024-08-01-preview",
        )
    return _client


def rewrite_query(message: str, history: list[dict]) -> str:
    """会話履歴を踏まえてスタンドアロンな検索クエリに書き換える"""
    if not history:
        return message

    client = get_client()
    deployment = os.environ.get("AZURE_OPENAI_CHAT_DEPLOYMENT", "gpt-4o-mini")

    messages = [
        {"role": "system", "content": (
            "ユーザーの最新の質問と会話履歴から、検索エンジンに投げる"
            "スタンドアロンな検索クエリを1つだけ生成してください。"
            "クエリのみを返し、説明は不要です。"
        )},
    ]
    for h in history[-6:]:
        messages.append({"role": h["role"], "content": h["content"]})
    messages.append({"role": "user", "content": message})

    resp = client.chat.completions.create(
        model=deployment,
        messages=messages,
        temperature=0,
        max_tokens=200,
    )
    return resp.choices[0].message.content.strip()


def generate_answer(
    message: str,
    search_results: list[dict],
    history: list[dict],
) -> tuple[str, list[dict]]:
    """検索結果を基に回答を生成。(answer, citations) を返す"""
    client = get_client()
    deployment = os.environ.get("AZURE_OPENAI_CHAT_DEPLOYMENT", "gpt-4o-mini")

    # コンテキスト構築
    context_parts = []
    citations = []
    for i, doc in enumerate(search_results, 1):
        title = doc.get("title") or "文書"
        chunk = doc.get("chunk") or ""
        context_parts.append(f"[{i}] {title}\n{chunk}")
        citations.append({
            "title": title,
            "url": doc.get("source_url") or "",
            "chunk": chunk[:200],
        })

    context = "\n\n---\n\n".join(context_parts) if context_parts else "（検索結果なし）"

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "system", "content": f"## 検索結果\n\n{context}"},
    ]
    for h in history[-6:]:
        messages.append({"role": h["role"], "content": h["content"]})
    messages.append({"role": "user", "content": message})

    resp = client.chat.completions.create(
        model=deployment,
        messages=messages,
        temperature=0.1,
        max_tokens=1500,
    )

    answer = resp.choices[0].message.content.strip()

    # 回答全体が「該当なし」の場合のみ参照元を返さない（ファイル名漏洩防止）
    # 部分的に「見つかりませんでした」を含む場合は参照元を残す
    answer_stripped = answer.replace(" ", "").replace("\n", "")
    if answer_stripped in ("該当する情報が見つかりませんでした。", "該当する情報が見つかりませんでした"):
        citations = []

    return answer, citations
