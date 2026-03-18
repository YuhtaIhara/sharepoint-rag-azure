---
type: draft
document: 運用手順書
format: Word
issue: "#41"
created: 2026-03-18
updated: 2026-03-18
version: "0.1"
status: draft
---

<!-- Word 化時の表紙情報 -->
<!-- PJ名: SharePoint RAG チャットボット PoC -->
<!-- 文書名: 運用手順書 -->
<!-- 版数: 0.1 -->
<!-- 日付: 2026-03-18 -->
<!-- 作成者: 構築担当者 -->
<!-- 承認者: PJリーダー -->

# 運用手順書

## 変更履歴

| 版数 | 日付 | 変更者 | 変更内容 |
|------|------|--------|----------|
| 0.1 | 2026-03-18 | 構築担当者 | 初版作成 |

---

## 1. 概要

| 項目 | 内容 |
|------|------|
| 対象システム | SharePoint RAG チャットボット PoC |
| 目的 | 本システムの初期構築手順・日常運用・トラブルシューティングを一元的に記録する |
| 想定読者 | 構築担当者、運用担当者、後任引き継ぎ者 |
| 前提 | Claude Code 等のAIアシスタントなしで、人手で再現可能な手順書とする |

本書は「ゼロからこのシステムを構築・デプロイし、運用できる」ことを目標とした完全なリファレンスである。Azure リソースの構築手順は 10-構築手順書に詳述されているため、本書ではアプリケーション側のデプロイ・設定・運用に重点を置く。

---

## 2. システム構成概要

### 2.1 アーキテクチャ

```
[ユーザー]
  ↓ Entra ID SSO
[App Service (webapp)] ← Node.js Express / チャットUI
  ↓ POST /api/chat
[Azure Functions (functions)] ← Python 3.12 / バックエンドAPI
  ├→ [Azure OpenAI] ← クエリ書き換え + 回答生成 (gpt-4o-mini)
  ├→ [AI Search] ← ハイブリッド検索 + ACL フィルタ (text-embedding-3-large)
  └→ [Cosmos DB] ← 会話履歴 (ChatDB/conversations)

[SharePoint] → [sp_to_blob.py] → [Blob Storage]
  → [AI Search Indexer] → [AI Search Index]
  → [update_index_metadata.py] → ACL メタデータ反映
```

### 2.2 リソース一覧とホスト名

| リソース | 名前 | ホスト名 / エンドポイント | リージョン |
|---------|------|------------------------|----------|
| Resource Group | `rg-sprag-poc-jpe` | — | Japan East |
| Azure OpenAI (AI Foundry) | `oai-sprag-poc-eastus2` | `https://oai-sprag-poc-eastus2.services.ai.azure.com/` | East US 2 |
| AI Search | `srch-sprag-poc-jpe` | `https://srch-sprag-poc-jpe.search.windows.net` | Japan East |
| Storage Account (文書用) | `stspragpocjpe` | `https://stspragpocjpe.blob.core.windows.net/` | Japan East |
| Cosmos DB | `cosmos-sprag-poc-jpe` | — | Japan East |
| Key Vault | `kv-sprag-poc-jpe` | — | Japan East |
| Application Insights | `appi-sprag-poc-jpe` | — | Japan East |
| Azure Functions | `func-sprag-poc-jpe` | `https://func-sprag-poc-jpe-xxxxxxxxxx.japaneast-01.azurewebsites.net` | Japan East |
| App Service | `app-sprag-poc-jpe` | `https://app-sprag-poc-jpe.azurewebsites.net` | East Asia |
| Storage Account (Functions用) | `stfuncspragpoc` | — | Japan East |
| Document Intelligence | `di-sprag-poc-jpe` | `https://di-sprag-poc-jpe.cognitiveservices.azure.com/` | Japan East |
| Entra ID アプリ | `app-sprag-poc` | — | — |

> **注意**: Functions のホスト名は新しい Azure 命名形式 `{name}-{hash}.{region}-01.azurewebsites.net` が適用される。リソース作成時にハッシュが自動付与されるため、実際の URL は Azure ポータルで確認すること。

### 2.3 データフロー

1. **インジェスト**: SharePoint → (Graph API) → Blob Storage → (AI Search Indexer) → AI Search Index → (update_index_metadata.py) → ACL メタデータ反映
2. **クエリ**: ユーザー入力 → webapp → Functions → クエリ書き換え(OpenAI) → ハイブリッド検索(AI Search + ACL フィルタ) → 回答生成(OpenAI) → レスポンス
3. **会話履歴**: Functions ↔ Cosmos DB (セッション単位で保存・復元)

---

## 3. 初期構築手順（ゼロからの構築）

### 3.1 前提条件

