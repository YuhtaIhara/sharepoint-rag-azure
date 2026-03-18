# リソース設計書 + コスト試算

## 変更履歴

| 版数 | 日付 | 変更者 | 変更内容 |
|------|------|--------|----------|
| 0.1 | 2026-03-14 | 構築担当者 | 初版ドラフト作成 |
| 0.2 | 2026-03-14 | 構築担当者 | CAF 命名規則準拠・タギング戦略追加・SKU 選定理由追加（ベストプラクティス調査に基づく構成改善） |
| 0.3 | 2026-03-14 | 構築担当者 | Azure Pricing Calculator エビデンスリンク追加 |
| 0.4 | 2026-03-15 | 構築担当者 | リージョンを Japan East に変更。命名規則を jpe に統一。LLM を GPT-4o-mini に変更 |
| 0.5 | 2026-03-18 | 構築担当者 | リージョン差異反映（OpenAI→East US 2、App Service→East Asia）。RBAC #10 設定済に更新 |
| 0.6 | 2026-03-18 | 構築担当者 | Functions ホスト名を実績値に更新（新 Azure 命名形式） |

---

## シート1: 命名規則

### 命名体系

[Azure CAF 命名規則](https://learn.microsoft.com/ja-jp/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming) に準拠。

```
{CAF略称}-{ワークロード}-{環境}-{リージョン}
```

| 要素 | 値 | 説明 |
|------|-----|------|
| ワークロード | `sprag` | SharePoint RAG |
| 環境 | `poc` | PoC 環境（本番時は `prd`） |
| リージョン | `jpe` | Japan East |

> CAF 略称一覧: [Resource abbreviations](https://learn.microsoft.com/ja-jp/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations)

### リソース名一覧

| # | サービス | CAF 略称 | リソース名 | 命名制約 |
|---|---------|---------|-----------|---------|
| 0 | Resource Group | `rg` | `rg-sprag-poc-jpe` | — |
| 1 | Entra ID アプリ | — | `app-sprag-poc` | — |
| 2 | Azure OpenAI | `oai` | `oai-sprag-poc-jpe` | 英数字・ハイフン |
| 3 | Document Intelligence | `di` | `di-sprag-poc-jpe` | 英数字・ハイフン |
| 4 | Storage Account | `st` | `stspragpocjpe` | 小文字+数字のみ、3-24文字、グローバル一意 |
| 5 | AI Search | `srch` | `srch-sprag-poc-jpe` | 小文字+数字+ハイフン、グローバル一意 |
| 6 | Cosmos DB | `cosmos` | `cosmos-sprag-poc-jpe` | 小文字+数字+ハイフン、グローバル一意 |
| 7 | Key Vault | `kv` | `kv-sprag-poc-jpe` | 英数字+ハイフン、グローバル一意 |
| 8 | Application Insights | `appi` | `appi-sprag-poc-jpe` | — |
| 9 | Azure Functions | `func` | `func-sprag-poc-jpe` | グローバル一意 |
| 10 | App Service | `app` | `app-sprag-poc-jpe` | グローバル一意 |
| 11 | Functions 用 Storage | `st` | `stfuncspragpoc` | 小文字+数字のみ |

### タギング戦略

全リソースに以下の必須タグを付与する。

| タグ名 | 必須 | 値 | 用途 |
|--------|------|-----|------|
| `Environment` | Yes | `poc` | 環境識別 |
| `Project` | Yes | `sp-rag` | プロジェクト識別・コスト配賦 |
| `Owner` | Yes | `project-owner` | 管理責任者 |
| `CreatedDate` | Yes | `2026-03-14` | 作成日（PoC 終了判断用） |
| `DeleteAfter` | Yes | `2026-03-31` | PoC 終了後の削除期限 |

> 本番移行時は `CostCenter`、`Department` を追加。Azure Policy で必須タグの強制を検討。

---

## シート2: リソース一覧

基本リージョン: Japan East（AI Search + Document Intelligence 同一リージョン必須）。例外: Azure OpenAI → East US 2（JE 非対応）、App Service → East Asia（JE B1 クォータ不足）

| # | リソース名 | サービス | SKU | 設定値 | 用途 | SKU 選定理由 | 依存先 |
|---|-----------|---------|-----|--------|------|-------------|--------|
| 0 | `rg-sprag-poc-jpe` | Resource Group | — | Japan East / サブスクリプション: Azure サブスクリプション 1 (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`) | 全リソースの入れ物 | — | — |
| 1 | `app-sprag-poc` | Entra ID アプリ登録 | — | シングルテナント / Sites.Read.All, Files.Read.All / シークレット6ヶ月 | Graph API 認証 | — | — |
| 2 | `oai-sprag-poc-eastus2` | Azure AI Foundry (OpenAI) | S0 | GPT-4o-mini: 30K TPM / text-embedding-3-large: 120K TPM / **East US 2** | 回答生成 + 埋め込み | JE 非対応のため East US 2 | — |
| 3 | `di-sprag-poc-jpe` | Document Intelligence | S0 | — | PDF/Office 構造抽出 | Free は月500ページ制限。S0 で従量課金 | — |
| 4 | `stspragpocjpe` | Storage Account | Standard LRS | コンテナ: `sharepoint-documents` / パブリックアクセス無効 / 論理削除有効 | SP 文書格納 | PoC は冗長性不要。LRS が最安 | — |
| 5 | `srch-sprag-poc-jpe` | AI Search | **S1** | レプリカ: 1 / パーティション: 1 / セマンティックランカー: Free / マネージド ID: ON | 検索エンジン | ベクトル検索は S1 以上必須。Basic 不可 | #2, #3, #4 |
| 6 | `cosmos-sprag-poc-jpe` | Cosmos DB | サーバーレス (NoSQL) | DB: `ChatDB` / コンテナ: `conversations` / PK: `/sessionId` | 会話履歴 | 低頻度アクセスのためサーバーレスが最安 | — |
| 7 | `kv-sprag-poc-jpe` | Key Vault | Standard | RBAC / シークレット9個 | シークレット管理 | Standard で十分（Premium は HSM 用） | 全リソース |
| 8 | `appi-sprag-poc-jpe` | Application Insights | ワークスペースベース | 日次上限設定推奨 | 監視 | 従量課金のみ | — |
| 9 | `func-sprag-poc-jpe` | Azure Functions | 従量課金 | Python 3.12 / Linux / マネージド ID: ON / ホスト名: `func-sprag-poc-jpe-xxxxxxxxxx.japaneast-01.azurewebsites.net` | パイプライン + オーケストレーション | PoC は無料枠内。Premium は VNet 統合時 | #4, #7, #8 |
| 10 | `app-sprag-poc-jpe` | App Service | **B1** (Linux) | Node.js 22 LTS / マネージド ID: ON / **East Asia** | チャット UI | JE B1 クォータ不足のため East Asia | #7, #9 |
| 11 | `stfuncspragpoc` | Storage Account | Standard LRS | Functions 内部用 | Functions ランタイム | Functions ランタイム要件 | — |

### RBAC 設定

| 付与先 | 対象リソース | ロール |
|--------|------------|--------|
| AI Search MI | Storage (#4) | Storage Blob Data Reader |
| AI Search MI | Azure OpenAI (#2, East US 2) | Cognitive Services OpenAI User |
| Functions MI | Key Vault (#7) | Key Vault Secrets User |
| Functions MI | Storage (#4) | Storage Blob Data Contributor |
| Functions MI | Azure OpenAI (#2) | Cognitive Services OpenAI User |
| App Service MI | Key Vault (#7) | Key Vault Secrets User |
| 自分自身 | AI Search (#5) | Search Service Contributor + Search Index Data Contributor + Search Index Data Reader |
| 自分自身 | Key Vault (#7) | Key Vault Secrets Officer |

### Key Vault シークレット

| シークレット名 | ソース |
|---|---|
| `AZURE-OPENAI-KEY` | #2 API キー |
| `AZURE-OPENAI-ENDPOINT` | #2 エンドポイント |
| `GRAPH-CLIENT-ID` | #1 クライアント ID |
| `GRAPH-CLIENT-SECRET` | #1 シークレット値 |
| `GRAPH-TENANT-ID` | #1 テナント ID |
| `SEARCH-API-KEY` | #5 管理キー |
| `SEARCH-ENDPOINT` | #5 エンドポイント |
| `COSMOS-CONNECTION-STRING` | #6 接続文字列 |
| `STORAGE-CONNECTION-STRING` | #4 接続文字列 |

---

## シート3: コスト試算（PoC）

### 前提条件

| 項目 | 値 |
|------|-----|
| ユーザー数 | 10名 |
| SP 文書数 | 100件以上 |
| PoC 期間 | 数日〜2週間 |
| リージョン | Japan East |
| 通貨 | USD（参考: 1 USD ≒ 150 JPY） |
| 試算ツール | [Azure Pricing Calculator](https://azure.microsoft.com/ja-jp/pricing/calculator/) |

### 月額コスト内訳

| # | リソース | SKU | 課金種別 | 月額（USD） | 備考 |
|---|---------|-----|---------|------------|------|
| 1 | **AI Search** | S1 | 固定 | **$245.28** | 最大コスト。1 SU（1レプリカ×1パーティション） |
| 2 | **App Service** | B1 Linux | 固定 | **$12.41** | 常時起動の最小プラン |
| 3 | **Azure OpenAI (GPT-4o-mini)** | Standard | 従量 | **〜$1** | 入力$0.15/1M tokens, 出力$0.60/1M tokens。PoC利用では微少 |
| 4 | **Azure OpenAI (embedding)** | Standard | 従量 | **〜$1** | $0.13/1M tokens。100件インデックス構築+クエリ |
| 5 | **Document Intelligence** | S0 | 従量 | **〜$5** | Layout: $10/1,000ページ。100件×平均5ページ=500ページ |
| 6 | **Cosmos DB** | サーバーレス | 従量 | **〜$1** | $0.25/1M RU + $0.25/GB。PoC利用では微少 |
| 7 | **Functions** | 従量課金 | 従量 | **$0** | 無料枠内（月100万回実行 + 400,000 GB-s） |
| 8 | **Blob Storage** | Standard LRS | 従量 | **〜$0.01** | $0.0184/GB。100件で数十MB程度 |
| 9 | **Key Vault** | Standard | 従量 | **〜$0.01** | $0.03/10,000操作 |
| 10 | **Application Insights** | — | 従量 | **$0** | 無料枠 5GB/月内 |
| | | | **合計** | **約 $265/月** | |
| | | | **参考: 日本円** | **約 39,750円/月** | |

### PoC 期間中の想定コスト

| 期間 | 想定コスト |
|------|-----------|
| 3日 | 約 $26（AI Search の日割り $24 + 従量課金 $2） |
| 1週間 | 約 $62 |
| 2週間 | 約 $124 |
| 1ヶ月 | 約 $265 |

> AI Search S1 は時間課金（$0.336/時）。PoC 終了後にリソース削除で課金停止。
>
> 上記の金額は 2026年3月時点の [Azure Pricing Calculator](https://azure.microsoft.com/ja-jp/pricing/calculator/) に基づく。最新価格は Calculator で確認のこと。

---

## シート5: 作成スケジュール

### 作成順序（依存順）

| 順 | リソース | 依存 | 作成時間目安 |
|----|---------|------|------------|
| 1 | Resource Group | — | 1分 |
| 2 | Entra ID アプリ登録 | — | 10分（権限付与含む） |
| 3 | Azure OpenAI + モデルデプロイ | RG | 10分 |
| 4 | Document Intelligence | RG | 5分 |
| 5 | Storage Account + コンテナ | RG | 5分 |
| 6 | AI Search + 初期設定5項目 | #3, #4, #5 | 15分 |
| 7 | Cosmos DB + DB/コンテナ | RG | 5分 |
| 8 | Key Vault + シークレット9個 | 全リソース | 15分 |
| 9 | Application Insights | RG | 3分 |
| 10 | Azure Functions + 設定 | #5, #8, #9 | 10分 |
| 11 | App Service + 設定 | #8, #10 | 10分 |
| 12 | RBAC 設定（6件） | #5, #9, #10 | 15分 |
| | **合計** | | **約 1.5時間** |

### PoC 終了後の削除

PoC 終了後: リソースグループを削除。Entra ID アプリ登録を手動削除。

---

## 関連文書

| 文書 | 内容 |
|------|------|
| 要件定義書 | 前提条件・制約 |
| アーキテクチャ設計書 | コンポーネント構成・選定理由 |
| セキュリティ設計書 | RBAC・ネットワーク詳細 |
| 構築手順書 | 各リソースの作成手順（ポータル操作） |

---

以上
