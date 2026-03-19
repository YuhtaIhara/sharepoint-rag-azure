"""OpenAI クライアント — クエリ書き換え + 回答生成"""

import os
import re

from openai import AzureOpenAI

SYSTEM_PROMPT = """あなたは社内文書検索アシスタントです。
ユーザーの質問に対して、検索結果に含まれる情報を使って回答してください。

## 回答ルール

### 情報の使い方
- 検索結果に書かれていない情報は回答に含めない。一般知識や推測で補完しない
- 検索結果から具体的な情報（手続き、条件、数値、期限、対象者など）を抽出して回答に盛り込む
- 複数の検索結果に関連情報が分散している場合は、統合して回答を組み立てる
- 根拠となる文書を [1], [2] のように引用番号で示す

### 回答の形式
- 手続き・プロセスに関する質問: ステップや条件を箇条書きで示す
- 制度・規程に関する質問: 対象者、条件、期間、申請方法など具体的な項目を整理する
- 文書の内容確認: 重要なポイントを構造的に整理して提示する
- 検索結果に具体的な数値・期限・条件が含まれていれば、必ず回答に含める

### 回答できない場合
- 検索結果が空、または内容が質問と明らかに無関係な場合のみ「該当する情報が見つかりませんでした」と回答する

### 注意事項
- 検索対象は社内のSharePoint文書（契約書、申請書、事業計画、社内規程など）
- 検索結果にはPDF・Word・Excelから抽出されたテキストが含まれる
- 回答は日本語で行う"""

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
        category = doc.get("category") or ""
        meta = f"[{i}] {title}"
        if category:
            meta += f" ({category})"
        context_parts.append(f"{meta}\n{chunk}")
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
        temperature=0.3,
        max_tokens=1500,
    )

    answer = resp.choices[0].message.content.strip()

    # 回答全体が「該当なし」の場合のみ参照元を返さない（ファイル名漏洩防止）
    # 部分的に「見つかりませんでした」を含む場合は参照元を残す
    _NO_RESULT_PATTERNS = [
        "該当する情報が見つかりませんでした",
        "該当する情報は見つかりませんでした",
        "見つかりませんでした",
    ]
    answer_clean = answer.strip().replace(" ", "").replace("\n", "").replace("。", "")
    if any(p.replace("。", "") in answer_clean for p in _NO_RESULT_PATTERNS) and len(answer_clean) < 80:
        citations = []

    # 存在しない引用番号を除去
    max_ref = len(search_results)
    answer = re.sub(
        r"\[(\d+)\]",
        lambda m: m.group(0) if 1 <= int(m.group(1)) <= max_ref else "",
        answer,
    )

    return answer, citations