| # | 条件 | 確認方法 |
|---|------|---------|
| 1 | Azure サブスクリプションに共同作成者権限がある | ポータル → サブスクリプション → IAM |
| 2 | Azure OpenAI の利用申請が承認済み | ポータルで Azure OpenAI リソース作成可能か確認 |
| 3 | Entra ID でアプリ登録の権限がある | ポータル → Entra ID → アプリの登録 |
| 4 | SharePoint テストサイトの管理者権限がある | SP サイト設定 → サイトの権限 で確認 |
| 5 | ローカルに Python 3.12+, Node.js 22+, Azure CLI がインストール済み | `python --version`, `node --version`, `az version` |
| 6 | bash 環境がある（Git Bash, WSL 等） | `envsubst` コマンドが利用可能であること |

### 3.2 Azure リソース構築

10-構築手順書 §4.0〜4.13 に従い、以下の順序でリソースを作成する。

1. Resource Group (`rg-sprag-poc-jpe`)
2. Entra ID アプリ登録 (`app-sprag-poc`)
3. Azure OpenAI + モデルデプロイ (`gpt-4o-mini`, `text-embedding-3-large`)
4. Document Intelligence (`di-sprag-poc-jpe`)
5. Storage Account (`stspragpocjpe`) + コンテナ `sharepoint-documents`
6. AI Search (`srch-sprag-poc-jpe`) — **S1 課金リソース $245.28/月**
7. Cosmos DB (`cosmos-sprag-poc-jpe`) + DB `ChatDB` + コンテナ `conversations`
8. Key Vault (`kv-sprag-poc-jpe`) + シークレット 9 件
9. Application Insights (`appi-sprag-poc-jpe`)
10. Azure Functions (`func-sprag-poc-jpe`)
11. App Service (`app-sprag-poc-jpe`) — **B1 課金リソース $14.60/月**
12. RBAC 10 件の割り当て
13. SharePoint フォルダ権限設定

> 所要時間目安: 約 1.5 時間。詳細パラメータは 05-パラメータシートを参照。

### 3.3 アプリケーションコードのデプロイ

リポジトリのクローンが前提。以降の手順はリポジトリルートをカレントディレクトリとする。

```bash
git clone https://github.com/<org>/sharepoint-rag-azure.git
cd sharepoint-rag-azure
```

---

#### 3.3.1 SP → Blob 同期スクリプト

**目的**: SharePoint の文書を Graph API 経由でダウンロードし、ACL メタデータ付きで Azure Blob Storage にアップロードする。

**場所**: `scripts/sp_to_blob.py`

##### Python 環境セットアップ

```bash
cd scripts
python -m venv .venv

# Windows (Git Bash / PowerShell)
source .venv/Scripts/activate
# macOS / Linux
# source .venv/bin/activate

pip install requests azure-storage-blob python-dotenv
```

##### .env 設定

`scripts/.env` を作成する。テンプレートは `scripts/.env.example`。

```ini
# Microsoft Graph API (Entra ID app: app-sprag-poc)
GRAPH_CLIENT_ID=<Entra ID アプリのクライアント ID>
GRAPH_CLIENT_SECRET=<Entra ID アプリのクライアントシークレット>
GRAPH_TENANT_ID=<テナント ID>

# Azure Blob Storage
STORAGE_CONNECTION_STRING=<stspragpocjpe の接続文字列>

# SharePoint
SP_SITE_HOSTNAME=<テナント>.sharepoint.com
SP_SITE_PATH=<サイトパス（ルートサイトの場合は空）>
SP_DOCUMENT_LIBRARY=Shared Documents

# 対象フォルダ（カンマ区切り、部分一致フィルタ）
SP_TARGET_FOLDERS=ダミーファイル
```

| 変数名 | 説明 |
|--------|------|
| `GRAPH_CLIENT_ID` | Entra ID アプリ `app-sprag-poc` のアプリケーション(クライアント) ID |
| `GRAPH_CLIENT_SECRET` | 同アプリのクライアントシークレット値 |
| `GRAPH_TENANT_ID` | Entra ID のディレクトリ(テナント) ID |
| `STORAGE_CONNECTION_STRING` | `stspragpocjpe` ストレージアカウントの接続文字列 |
| `SP_SITE_HOSTNAME` | SharePoint テナントのホスト名 |
| `SP_SITE_PATH` | サイトのパス（例: `sites/test-site`）。ルートサイトの場合は空 |
| `SP_DOCUMENT_LIBRARY` | ドキュメントライブラリ名。通常 `Shared Documents` |
| `SP_TARGET_FOLDERS` | 対象フォルダの部分一致フィルタ。カンマ区切り |

##### SP_TARGET_FOLDERS の意味

SharePoint のドキュメントライブラリルートには多数のフォルダが存在しうる（本 PoC 環境ではルートに 11 フォルダ）。全フォルダを処理すると不要な文書まで取り込まれるため、`SP_TARGET_FOLDERS` で対象を絞る。

