# アーキテクチャ設計書

## 変更履歴

| 版数 | 日付 | 変更者 | 変更内容 |
|------|------|--------|----------|
| 0.1 | 2026-03-13 | 構築担当者 | 初版ドラフト作成 |
| 0.2 | 2026-03-14 | 構築担当者 | 重複整理・圧縮 |
| 0.3 | 2026-03-14 | 構築担当者 | Alternatives Considered・ADR 追加（ベストプラクティス調査に基づく構成改善） |
| 0.4 | 2026-03-14 | 構築担当者 | C4 モデル図ガイド追加 |
| 0.5 | 2026-03-15 | 構築担当者 | テンプレート準拠のセクション構造へ再編。プロセスノート削除 |
| 0.6 | 2026-03-15 | 構築担当者 | リージョンを Japan East に変更。LLM を GPT-4o-mini に変更 |
| 0.7 | 2026-03-15 | 構築担当者 | ACL 制御を Phase 2 から Phase 1 に統合。フェーズ分け廃止 |
| 0.8 | 2026-03-18 | 構築担当者 | リージョン差異反映（OpenAI→East US 2、App Service→East Asia） |
| 0.9 | 2026-03-18 | 構築担当者 | 実装実績に基づきテキスト構成図・データフロー・スキルセット構成を更新 |
| 1.0 | 2026-03-18 | 構築担当者 | DI Layout スキル統合。2インデクサー構成（DI + SplitSkill フォールバック）。Cognitive Services マルチサービスアカウント追加 |
| 1.1 | 2026-03-18 | 構築担当者 | IaC (Terraform) + CI/CD (GitHub Actions) + SP 同期自動化 (Timer Trigger) セクション追加 |

---

## 1. 設計方針

| # | 方針 | 説明 |
|---|------|------|
| 1 | GPT-RAG リファレンス準拠 | Microsoft 公式の RAG 構成を採用。独自設計のリスクを回避 |
| 2 | GA サービスのみ | SP インデクサー（プレビュー・GA 予定なし）は不採用。Blob indexer（GA）経由 |
| 3 | PoC 構成 + スケール設計 | 10名・100件以上で構築。100-300名へのパスは設計書に記載 |
| 4 | マネージドサービス優先 | 自前運用を最小化 |
| 5 | セキュリティ バイ デザイン | ACL（ドキュメント単位のアクセス制御）を初期構築から組み込む |

---

## 2. 全体構成図

### 2.1 テキスト構成図

```
[SharePoint Online]
    │ Graph API（sp_to_blob.py）
    ▼
[Blob Storage] ── sharepoint-documents（メタデータに ACL・category・source_url を格納）
    │ Blob Indexer
    ▼
[AI Search スキルセット]
    ├─ DocumentIntelligenceLayoutSkill（構造解析+チャンキング: 2000文字、オーバーラップ200）
    │    ↑ di-sprag-poc-jpe（Layout モデル v4.0）
    └─ AzureOpenAIEmbeddingSkill — text-embedding-3-large（ベクトル生成）
    │
    ▼
[AI Search (S1)] ── ハイブリッド検索 + セマンティックランカー + ACL フィルタ
    │                  ↑ update_index_metadata.py で allowed_groups 等を後付け更新
    │
    ▼
[App Service] ── Node.js プロキシ + Entra ID SSO（ユーザー email 抽出）
    │
    ▼
[Azure Functions] ── Python オーケストレーション
    ├─ クエリ書き換え → 検索 → プロンプト構築
    ├─→ [Azure OpenAI GPT-4o-mini ※East US 2] → 根拠リンク付き回答
    └─→ [Cosmos DB] ← 会話履歴
    │
    ▼
[App Service] → ユーザー
    │
[共通] Key Vault / Application Insights / Entra ID
```

### 2.2 C4 モデル図（draw.io 作成ガイド）