本 PoC では `ダミーファイル` を指定することで、以下 3 フォルダのみを処理対象としている:
- `01_ダミーファイル 経営`
- `02_ダミーファイル 人事労務`
- `03_ダミーファイル 営業`

フィルタは部分一致。空の場合は全フォルダを処理する。

##### 実行手順

```bash
# 1. dry-run で対象ファイルを確認（アップロードしない）
python sp_to_blob.py --dry-run

# 出力例:
# [1/15] 01_ダミーファイル 経営/経営方針2026.pdf (category=01_ダミーファイル 経営, ACL=['leader@example.com'])
# [2/15] 02_ダミーファイル 人事労務/就業規則.docx (category=02_ダミーファイル 人事労務, ACL=['*'])
# ...

# 2. 問題なければ本番実行
python sp_to_blob.py
```

##### 出力の確認方法

1. Azure ポータル → `stspragpocjpe` → コンテナー → `sharepoint-documents`
2. フォルダ階層が SP と同一構造で Blob が存在することを確認
3. 各 Blob のメタデータに以下が設定されていること:
   - `source_url`: SP 上の元ファイル URL (URL エンコード済み)
   - `title`: ファイル名 (Base64 エンコード済み)
   - `category`: トップレベルフォルダ名 (Base64 エンコード済み)
   - `allowed_groups`: 閲覧可能ユーザーの JSON 配列（例: `["user@example.com"]` or `["*"]`）

##### ACL の動作

| SP フォルダの状態 | `allowed_groups` の値 | 意味 |
|------------------|----------------------|------|
| 権限継承（個別設定なし） | `["*"]` | 全員アクセス可 |
| 個別権限設定あり | `["user1@example.com", "user2@example.com"]` | 指定ユーザーのみ |

> 権限はトップレベルフォルダ単位で取得される。サブフォルダの個別権限には非対応（Phase 1.5 の改善候補）。

---

#### 3.3.2 AI Search パイプラインデプロイ

**目的**: AI Search のインデックス・データソース・スキルセット・インデクサーを一括作成する。

**場所**: `search/` ディレクトリ

##### 構成ファイル

| ファイル | 内容 |
|---------|------|
| `index.json` | インデックス定義。8 フィールド（chunk_id, parent_id, chunk, title, text_vector, category, source_url, allowed_groups）。ベクトル検索 (HNSW/cosine/3072次元) + セマンティック構成 |
| `datasource.json` | Blob Storage データソース。`stspragpocjpe` の `sharepoint-documents` コンテナに接続。マネージド ID 認証 |
| `skillset.json` | テキスト分割 (2000文字/200文字オーバーラップ) → OpenAI Embedding (text-embedding-3-large)。indexProjections で子ドキュメント生成 |
| `indexer.json` | データソース → スキルセット → インデックスの接続。手動スケジュール |
| `deploy.sh` | 上記 4 リソースを curl で一括デプロイするスクリプト |

##### 必要な環境変数

```bash
export SEARCH_ENDPOINT="https://srch-sprag-poc-jpe.search.windows.net"
export SEARCH_API_KEY="<AI Search の管理キー>"
export AZURE_OPENAI_API_KEY="<Azure OpenAI の API キー>"
export AZURE_OPENAI_ENDPOINT="https://oai-sprag-poc-eastus2.services.ai.azure.com/"
export SUBSCRIPTION_ID="<Azure サブスクリプション ID>"
```

| 変数名 | 使用箇所 | 取得元 |
|--------|---------|--------|
| `SEARCH_ENDPOINT` | 全 API コール | AI Search → キー → エンドポイント |
| `SEARCH_API_KEY` | 全 API コールの認証ヘッダー | AI Search → キー → プライマリ管理キー |
| `AZURE_OPENAI_API_KEY` | `skillset.json`, `index.json` の vectorizer | Azure OpenAI → キーとエンドポイント → KEY 1 |
| `AZURE_OPENAI_ENDPOINT` | `index.json` の vectorizer | Azure OpenAI → キーとエンドポイント → エンドポイント |
| `SUBSCRIPTION_ID` | `datasource.json` のマネージド ID 接続文字列 | ポータル → サブスクリプション |

##### envsubst による変数展開の仕組み

JSON テンプレートファイル内に `${VARIABLE_NAME}` のプレースホルダーがある。`deploy.sh` は `envsubst` コマンドでこれらを環境変数の実際の値に置換してから API に送信する。

例（`datasource.json` の抜粋）:
```json
"connectionString": "ResourceId=/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-sprag-poc-jpe/..."
```

##### 実行手順

```bash
cd search

# 環境変数を設定してから実行
chmod +x deploy.sh
./deploy.sh

# インデクサーも同時に実行する場合
./deploy.sh --run-indexer
```

出力例:
```
=== 1/4 Index 作成 ===
{"@odata.context":"...","name":"sprag-index",...}
=== 2/4 Data Source 作成 ===
{"@odata.context":"...","name":"sprag-datasource",...}
=== 3/4 Skillset 作成 ===
{"@odata.context":"...","name":"sprag-skillset",...}
=== 4/4 Indexer 作成 ===
{"@odata.context":"...","name":"sprag-indexer",...}
=== 完了 ===
```

##### インデクサー手動実行と確認

```bash
# インデクサー実行（deploy.sh の --run-indexer でも可）
curl -X POST "${SEARCH_ENDPOINT}/indexers/sprag-indexer/run?api-version=2024-07-01" \
  -H "api-key: ${SEARCH_API_KEY}"

# ステータス確認
curl -s "${SEARCH_ENDPOINT}/indexers/sprag-indexer/status?api-version=2024-07-01" \
  -H "api-key: ${SEARCH_API_KEY}" | python3 -m json.tool
```

確認ポイント:
- `lastResult.status` が `success` であること
- `lastResult.itemCount` が Blob 内のファイル数と一致すること
- `lastResult.errorCount` が 0 であること

Azure ポータルでの確認: AI Search → インデクサー → `sprag-indexer` → 実行履歴

##### スキルセットの indexProjections について

スキルセットはテキスト分割後のチャンクを `indexProjections` で子ドキュメントとしてインデックスに投影する。このとき `parent_id` が自動設定され、元の Blob パスから `chunk_id` が fixedLengthEncode で生成される。

**重要な制約**: indexProjections は Blob のカスタムメタデータの一部（`metadata_storage_name` 等の標準メタデータは伝播するが、`allowed_groups` のようなカスタムメタデータは子ドキュメントに自動伝播しない）。このため、次の手順 (§3.3.3) で別途メタデータを更新する必要がある。

---

#### 3.3.3 ACL メタデータ更新

**目的**: インデクサーが生成した子ドキュメント（チャンク）に、Blob のカスタムメタデータ（`allowed_groups`, `category`, `source_url`）を反映する。

**なぜ必要か**: AI Search の skillset で indexProjections を使用すると、Blob カスタムメタデータ（`allowed_groups` 等）は子ドキュメントに自動的には伝播しない。このスクリプトが Blob メタデータを読み取り、ファイル名をキーにインデックスドキュメントとマッチングし、AI Search REST API で一括更新（merge）する。

**場所**: `scripts/update_index_metadata.py`

##### 必要な環境変数

```bash
# scripts/.env に追加するか、シェルで export する
export STORAGE_CONNECTION_STRING="<stspragpocjpe の接続文字列>"
export SEARCH_ENDPOINT="https://srch-sprag-poc-jpe.search.windows.net"
export SEARCH_API_KEY="<AI Search の管理キー>"
```

| 変数名 | 説明 |
|--------|------|
| `STORAGE_CONNECTION_STRING` | Blob Storage の接続文字列。Blob メタデータ読み取りに使用 |
| `SEARCH_ENDPOINT` | AI Search のエンドポイント |
| `SEARCH_API_KEY` | AI Search の管理キー（REST API 直接呼び出し） |

> `scripts/.env` に `STORAGE_CONNECTION_STRING` が既に設定済みであれば、`SEARCH_ENDPOINT` と `SEARCH_API_KEY` を追加するだけでよい。

##### 実行手順

```bash
cd scripts
source .venv/Scripts/activate  # venv を有効化

python update_index_metadata.py
```

出力例:
```
2026-03-18 12:00:00 INFO === インデックスメタデータ更新開始 ===
2026-03-18 12:00:01 INFO Blob メタデータ 15 件取得
2026-03-18 12:00:02 INFO インデックスから 42 ドキュメント取得
2026-03-18 12:00:02 INFO マッチ: 42, 未マッチ: 0
2026-03-18 12:00:02 INFO 更新対象: 42 ドキュメント
2026-03-18 12:00:03 INFO バッチ 1-42/42: OK=42, Error=0
2026-03-18 12:00:03 INFO === 更新完了 ===
```

##### 確認方法

Azure ポータル → AI Search → インデックス → `sprag-index` → Search explorer:
```json
{
  "search": "*",
  "select": "chunk_id, title, allowed_groups, category",
  "top": 5
}
```

各ドキュメントの `allowed_groups` に値が設定されていること（空配列 `[]` ではないこと）を確認する。

##### マッチングロジック

スクリプトは以下のロジックでインデックスドキュメントと Blob をマッチングする:
1. Blob 一覧からファイル名を抽出
2. インデックスドキュメントの `title` フィールド（= ファイル名）と照合
3. マッチした場合、`allowed_groups`, `category`, `source_url` を merge 更新