[C4 モデル](https://c4model.com/) に基づく3レベルの構成図。

**Level 1: System Context 図**

システム全体と外部アクターの関係を示す。技術詳細は含めない。

| 要素 | 種別 | 説明 |
|------|------|------|
| PoC ユーザー（10名） | Person | チャット UI を通じて SP 文書を検索・質問 |
| RAG チャットボット | Software System | 本 PoC のスコープ |
| SharePoint Online | External System | 検索対象の文書ソース |
| Entra ID | External System | SSO 認証プロバイダ |

**Level 2: Container 図**

システム内部のコンテナ（デプロイ単位）と通信方向を示す。

| コンテナ | 技術 | 責務 |
|---------|------|------|
| チャット UI | App Service / Node.js | ユーザーインターフェース |
| オーケストレーター | Azure Functions / Python | クエリ処理・プロンプト構築 |
| 検索エンジン | AI Search S1 | ハイブリッド検索 + セマンティックランカー |
| LLM | Azure OpenAI GPT-4o-mini | 回答生成 |
| 文書ストア | Blob Storage | SP 文書の中間格納 |
| 会話履歴 DB | Cosmos DB | セッション管理 |
| シークレット管理 | Key Vault | API キー・接続文字列 |

**Level 3: Deployment 図**

Azure リソースの物理配置を示す。リソース設計書の命名と対応させる。

| 要素 | 内容 |
|------|------|
| Azure Subscription | 顧客テナント |
| Resource Group | `rg-sprag-poc-jpe` |
| リージョン | Japan East |
| ネットワーク | PoC: パブリック / スケール時: VNet + Private Endpoint |
| 補足 | OpenAI は East US 2、App Service は East Asia（Japan East の制約による） |

---

## 3. コンポーネント一覧

| # | コンポーネント | サービス / SKU | 役割 | 選定理由 |
|---|---|---|---|---|
| 1 | 文書取得 | Graph API → Blob | SP 文書を Blob に同期 | SP インデクサーが GA 予定なしのため Blob 経由が正攻法 |
| 2 | 文書解析+チャンキング | Document Intelligence Layout | DI Layout モデルで文書構造を解析し、構造認識チャンクを生成（2000文字、オーバーラップ200） | DI が文書構造（表・見出し・段落）を理解した上でチャンク分割。Excel のフリガナ・セル参照ノイズを除去 |
| 3 | 埋め込み | OpenAI text-embedding-3-large | 3072次元ベクトル生成 | Azure OpenAI 最高精度の埋め込みモデル |
| 4 | 検索 | AI Search S1 | ハイブリッド検索 + セマンティックランカー | ベクトル+キーワード+再ランキングの3段構え。S1 はベクトル検索の最小 SKU |
| 5 | 回答生成 | OpenAI GPT-4o-mini | 根拠付き自然言語回答 | Japan East 非対応のため **East US 2** にデプロイ（`oai-sprag-poc-eastus2`）。精度向上時は GPT-4o に切替可能 |
| 6 | オーケストレーション | Azure Functions (Python) | クエリ処理・プロンプト構築 | サーバーレス + Semantic Kernel（GPT-RAG 採用） |
| 7 | チャット UI | App Service B1 (Node.js) | Web チャット + SSO 認証 | Entra ID SSO 統合が容易。Japan East B1 クォータ不足のため **East Asia** にデプロイ |
| 8 | 会話履歴 | Cosmos DB サーバーレス | セッション単位の Q&A 保存 | GPT-RAG 推奨。低コスト |
| 9 | シークレット | Key Vault | API キー・接続文字列の一元管理 | Azure 標準。マネージド ID で参照 |
| 10 | 監視 | Application Insights | トレース・ログ | Functions/App Service とネイティブ統合 |
| 11 | 認証 | Entra ID | SSO + Graph API 認証 | SP 権限取得に必須 |
| 12 | スキル課金 | Cognitive Services マルチサービス S0 | DI Layout スキルの課金リソース | DI Layout は 20doc/日超で課金リソース必須。マルチサービスアカウントが必要（単体 DI リソースのキーは不可） |

---

## 4. Alternatives Considered

主要な技術選定で検討した代替案と、不採用の理由。

| 選定事項 | 採用 | 代替案 | 不採用理由 |
|---------|------|--------|-----------|
| SP 文書取得 | Graph API → Blob indexer | SP indexer（直接） | プレビューのまま GA 予定なし。本番運用に採用不可 |
| チャンキング | Document Intelligence Layout（text output + chunkingProperties） | SplitSkill（固定長） | DI Layout が文書構造を理解した上でチャンク分割。Excel のフリガナ・セル参照ノイズ除去にも有効。SplitSkill は構造を無視した単純文字数分割のため品質が劣る |
| 埋め込みモデル | text-embedding-3-large (3072d) | text-embedding-3-small (1536d) | PoC では精度優先。コスト差は微少（$0.13 vs $0.02/1M tokens） |
| LLM | GPT-4o-mini (Standard) | GPT-4o (Global Standard) | Japan East で GPT-4o の Standard デプロイ不可。精度向上時は Global Standard に切替可能 |
| オーケストレーション | Semantic Kernel (Functions) | LangChain | GPT-RAG リファレンスが Semantic Kernel 採用。Azure 統合が深い |
| 検索 SKU | AI Search S1 | AI Search Basic/Free | ベクトル検索は S1 以上が必須。Basic ではベクトルインデックス不可 |
| 会話履歴 | Cosmos DB サーバーレス | Table Storage | GPT-RAG 推奨。JSON 柔軟性・パーティション設計がチャット向き |
| チャット UI | App Service B1 | Container Apps | SSO 統合が App Service のほうが容易。PoC 規模では Container Apps のメリットが薄い |

---

## 5. データフロー

### 5.1 インジェスション（文書取り込み）

```
1. sp_to_blob.py（手動実行）
   SP → Graph API → ファイル取得 + フォルダ権限取得
   → Blob にアップロード（メタデータ: allowed_groups, category, source_url）
   ※ 継承権限（明示的権限なし）のフォルダは ["*"]（全員アクセス可）

2. AI Search インデクサー × 2（手動実行）
   ■ DI インデクサー（.pdf/.docx/.xlsx/.pptx → 252件）
     Blob → DocumentIntelligenceLayoutSkill（構造解析+チャンキング: 2000文字/200オーバーラップ）
          → AzureOpenAIEmbeddingSkill（text-embedding-3-large）→ インデックスに格納
   ■ フォールバックインデクサー（.doc/.csv/その他 → 23件）
     Blob → SplitSkill（テキスト分割: 2000文字/200オーバーラップ）
          → AzureOpenAIEmbeddingSkill → インデックスに格納
   ※ DI 非対応形式（.doc 等）は SplitSkill でフォールバック。両インデクサーが同一インデックスに書き込む

3. update_index_metadata.py（手動実行）
   Blob メタデータ（allowed_groups, category, source_url）を読み取り
   → インデックスの既存ドキュメントに merge 更新
```

> **注**: 2インデクサー構成。DI Layout 対応形式（PDF/DOCX/XLSX/PPTX）は `sprag-indexer` で構造認識チャンキング、非対応形式（.doc/.csv）は `sprag-indexer-fallback` で SplitSkill フォールバック。課金は Cognitive Services マルチサービスアカウント `cog-sprag-poc-jpe` 経由。

### 5.2 クエリ（検索・回答）

```
ユーザー → App Service（server.js: X-MS-CLIENT-PRINCIPAL-NAME からユーザー email 抽出）
  → Azure Functions（orchestrator.py）
  → AI Search ハイブリッド検索 + ACL フィルタ（allowed_groups + ワイルドカード "*" 対応）
  → セマンティックランカーで再ランキング
  → 上位チャンク + 会話履歴 + システムプロンプト → GPT-4o-mini
  → 根拠リンク付き回答 → ユーザー（「該当なし」回答時は citation を抑制）
  → Cosmos DB に会話履歴保存
```

---

## 6. 認証経路

| 経路 | 方式（PoC） | 100-300名時 |
|---|---|---|
| ユーザー → App Service | Entra ID SSO | + 条件付きアクセス |
| Functions → Graph API | クライアントシークレット | 証明書認証 |
| Functions → OpenAI | API キー（Key Vault） | マネージド ID |
| Functions → Cosmos DB | 接続文字列（Key Vault） | マネージド ID |
| AI Search → Blob / OpenAI | マネージド ID | 同左 |
| Functions / App Service → Key Vault | マネージド ID | 同左 |

---

## 7. 要件トレーサビリティ

| 要件 | 実現 |
|---|---|
| F-01 文書検索 | AI Search ハイブリッド検索 + セマンティックランカー |
| F-02 回答生成 | GPT-4o-mini + 根拠チャンクベースのプロンプト |
| F-03 会話履歴 | Cosmos DB（sessionId パーティション） |
| F-04 文書取り込み | Graph API → Blob → スキルセット → インデックス |
| F-05 認証 | Entra ID SSO |
| F-06 チャット UI | App Service |
| F-07 ACL 制御 | allowed_groups + セキュリティフィルタ |

---

## 8. IaC (Terraform)

### 8.1 設計方針

| 方針 | 説明 |
|------|------|
| 基盤リソースの IaC 化 | 13 リソース + RBAC 10件 + KV シークレット 9件を Terraform で宣言的管理 |
| コードデプロイは CI/CD | Functions / webapp のアプリケーションコードは GitHub Actions で自動デプロイ |
| destroy 事故防止 | Terraform は手動 `plan → apply`。CI/CD パイプラインに載せない |
| 既存リソース温存 | Entra ID App = `data` 参照、Storage (文書用) = `terraform import` |

### 8.2 ファイル構成

```
infra/
  providers.tf      # azurerm + azuread provider
  variables.tf      # 全入力変数
  main.tf           # Resource Group (data) + 共通タグ
  entra.tf          # data: Entra ID アプリ参照
  openai.tf         # Azure OpenAI + モデルデプロイ x2
  di.tf             # Document Intelligence S0
  cognitive.tf      # Cognitive Services マルチサービス S0
  storage.tf        # Storage x2 (文書用=import, Functions用=新規)
  search.tf         # AI Search S1 + terraform_data (search objects)
  cosmosdb.tf       # Cosmos DB サーバーレス
  keyvault.tf       # Key Vault + シークレット 9件
  appinsights.tf    # Application Insights + Log Analytics
  functions.tf      # Functions (Y1) + MI + アプリ設定 (KV参照)
  appservice.tf     # App Service (B1, East Asia) + MI
  rbac.tf           # RBAC 10件
  outputs.tf        # エンドポイント・キー出力
  cleanup.sh        # terraform apply 前のリソース削除
```

### 8.3 Azure ポータルとの対応

| Terraform 操作 | Azure ポータル相当操作 |
|---------------|-------------------|
| `terraform plan` | リソース作成画面の「確認と作成」 |
| `terraform apply` | 「作成」ボタン（全リソースを依存順に自動作成） |
| `terraform destroy` | リソースグループ内の管理対象リソースを個別削除 |
| `terraform import` | 既存リソースをポータルで確認し、Terraform 管理下に登録 |
| `terraform output` | ポータルでエンドポイント・キーを個別確認 |

---

## 9. CI/CD (GitHub Actions)

### 9.1 設計方針

| 方針 | 説明 |
|------|------|
| コードデプロイのみ自動化 | 基盤リソース (Terraform) は手動。アプリコードのみ CI/CD |
| path フィルタ | `functions/**` / `webapp/**` 変更時のみトリガー |
| 手動トリガー対応 | `workflow_dispatch` で任意タイミングのデプロイも可能 |

### 9.2 ワークフロー

```
[git push main]
  ├─ functions/ 変更 → deploy-functions.yml
  │    Python 3.12 + pip install → Azure Functions Action
  └─ webapp/ 変更 → deploy-webapp.yml
       Node.js 22 + npm install → Azure Web Apps Deploy Action
```

---

## 10. SP 同期の自動化

### 10.1 アーキテクチャ

```
[SP ファイル追加/削除/権限変更]
    ↓ Timer Trigger（毎時0分）
[Azure Functions: sync_trigger]
    ├─ SP → Blob 差分同期（lastModifiedDateTime 比較）
    └─ インデックスメタデータ更新（ACL 反映）
    ↓ インデクサー自動実行（schedule: PT1H）
[AI Search: sprag-indexer + sprag-indexer-fallback]
    → インデックス自動更新
```

### 10.2 差分同期

SP の `lastModifiedDateTime` と Blob の `Last-Modified` を比較し、変更があるファイルだけ同期する。SP に存在しないファイルは Blob から削除される。

---

## 11. 関連文書

| 文書 | 内容 |
|---|---|
| 要件定義書 | 本書が実現する要件 |
| リソース設計書 | SKU・設定値・コスト |
| セキュリティ設計書 | 認証・認可・ネットワーク詳細 |
| 構築手順書 | リソース作成手順 |

---

## 付録A: インデックス設計

| フィールド | 型 | 用途 |
|---|---|---|
| chunk_id | string | チャンク一意 ID |
| parent_id | string | 元文書 ID |
| chunk | string | チャンクテキスト（検索対象） |
| title | string | 文書タイトル |
| text_vector | Collection(Edm.Single) | 埋め込みベクトル（3072次元） |
| category | string | フォルダカテゴリ |
| source_url | string | SP 上の元ファイル URL（根拠リンク用） |
| allowed_groups | Collection(Edm.String) | ACL グループ ID |

---

## 付録B: ACL 制御

ACL の詳細は 03-セキュリティ設計書 §5 を参照。

---

以上