「未マッチ」が多い場合は、Blob のファイル名とインデックスの title フィールドを比較して原因を調査する。

---

#### 3.3.4 Azure Functions デプロイ

**目的**: チャット API バックエンド（Python 3.12）を Azure Functions にデプロイする。

**場所**: `functions/` ディレクトリ

##### コード構成

| ファイル | 役割 |
|---------|------|
| `function_app.py` | エントリポイント。3 エンドポイント: `POST /api/chat`, `GET /api/health`, `POST /api/ingest` |
| `chat/orchestrator.py` | チャットのメインフロー。入力検証 → 履歴取得 → クエリ書き換え → 検索 → 回答生成 → 履歴保存 |
| `chat/search.py` | AI Search クライアント。ハイブリッド検索 (ベクトル + キーワード + セマンティックランカー) + ACL フィルタ |
| `chat/llm.py` | OpenAI クライアント。クエリ書き換え (temperature=0) + 回答生成 (temperature=0.1) |
| `chat/history.py` | Cosmos DB 会話履歴。セッション単位で保存・取得 |
| `host.json` | Functions ランタイム設定。タイムアウト 5 分、Application Insights サンプリング有効 |
| `requirements.txt` | Python 依存パッケージ |

##### ZIP パッケージ作成とデプロイ

```bash
cd functions

# 依存パッケージのインストール（ZIP に含める）
pip install -r requirements.txt --target .python_packages/lib/site-packages

# ZIP パッケージ作成
zip -r ../functions.zip . -x ".venv/*" "__pycache__/*" "*.pyc"

# デプロイ
az functionapp deployment source config-zip \
  -g rg-sprag-poc-jpe \
  -n func-sprag-poc-jpe \
  --src ../functions.zip
```

> デプロイ完了まで 2〜3 分かかる。完了後、ポータルの Functions 概要ページで `chat`, `health`, `ingest_trigger` の 3 関数が表示されることを確認。

##### 環境変数 16 件の設定

Azure ポータル → `func-sprag-poc-jpe` → 設定 → 環境変数 で以下を設定する。

| # | 種別 | 設定名 | 値 | 備考 |
|---|------|--------|-----|------|
| 1 | KV参照 | `AZURE_OPENAI_ENDPOINT` | `@Microsoft.KeyVault(VaultName=kv-sprag-poc-jpe;SecretName=AZURE-OPENAI-ENDPOINT)` | |
| 2 | KV参照 | `AZURE_OPENAI_API_KEY` | `@Microsoft.KeyVault(VaultName=kv-sprag-poc-jpe;SecretName=AZURE-OPENAI-KEY)` | |
| 3 | KV参照 | `AZURE_SEARCH_ENDPOINT` | `@Microsoft.KeyVault(VaultName=kv-sprag-poc-jpe;SecretName=SEARCH-ENDPOINT)` | |
| 4 | KV参照 | `AZURE_SEARCH_API_KEY` | `@Microsoft.KeyVault(VaultName=kv-sprag-poc-jpe;SecretName=SEARCH-API-KEY)` | |
| 5 | KV参照 | `COSMOS_CONNECTION_STRING` | `@Microsoft.KeyVault(VaultName=kv-sprag-poc-jpe;SecretName=COSMOS-CONNECTION-STRING)` | |
| 6 | KV参照 | `STORAGE_CONNECTION_STRING` | `@Microsoft.KeyVault(VaultName=kv-sprag-poc-jpe;SecretName=STORAGE-CONNECTION-STRING)` | |
| 7 | KV参照 | `GRAPH_CLIENT_ID` | `@Microsoft.KeyVault(VaultName=kv-sprag-poc-jpe;SecretName=GRAPH-CLIENT-ID)` | |
| 8 | KV参照 | `GRAPH_CLIENT_SECRET` | `@Microsoft.KeyVault(VaultName=kv-sprag-poc-jpe;SecretName=GRAPH-CLIENT-SECRET)` | |
| 9 | KV参照 | `GRAPH_TENANT_ID` | `@Microsoft.KeyVault(VaultName=kv-sprag-poc-jpe;SecretName=GRAPH-TENANT-ID)` | |
| 10 | 設定値 | `AZURE_OPENAI_CHAT_DEPLOYMENT` | `gpt-4o-mini` | |
| 11 | 設定値 | `AZURE_OPENAI_EMBEDDING_DEPLOYMENT` | `text-embedding-3-large` | |
| 12 | 設定値 | `AZURE_SEARCH_INDEX_NAME` | `sprag-index` | |
| 13 | 設定値 | `COSMOS_DB_DATABASE` | `ChatDB` | |
| 14 | 設定値 | `COSMOS_DB_CONTAINER` | `conversations` | |
| 15 | 設定値 | `BLOB_CONTAINER_NAME` | `sharepoint-documents` | |
| 16 | 自動 | `APPLICATIONINSIGHTS_CONNECTION_STRING` | (Functions 作成時に自動設定) | |

> KV 参照が正しく解決されるには、Functions のマネージド ID に Key Vault Secrets User ロールが付与されている必要がある（10-構築手順書 §4.11 #3）。

##### ヘルスチェック

```bash
curl -s "https://func-sprag-poc-jpe-xxxxxxxxxx.japaneast-01.azurewebsites.net/api/health"
# 期待出力: {"status": "ok"}
```

> `/api/health` は `AuthLevel.ANONYMOUS` のため、Function Key 不要。初回アクセスはコールドスタートで 10〜30 秒かかる場合がある。

##### Functions ホスト名の注意点

Functions のホスト名は Azure の新しい命名形式 `{name}-{hash}.{region}-01.azurewebsites.net` が適用される。PoC 環境の実際の URL:

```
https://func-sprag-poc-jpe-xxxxxxxxxx.japaneast-01.azurewebsites.net
```

この URL は Functions 作成時に決定され、Azure ポータルの Functions 概要ページで確認できる。webapp の `BACKEND_API_URL` にはこの完全な URL を設定する必要がある。

---

#### 3.3.5 webapp デプロイ

**目的**: チャット UI フロントエンド（Node.js 22 + Express）を App Service にデプロイする。

**場所**: `webapp/` ディレクトリ

##### コード構成

| ファイル | 役割 |
|---------|------|
| `server.js` | Express サーバー。`/api/chat` へのリクエストを Functions に中継（プロキシ）。リトライ付き (最大 3 回、60 秒タイムアウト) |
| `public/app.js` | チャット UI のクライアント JS。セッション ID を localStorage で管理。認証切れ時は自動リダイレクト |
| `public/index.html` | チャット UI の HTML |
| `public/style.css` | スタイルシート |
| `package.json` | Node.js 依存パッケージ (express のみ) |

##### デプロイ手順

```bash
cd webapp

# 依存パッケージインストール
npm install

# ZIP パッケージ作成
zip -r ../webapp.zip .

# デプロイ
az webapp deployment source config-zip \
  -g rg-sprag-poc-jpe \
  -n app-sprag-poc-jpe \
  --src ../webapp.zip
```

##### 環境変数の設定

Azure ポータル → `app-sprag-poc-jpe` → 設定 → 環境変数:

| # | 設定名 | 値 | 備考 |
|---|--------|-----|------|
| 1 | `BACKEND_API_URL` | `https://func-sprag-poc-jpe-xxxxxxxxxx.japaneast-01.azurewebsites.net` | Functions エンドポイント。末尾スラッシュなし |
| 2 | `FUNCTIONS_KEY` | Functions のデフォルトキー | Functions → アプリ キー → `default` の値 |

> `BACKEND_API_URL` に設定する値は Functions の実際のホスト名（ハッシュ付き）であること。`func-sprag-poc-jpe.azurewebsites.net` ではない。

##### 動作確認

```bash
curl -s -o /dev/null -w "%{http_code}" "https://app-sprag-poc-jpe.azurewebsites.net"
# Entra ID 認証が有効なら 302 (リダイレクト) が返る
```

ブラウザで `https://app-sprag-poc-jpe.azurewebsites.net` にアクセスし、Entra ID ログイン後にチャット UI が表示されることを確認する。

---

#### 3.3.6 Entra ID 認証設定

**A. App Service 認証の構成**

| 順 | 操作 | 設定値 |
|----|------|--------|
| 1 | App Service → 左メニュー「認証」→「ID プロバイダーの追加」 | — |
| 2 | ID プロバイダー: **Microsoft** を選択 | — |
| 3 | テナントの種類: **従業員** | 発行者テナントからのみ |
| 4 | アプリの登録の種類: **既存のアプリの登録からアプリを選択する** | — |
| 5 | アプリケーション (クライアント) ID: `app-sprag-poc` のクライアント ID | KV `GRAPH-CLIENT-ID` の値 |
| 6 | クライアント シークレット: `app-sprag-poc` のシークレット値 | KV `GRAPH-CLIENT-SECRET` の値 |
| 7 | 発行者の URL: `https://login.microsoftonline.com/<テナントID>/v2.0` | KV `GRAPH-TENANT-ID` の値を使用 |
| 8 | アクセスの制限: **認証が必要** | — |
| 9 | 認証されていない要求: **HTTP 302 Found リダイレクト: 推奨される ID プロバイダー** | — |
| 10 | 「追加」 | — |

**B. Entra ID アプリのリダイレクト URI 設定**

| 順 | 操作 | 設定値 |
|----|------|--------|
| 1 | Entra ID → アプリの登録 → `app-sprag-poc` → 認証 | — |
| 2 | プラットフォームの追加 → **Web** | — |
| 3 | リダイレクト URI | `https://app-sprag-poc-jpe.azurewebsites.net/.auth/login/aad/callback` |
| 4 | 暗黙的な許可 → **ID トークン** にチェック | — |
| 5 | 「構成」で保存 | — |

> App Service 認証が正しく構成されると、未認証のアクセスは Entra ID ログインページにリダイレクトされる。ログイン成功後、App Service が `x-ms-client-principal-name` (= ユーザーの UPN/メール) と `x-ms-client-principal-id` を HTTP ヘッダーに付与する。webapp はこの値を使って Functions に `user_id` と `user_groups` を渡す。

---

## 4. 日常運用

### 4.1 新規文書の追加

SharePoint に新しい文書をアップロードした後、以下の手順で検索インデックスに反映する。

```bash
# 前提: scripts ディレクトリの venv を有効化済み、環境変数を設定済み

# 1. SP → Blob 同期
cd scripts
python sp_to_blob.py

# 2. AI Search インデクサー実行
curl -X POST "${SEARCH_ENDPOINT}/indexers/sprag-indexer/run?api-version=2024-07-01" \
  -H "api-key: ${SEARCH_API_KEY}"

# 3. インデクサー完了を待つ（通常 1〜5 分）
# ステータス確認
curl -s "${SEARCH_ENDPOINT}/indexers/sprag-indexer/status?api-version=2024-07-01" \
  -H "api-key: ${SEARCH_API_KEY}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
s = d.get('lastResult', {})
print(f'Status: {s.get(\"status\", \"N/A\")}, Items: {s.get(\"itemCount\", 0)}, Errors: {s.get(\"errorCount\", 0)}')
"

# 4. ACL メタデータ更新（必須）
python update_index_metadata.py
```

> **重要**: 手順 4 は省略不可。インデクサーの indexProjections は Blob カスタムメタデータ (`allowed_groups`) を子ドキュメントに伝播しないため、このスクリプトがなければ ACL フィルタが機能しない。

### 4.2 権限変更への対応

SharePoint でフォルダ権限を変更した場合:

```bash
# 1. SP → Blob 再同期（ACL メタデータが更新される）
cd scripts
python sp_to_blob.py

# 2. ACL メタデータ更新（Blob メタデータ → インデックスへ反映）
python update_index_metadata.py
```

> 権限変更のみの場合、インデクサーの再実行は不要。`sp_to_blob.py` が Blob メタデータの `allowed_groups` を更新し、`update_index_metadata.py` がインデックスに反映する。

### 4.3 インデクサー再実行時の注意

インデクサーを再実行すると、indexProjections が再度子ドキュメントを生成する。この際、`allowed_groups`, `category`, `source_url` はデフォルト値（空）にリセットされる。

**インデクサー実行後は必ず `update_index_metadata.py` を実行すること。**

### 4.4 トラブルシューティング

| 症状 | 原因 | 対処 |
|------|------|------|
| 初回リクエストでタイムアウト / エラー | Functions Consumption プランのコールドスタート (10〜30秒) | webapp のリトライ機能で自動回復する。もう一度送信すれば解消。`/api/health` で事前にウォームアップも可 |
| 「該当する情報が見つかりませんでした」 | (a) ACL フィルタで除外 (b) チャンクに該当情報なし (c) クエリ書き換えが不適切 | (a) ユーザーの UPN が `allowed_groups` に含まれるか AI Search Explorer で確認 (b) 別の表現で検索 (c) Application Insights でリライトされたクエリを確認 |
| 502 Bad Gateway | webapp → Functions 接続失敗 | (1) `BACKEND_API_URL` が正しいか確認（ハッシュ付きホスト名であること）(2) Functions が Running 状態か確認 (3) `FUNCTIONS_KEY` が正しいか確認 |
| AADSTS エラー（認証画面でエラー） | Entra ID 認証設定不備 | (1) リダイレクト URI が正しいか確認 (2) ID トークンが有効化されているか確認 (3) テナント ID が一致しているか確認 |
| Functions の環境変数で「Key Vault Reference Error」 | RBAC 設定不備 | Functions のマネージド ID に `kv-sprag-poc-jpe` の Key Vault Secrets User ロールが付与されているか確認 |
| インデクサーのエラー `0 items processed` | データソースの接続エラー | AI Search のマネージド ID に `stspragpocjpe` の Storage Blob Data Reader ロールが付与されているか確認 |
| インデクサーの Embedding エラー | OpenAI 接続エラー | (1) `skillset.json` の `apiKey` / `resourceUri` が正しいか確認 (2) AI Search MI に OpenAI の Cognitive Services OpenAI User ロールが付与されているか確認 |
| ハルシネーション（一般知識で回答） | LLM がシステムプロンプトを無視 | (1) `llm.py` の `SYSTEM_PROMPT` を確認 (2) 検索結果が返っているか確認（結果が空なら検索側の問題）(3) GPT-4o への切替を検討 |
| `allowed_groups` が空 | `update_index_metadata.py` 未実行 or マッチング失敗 | (1) スクリプトを実行 (2) ログの「未マッチ」数を確認。Blob ファイル名とインデックスの title が一致しているか調査 |
| Cosmos DB 接続エラー（会話履歴不可） | 初回接続 or 接続文字列不正 | 会話履歴の取得・保存は try-except で囲まれており、失敗しても回答生成は続行される。Cosmos DB の接続文字列を確認 |

### 4.5 ログ確認

| 対象 | 確認方法 |
|------|---------|
| Functions の実行ログ | Azure ポータル → `func-sprag-poc-jpe` → 監視 → ログ ストリーム |
| Application Insights | Azure ポータル → `appi-sprag-poc-jpe` → トランザクションの検索 / ライブ メトリック |
| AI Search インデクサー履歴 | Azure ポータル → `srch-sprag-poc-jpe` → インデクサー → `sprag-indexer` → 実行履歴 |
| webapp のログ | Azure ポータル → `app-sprag-poc-jpe` → 監視 → ログ ストリーム |

---

## 5. PoC 終了時の手順

### 5.1 リソース削除

| 順 | 操作 | 備考 |
|----|------|------|
| 1 | Azure ポータル → `rg-sprag-poc-jpe` → リソースグループの削除 | 全 Azure リソースが一括削除される |
| 2 | Entra ID → アプリの登録 → `app-sprag-poc` → 削除 | リソースグループに含まれないため個別削除が必要 |

### 5.2 削除期限

| タグ | 値 | 意味 |
|------|-----|------|
| `DeleteAfter` | `2026-03-31` | 全リソースに設定済み。この日までに削除する |

### 5.3 コスト停止の優先度

即時コスト削減が必要な場合は、以下の順で停止・削除する:

| 優先度 | リソース | 月額 | 操作 |
|--------|---------|------|------|
| 1 | AI Search S1 | ~$245 | 削除（停止不可） |
| 2 | App Service B1 | ~$13 | App Service プラン削除 |
| 3 | その他 | ~$8 | 従量課金のため使用しなければほぼ $0 |

---

## 6. チューニング候補（Phase 1.5）

| # | 改善 | 現状 | 効果 | コスト | 工数 |
|---|------|------|------|--------|------|
| 1 | GPT-4o-mini → GPT-4o | 回答品質に限界（要約・統合の精度） | 回答品質向上 | ~$10/月追加 | 設定変更のみ |
| 2 | Document Intelligence 活用 | テキスト抽出は AI Search 標準のみ | Excel/PDF のチャンク品質向上 | ~$5 (初回のみ) | スキルセット修正 |
| 3 | チャンクサイズ 2000→1000 | 2000 文字 / 200 文字オーバーラップ | 検索精度向上（細粒度チャンク） | 無料（再インデックス） | skillset.json 修正 + 再デプロイ |
| 4 | セキュリティグループ対応 | ACL はメールアドレスベース | Entra ID セキュリティグループでのアクセス制御 | 開発工数 | Graph API でグループメンバーシップ取得に拡張 |
| 5 | Functions Premium プラン | Consumption (コールドスタートあり) | コールドスタート解消 | ~$150/月追加 | SKU 変更 |
| 6 | サブフォルダ個別権限対応 | トップレベルフォルダ単位の ACL のみ | より細かい権限制御 | 開発工数 | sp_to_blob.py の再帰的権限取得対応 |

---

## 7. 関連文書

| # | 文書 | 内容 |
|---|------|------|
| 01 | 要件定義書 (`docs/01-requirements.md`) | スコープ、ユースケース、機能/非機能要件 |
| 02 | アーキテクチャ設計書 (`docs/02-architecture.md`) | コンポーネント設計、データフロー、ADR |
| 03 | セキュリティ設計書 (`docs/03-security.md`) | STRIDE 脅威モデル、認証/認可、ACL 設計 |
| 04 | リソース設計書 (`docs/04-resource-design.md`) | 命名規則、SKU 選定、コスト試算、RBAC |
| 05 | パラメータシート (`docs/05-parameter-sheet.md`) | 全リソースの設定値（機密値は REDACT 済み） |
| 10 | 構築手順書 (`docs/10-build-guide.md`) | Azure リソースの作成手順（ポータル操作） |
| 11 | 試験仕様書 (`docs/11-test-spec.md`) | ACL シナリオテスト |

---

以上
