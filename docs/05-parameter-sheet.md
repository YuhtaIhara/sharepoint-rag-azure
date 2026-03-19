# パラメータシート

## 変更履歴

| 版数 | 日付 | 変更者 | 変更内容 |
|------|------|--------|----------|
| 0.1 | 2026-03-15 | 構築担当者 | 初版作成。RG・Entra ID アプリは実績値、その他は設計値 |
| 0.2 | 2026-03-18 | 構築担当者 | リージョン変更反映（OpenAI→East US 2、App Service→East Asia）。Summary を実績値に更新。oai-sprag-poc-jpe 削除記録 |
| 0.3 | 2026-03-18 | 構築担当者 | デプロイ実績反映。RBAC 全件設定済。KV シークレット全件登録済。Functions/App Service ホスト名・アプリ設定を実績値に更新 |
| 0.4 | 2026-03-18 | 構築担当者 | スキルセット構成を実績値に更新（SplitSkill + AzureOpenAIEmbeddingSkill）。DI 未使用注記追加 |
| 0.5 | 2026-03-18 | 構築担当者 | DI Layout スキル統合。2インデクサー構成。Cognitive Services マルチサービスアカウント追加。Blob から Word テンポラリファイル削除 |
| 0.6 | 2026-03-18 | 構築担当者 | Terraform 管理注記追加。インデクサースケジュール追加 (PT1H)。SP 同期自動化設定追加 |

---

## Summary

| #   | シート名                  | リソース種別                | リソース名                  | 作成状況 | 作成日        | 作成者 | 備考      |
| --- | --------------------- | --------------------- | ---------------------- | ---- | ---------- | --- | ------- |
| 0   | Resource Group        | Resource Group        | `rg-sprag-poc-jpe`     | 完了  | 2026-03-14 | 担当者A | `data` 参照 (Terraform) |
| 1   | Entra ID App          | Entra ID アプリ登録        | `app-sprag-poc`        | 完了  | 2026-03-16 | 構築担当者 | `data` 参照 (Terraform) |
| 2   | Azure OpenAI          | Azure AI Foundry      | `oai-sprag-poc-eastus2` | Terraform 管理 | — | — | Terraform `azurerm_cognitive_account` + deployment x2 |
| 3   | Document Intelligence | Document Intelligence | `di-sprag-poc-jpe`     | Terraform 管理 | — | — | Terraform `azurerm_cognitive_account` (FormRecognizer) |
| 4   | Storage Account       | Storage Account       | `stspragpocjpe`        | Terraform 管理 | — | — | `terraform import` で管理下に |
| 5   | AI Search             | AI Search             | `srch-sprag-poc-jpe`   | Terraform 管理 | — | — | Terraform + `terraform_data` (search objects) |
| 6   | Cosmos DB             | Cosmos DB             | `cosmos-sprag-poc-jpe` | Terraform 管理 | — | — | Terraform `azurerm_cosmosdb_account` (serverless) |
| 7   | Key Vault             | Key Vault             | `kv-sprag-poc-jpe`     | Terraform 管理 | — | — | Terraform + シークレット 9件自動設定 |
| 8   | Application Insights  | Application Insights  | `appi-sprag-poc-jpe`   | Terraform 管理 | — | — | Terraform + Log Analytics workspace |
| 9   | Azure Functions       | Azure Functions       | `func-sprag-poc-jpe`   | Terraform 管理 | — | — | Terraform (基盤) + GitHub Actions (コードデプロイ) |
| 10  | App Service           | App Service           | `app-sprag-poc-ea`     | Terraform 管理 | — | — | Terraform (基盤) + GitHub Actions (コードデプロイ) |
| 11  | Functions 用 Storage   | Storage Account       | `stfuncspragpoc`       | Terraform 管理 | — | — | Terraform `azurerm_storage_account` |
| 12  | Cognitive Services    | Cognitive Services (マルチサービス) | `cog-sprag-poc-jpe`    | Terraform 管理 | — | — | Terraform `azurerm_cognitive_account` (CognitiveServices) |

---

## #0 Resource Group

### 基本情報

| 項目 | 値 |
|------|-----|
| リソース名 | `rg-sprag-poc-jpe` |
| サービス | Resource Group |
| サブスクリプション | Azure サブスクリプション 1 (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`) |
| リージョン | Japan East |
| 関連文書 | リソース設計書 #0 |

### パラメータ一覧

| # | カテゴリ | 設定項目 | 設定値 | 既定値 | 備考 |
|---|---------|---------|--------|--------|------|
| 1 | タグ | Environment | `poc` | — | |
| 2 | タグ | Project | `sp-rag` | — | |
| 3 | タグ | Owner | `project-owner` | — | |
| 4 | タグ | CreatedDate | `2026-03-14` | — | |
| 5 | タグ | DeleteAfter | `2026-03-31` | — | PoC 終了後削除期限 |

---

## #1 Entra ID アプリ登録

### 基本情報

| 項目 | 値 |
|------|-----|
| リソース名 | `app-sprag-poc` |
| サービス | Entra ID アプリ登録 |
| テナント | 自社テナント |
| 関連文書 | リソース設計書 #1 / セキュリティ設計書 §4.3 |

### パラメータ一覧

| # | カテゴリ | 設定項目 | 設定値 | 既定値 | 備考 |
|---|---------|---------|--------|--------|------|
| 1 | 基本 | 表示名 | `app-sprag-poc` | — | |
| 2 | 基本 | サポートされるアカウントの種類 | シングルテナント | シングルテナント | 自社のみ |
| 3 | 基本 | リダイレクト URI | `https://app-sprag-poc-jpe.azurewebsites.net/.auth/login/aad/callback` | — | App Service 作成後に設定 |
| 4 | API 権限 | Microsoft Graph - Sites.Read.All | アプリケーション | — | 管理者同意必要 |
| 5 | API 権限 | Microsoft Graph - Files.Read.All | アプリケーション | — | 管理者同意必要 |
| 6 | API 権限 | 管理者同意状態 | **未承認** | — |  |
| 7 | セキュリティ | クライアントシークレット有効期限 | 6ヶ月 | — | PoC 終了後に失効 |

### 取得値

> 機密情報を含む。Excel 化時はパスワード保護またはアクセス制限を適用すること。

| 項目 | 値 | 格納先 Key Vault シークレット |
|------|-----|---------------------------|
| アプリケーション (クライアント) ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` | `GRAPH-CLIENT-ID` |
| ディレクトリ (テナント) ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` | `GRAPH-TENANT-ID` |
| クライアントシークレット値 | `***REDACTED***` | `GRAPH-CLIENT-SECRET` |

---

## #2 Azure OpenAI

> **設計変更**: 当初 `oai-sprag-poc-jpe` (Japan East) で計画したが、gpt-4o-mini / text-embedding-3-large が Japan East 非対応のため、Azure AI Foundry として East US 2 に作成。旧リソース `oai-sprag-poc-jpe` は 2026-03-18 に削除済み。

### 基本情報

| 項目 | 値 |
|------|-----|
| リソース名 | `oai-sprag-poc-eastus2` |
| サービス | Azure AI Foundry (Azure OpenAI) |
| リソースグループ | `rg-sprag-poc-jpe` |
| リージョン | **East US 2**（設計時: Japan East） |
| SKU / プラン | S0 (Standard) |
| 関連文書 | リソース設計書 #2 |

### パラメータ一覧

| #   | カテゴリ   | 設定項目        | 設定値          | 既定値        | 備考                          |
| --- | ------ | ----------- | ------------ | ---------- | --------------------------- |
| 1   | ネットワーク | ネットワークアクセス  | すべてのネットワーク   | すべてのネットワーク | PoC |
| 2   | セキュリティ | マネージド ID    | システム割り当て     | 無効         | AI Search からの RBAC 用        |
| 3   | タグ     | Environment | `poc`        | —          |                             |
| 4   | タグ     | Project     | `sp-rag`     | —          |                             |
| 5   | タグ     | Owner       | `project-owner`      | —          |                             |
| 6   | タグ     | CreatedDate | `2026-03-16` | —          |                             |
| 7   | タグ     | DeleteAfter | `2026-03-31` | —          |                             |

### モデルデプロイ

| # | モデル | デプロイ名 | デプロイの種類 | TPM | バージョン | 備考 |
|---|--------|-----------|-------------|-----|-----------|------|
| 1 | gpt-4o-mini | `gpt-4o-mini` | Standard | 30K | 最新 | 回答生成・クエリ書き換え |
| 2 | text-embedding-3-large | `text-embedding-3-large` | Standard | 120K | 最新 | ベクトル生成（3072次元） |

### 取得値

| 項目 | 値 | 格納先 Key Vault シークレット |
|------|-----|---------------------------|
| エンドポイント | `https://oai-sprag-poc-eastus2.services.ai.azure.com/` | `AZURE-OPENAI-ENDPOINT` |
| API キー (KEY 1) | `***REDACTED***` | `AZURE-OPENAI-KEY` |

---

## #3 Document Intelligence

### 基本情報

| 項目 | 値 |
|------|-----|
| リソース名 | `di-sprag-poc-jpe` |
| サービス | Document Intelligence |
| リソースグループ | `rg-sprag-poc-jpe` |
| リージョン | Japan East |
| SKU / プラン | S0 |
| 関連文書 | リソース設計書 #3 |

### パラメータ一覧

| #   | カテゴリ   | 設定項目        | 設定値          | 既定値        | 備考  |
| --- | ------ | ----------- | ------------ | ---------- | --- |
| 1   | ネットワーク | ネットワークアクセス  | すべてのネットワーク   | すべてのネットワーク | PoC |
| 2   | タグ     | Environment | `poc`        | —          |     |
| 3   | タグ     | Project     | `sp-rag`     | —          |     |
| 4   | タグ     | Owner       | `project-owner`      | —          |     |
| 5   | タグ     | CreatedDate | `2026-03-16` | —          |     |
| 6   | タグ     | DeleteAfter | `2026-03-31` | —          |     |

### 取得値

| 項目 | 値 | 用途 |
|------|-----|------|
| エンドポイント | `https://di-sprag-poc-jpe.cognitiveservices.azure.com/` | AI Search スキルセットから参照 |
| API キー (KEY 1) | `***REDACTED***` | AI Search スキルセットから参照 |

> Document Intelligence のキーは Key Vault ではなく AI Search スキルセットの `cognitiveServices` プロパティに直接設定する。

---

## #4 Storage Account（文書格納用）

### 基本情報

| 項目 | 値 |
|------|-----|
| リソース名 | `stspragpocjpe` |
| サービス | Storage Account |
| リソースグループ | `rg-sprag-poc-jpe` |
| リージョン | Japan East |
| SKU / プラン | Standard LRS |
| 関連文書 | リソース設計書 #4 |

### パラメータ一覧

| #   | カテゴリ   | 設定項目             | 設定値          | 既定値        | 備考                   |
| --- | ------ | ---------------- | ------------ | ---------- | -------------------- |
| 1   | 基本     | パフォーマンス          | Standard     | Standard   |                      |
| 2   | 基本     | 冗長性              | LRS          | RA-GRS     | PoC は冗長性不要           |
| 3   | 基本     | アカウントの種類         | StorageV2    | StorageV2  |                      |
| 4   | セキュリティ | パブリックアクセス        | 無効           | 有効         | Blob のパブリックアクセスを無効化  |
| 5   | セキュリティ | ストレージアカウントキーアクセス | 有効           | 有効         | 接続文字列で Functions が利用 |
| 6   | セキュリティ | TLS 最小バージョン      | 1.2          | 1.2        |                      |
| 7   | セキュリティ | 安全な転送が必須         | 有効           | 有効         | HTTPS のみ             |
| 8   | データ保護  | BLOB の論理削除       | 有効（7日）       | 有効（7日）     |                      |
| 9   | データ保護  | コンテナーの論理削除       | 有効（7日）       | 有効（7日）     |                      |
| 10  | ネットワーク | ネットワークアクセス       | すべてのネットワーク   | すべてのネットワーク | PoC                  |
| 11  | タグ     | Environment      | `poc`        | —          |                      |
| 12  | タグ     | Project          | `sp-rag`     | —          |                      |
| 13  | タグ     | Owner            | `project-owner`      | —          |                      |
| 14  | タグ     | CreatedDate      | `2026-03-16` | —          |                      |
| 15  | タグ     | DeleteAfter      | `2026-03-31` | —          |                      |

### コンテナ

| #   | コンテナ名                  | アクセスレベル | 用途                       |
| --- | ---------------------- | ------- | ------------------------ |
| 1   | `sharepoint-documents` | プライベート  | Graph API で取得した SP 文書を格納 |

### 取得値

| 項目           | 値         | 格納先 Key Vault シークレット        |
| ------------ | --------- | --------------------------- |
| 接続文字列        | `***REDACTED***` | `STORAGE-CONNECTION-STRING` |
| Blob エンドポイント | `https://stspragpocjpe.blob.core.windows.net/` | （AI Search データソースで使用）       |

---

## #5 AI Search

### 基本情報

| 項目 | 値 |
|------|-----|
| リソース名 | `srch-sprag-poc-jpe` |
| サービス | AI Search |
| リソースグループ | `rg-sprag-poc-jpe` |
| リージョン | Japan East |
| SKU / プラン | **S1**（月額 $245.28） |
| 関連文書 | リソース設計書 #5 / アーキテクチャ設計書 付録A |

### パラメータ一覧

| # | カテゴリ | 設定項目 | 設定値 | 既定値 | 備考 |
|---|---------|---------|--------|--------|------|
| 1 | 基本 | レプリカ数 | 1 | 1 | |
| 2 | 基本 | パーティション数 | 1 | 1 | |
| 3 | 基本 | セマンティックランカー | Free | Free | |
| 4 | セキュリティ | マネージド ID | システム割り当て | 無効 | Blob / OpenAI への RBAC 用 |
| 5 | セキュリティ | API キーベース認証 | 有効 | 有効 | Functions から API キーで接続 |
| 6 | ネットワーク | ネットワークアクセス | すべてのネットワーク | すべてのネットワーク | PoC |
| 7 | タグ | Environment | `poc` | — | |
| 8 | タグ | Project | `sp-rag` | — | |
| 9 | タグ | Owner | `project-owner` | — | |
| 10 | タグ | CreatedDate | `2026-03-14` | — | |
| 11 | タグ | DeleteAfter | `2026-03-31` | — | |

### インデックス定義

インデックス名: `sprag-index`

| # | フィールド名 | 型 | 検索可能 | フィルター可能 | ソート可能 | ファセット | キー | 備考 |
|---|------------|---|---------|-------------|---------|---------|-----|------|
| 1 | chunk_id | Edm.String | — | — | — | — | Yes | チャンク一意 ID |
| 2 | parent_id | Edm.String | — | Yes | — | — | — | 元文書 ID |
| 3 | chunk | Edm.String | Yes | — | — | — | — | チャンクテキスト（検索対象） |
| 4 | title | Edm.String | Yes | Yes | — | — | — | 文書タイトル |
| 5 | text_vector | Collection(Edm.Single) | — | — | — | — | — | 埋め込みベクトル（3072次元） |
| 6 | category | Edm.String | — | Yes | — | Yes | — | フォルダカテゴリ |
| 7 | source_url | Edm.String | — | — | — | — | — | SP 上の元ファイル URL |
| 8 | allowed_groups | Collection(Edm.String) | — | Yes | — | — | — | ACL グループ ID |

### ベクトル検索構成

| 項目 | 値 |
|------|-----|
| アルゴリズム | HNSW |
| メトリック | cosine |
| 次元数 | 3072 |
| 対象フィールド | text_vector |

### セマンティック構成

| 項目 | 値 |
|------|-----|
| 構成名 | `sprag-semantic-config` |
| タイトルフィールド | title |
| コンテンツフィールド | chunk |

### データソース

| 項目 | 値 |
|------|-----|
| データソース名 | `sprag-datasource` |
| 種類 | Azure Blob Storage |
| 接続先 | `stspragpocjpe` / `sharepoint-documents` |
| 認証 | マネージド ID（Storage Blob Data Reader） |

### スキルセット

| 項目 | 値 |
|------|-----|
| スキルセット名 (DI) | `sprag-skillset` |
| スキル 1 | DocumentIntelligenceLayoutSkill（構造解析+チャンキング: text output, 2000文字、オーバーラップ200） |
| スキル 2 | AzureOpenAIEmbeddingSkill（text-embedding-3-large） |
| cognitiveServices | `cog-sprag-poc-jpe` のキーで接続（CognitiveServicesByKey） |
| スキルセット名 (FB) | `sprag-skillset-fallback` |
| FB スキル 1 | SplitSkill（テキスト分割: 2000文字、オーバーラップ200） |
| FB スキル 2 | AzureOpenAIEmbeddingSkill（text-embedding-3-large） |

### インデクサー

| 項目 | 値 |
|------|-----|
| インデクサー名 (DI) | `sprag-indexer` |
| 対象 | `.pdf, .docx, .xlsx, .pptx`（indexedFileNameExtensions） |
| スキルセット | `sprag-skillset` |
| allowSkillsetToReadFileData | `true` |
| インデクサー名 (FB) | `sprag-indexer-fallback` |
| 対象 | 上記以外（excludedFileNameExtensions で .pdf/.docx/.xlsx/.pptx を除外） |
| スキルセット | `sprag-skillset-fallback` |
| 共通 | スケジュール: **PT1H（毎時自動実行）**、データソース: `sprag-datasource`、ターゲット: `sprag-index` |

### 取得値

| 項目 | 値 | 格納先 Key Vault シークレット |
|------|-----|---------------------------|
| エンドポイント | `https://srch-sprag-poc-jpe.search.windows.net` | `SEARCH-ENDPOINT` |
| 管理キー (Primary) | `***REDACTED***` | `SEARCH-API-KEY` |

---

## #6 Cosmos DB

### 基本情報

| 項目 | 値 |
|------|-----|
| リソース名 | `cosmos-sprag-poc-jpe` |
| サービス | Azure Cosmos DB |
| リソースグループ | `rg-sprag-poc-jpe` |
| リージョン | Japan East |
| SKU / プラン | サーバーレス (NoSQL) |
| 関連文書 | リソース設計書 #6 |

### パラメータ一覧

| #   | カテゴリ   | 設定項目        | 設定値          | 既定値        | 備考             |
| --- | ------ | ----------- | ------------ | ---------- | -------------- |
| 1   | 基本     | API         | NoSQL        | —          | GPT-RAG 推奨     |
| 2   | 基本     | 容量モード       | サーバーレス       | —          | 低頻度アクセスで最安     |
| 3   | 基本     | Free レベル割引  | 適用しない        | —          | 他用途で使用済みの場合を想定 |
| 4   | バックアップ | バックアップポリシー  | 定期的          | 定期的        |                |
| 5   | ネットワーク | ネットワークアクセス  | すべてのネットワーク   | すべてのネットワーク | PoC            |
| 6   | タグ     | Environment | `poc`        | —          |                |
| 7   | タグ     | Project     | `sp-rag`     | —          |                |
| 8   | タグ     | Owner       | `project-owner`      | —          |                |
| 9   | タグ     | CreatedDate | `2026-03-16` | —          |                |
| 10  | タグ     | DeleteAfter | `2026-03-31` | —          |                |

### データベース / コンテナ

| #   | データベース名  | コンテナ名           | パーティションキー    | TTL | 備考   |
| --- | -------- | --------------- | ------------ | --- | ---- |
| 1   | `ChatDB` | `conversations` | `/sessionId` | なし  | 会話履歴 |

### 取得値

| 項目 | 値 | 格納先 Key Vault シークレット |
|------|-----|---------------------------|
| 接続文字列 (PRIMARY) | `***REDACTED***` | `COSMOS-CONNECTION-STRING` |

---

## #7 Key Vault

### 基本情報

| 項目        | 値                           |
| --------- | --------------------------- |
| リソース名     | `kv-sprag-poc-jpe`          |
| サービス      | Azure Key Vault             |
| リソースグループ  | `rg-sprag-poc-jpe`          |
| リージョン     | Japan East                  |
| SKU / プラン | Standard                    |
| 関連文書      | リソース設計書 #7 / セキュリティ設計書 §7.2 |

### パラメータ一覧

| #   | カテゴリ   | 設定項目        | 設定値          | 既定値        | 備考                 |
| --- | ------ | ----------- | ------------ | ---------- | ------------------ |
| 1   | セキュリティ | アクセス許可モデル   | RBAC         | コンテナーポリシー  | RBAC を選択           |
| 2   | セキュリティ | 論理的な削除      | 有効（90日）      | 有効（90日）    | 削除後 90 日間は名前が予約    |
| 3   | セキュリティ | 消去保護        | 無効           | 無効         | PoC 終了後のクリーンアップを考慮 |
| 4   | ネットワーク | ネットワークアクセス  | すべてのネットワーク   | すべてのネットワーク | PoC                |
| 5   | タグ     | Environment | `poc`        | —          |                    |
| 6   | タグ     | Project     | `sp-rag`     | —          |                    |
| 7   | タグ     | Owner       | `project-owner`      | —          |                    |
| 8   | タグ     | CreatedDate | `2026-03-16` | —          |                    |
| 9   | タグ     | DeleteAfter | `2026-03-31` | —          |                    |

### シークレット管理表

> 全リソース作成完了後に値を記入し、Key Vault に登録する。

| # | シークレット名 | ソース | 値 | 登録状況 |
|---|-------------|--------|-----|---------|
| 1 | `AZURE-OPENAI-KEY` | #2 API キー | `***REDACTED***` | 登録済（v2: East US 2 に更新） |
| 2 | `AZURE-OPENAI-ENDPOINT` | #2 エンドポイント | `https://oai-sprag-poc-eastus2.services.ai.azure.com/` | 登録済（v2: East US 2 に更新） |
| 3 | `GRAPH-CLIENT-ID` | #1 クライアント ID | `***REDACTED***` | 登録済 |
| 4 | `GRAPH-CLIENT-SECRET` | #1 シークレット値 | `***REDACTED***` | 登録済 |
| 5 | `GRAPH-TENANT-ID` | #1 テナント ID | `***REDACTED***` | 登録済 |
| 6 | `SEARCH-API-KEY` | #5 管理キー | `***REDACTED***` | 登録済 |
| 7 | `SEARCH-ENDPOINT` | #5 エンドポイント | `https://srch-sprag-poc-jpe.search.windows.net` | 登録済 |
| 8 | `COSMOS-CONNECTION-STRING` | #6 接続文字列 | `***REDACTED***` | 登録済 |
| 9 | `STORAGE-CONNECTION-STRING` | #4 接続文字列 | `***REDACTED***` | 登録済 |

---

## #8 Application Insights

### 基本情報

| 項目 | 値 |
|------|-----|
| リソース名 | `appi-sprag-poc-jpe` |
| サービス | Application Insights |
| リソースグループ | `rg-sprag-poc-jpe` |
| リージョン | Japan East |
| SKU / プラン | ワークスペースベース（従量課金） |
| 関連文書 | リソース設計書 #8 |

### パラメータ一覧

| #   | カテゴリ | 設定項目                  | 設定値          | 既定値        | 備考                |
| --- | ---- | --------------------- | ------------ | ---------- | ----------------- |
| 1   | 基本   | リソースモード               | ワークスペースベース   | ワークスペースベース |                   |
| 2   | 基本   | Log Analytics ワークスペース | 新規作成（自動）     | —          | 自動作成される           |
| 3   | 基本   | 日次上限                  | 推奨: 1GB      | なし（無制限）    | コスト暴走防止。無料枠 5GB/月 |
| 4   | タグ   | Environment           | `poc`        | —          |                   |
| 5   | タグ   | Project               | `sp-rag`     | —          |                   |
| 6   | タグ   | Owner                 | `project-owner`      | —          |                   |
| 7   | タグ   | CreatedDate           | `2026-03-16` | —          |                   |
| 8   | タグ   | DeleteAfter           | `2026-03-31` | —          |                   |

### 取得値

| 項目 | 値 | 用途 |
|------|-----|------|
| 接続文字列 | `***REDACTED***` | Functions / App Service のアプリ設定 |
| インストルメンテーションキー | `***REDACTED***` | （接続文字列に含まれる、参考用） |

---

## #9 Azure Functions

### 基本情報

| 項目 | 値 |
|------|-----|
| リソース名 | `func-sprag-poc-jpe` |
| サービス | Azure Functions |
| リソースグループ | `rg-sprag-poc-jpe` |
| リージョン | Japan East |
| SKU / プラン | 従量課金 (Consumption) |
| 関連文書 | リソース設計書 #9 |

### パラメータ一覧

| # | カテゴリ | 設定項目 | 設定値 | 既定値 | 備考 |
|---|---------|---------|--------|--------|------|
| 1 | 基本 | ランタイムスタック | Python | — | Semantic Kernel |
| 2 | 基本 | バージョン | 3.12 | — | |
| 3 | 基本 | OS | Linux | — | |
| 4 | 基本 | プラン種類 | 従量課金 (Consumption) | — | 無料枠：月100万回 + 400,000 GB-s |
| 5 | 基本 | ストレージアカウント | `stfuncspragpoc` (#11) | — | Functions ランタイム用 |
| 6 | 監視 | Application Insights | `appi-sprag-poc-jpe` (#8) | — | |
| 7 | セキュリティ | マネージド ID | システム割り当て | 無効 | Key Vault / Storage / OpenAI 用 |
| 8 | ネットワーク | パブリックアクセス | 有効 | 有効 | PoC |
| 9 | タグ | Environment | `poc` | — | |
| 10 | タグ | Project | `sp-rag` | — | |
| 11 | タグ | Owner | `project-owner` | — | |
| 12 | タグ | CreatedDate | `2026-03-14` | — | |
| 13 | タグ | DeleteAfter | `2026-03-31` | — | |

### アプリケーション設定

| # | 種別 | 設定名 | 値 | 備考 |
|---|------|--------|-----|------|
| 1 | KV 参照 | AZURE_OPENAI_ENDPOINT | `@Microsoft.KeyVault(VaultName=kv-sprag-poc-jpe;SecretName=AZURE-OPENAI-ENDPOINT)` | |
| 2 | KV 参照 | AZURE_OPENAI_API_KEY | `@Microsoft.KeyVault(VaultName=kv-sprag-poc-jpe;SecretName=AZURE-OPENAI-KEY)` | |
| 3 | KV 参照 | AZURE_SEARCH_ENDPOINT | `@Microsoft.KeyVault(VaultName=kv-sprag-poc-jpe;SecretName=SEARCH-ENDPOINT)` | |
| 4 | KV 参照 | AZURE_SEARCH_API_KEY | `@Microsoft.KeyVault(VaultName=kv-sprag-poc-jpe;SecretName=SEARCH-API-KEY)` | |
| 5 | KV 参照 | COSMOS_CONNECTION_STRING | `@Microsoft.KeyVault(VaultName=kv-sprag-poc-jpe;SecretName=COSMOS-CONNECTION-STRING)` | |
| 6 | KV 参照 | STORAGE_CONNECTION_STRING | `@Microsoft.KeyVault(VaultName=kv-sprag-poc-jpe;SecretName=STORAGE-CONNECTION-STRING)` | |
| 7 | KV 参照 | GRAPH_CLIENT_ID | `@Microsoft.KeyVault(VaultName=kv-sprag-poc-jpe;SecretName=GRAPH-CLIENT-ID)` | |
| 8 | KV 参照 | GRAPH_CLIENT_SECRET | `@Microsoft.KeyVault(VaultName=kv-sprag-poc-jpe;SecretName=GRAPH-CLIENT-SECRET)` | |
| 9 | KV 参照 | GRAPH_TENANT_ID | `@Microsoft.KeyVault(VaultName=kv-sprag-poc-jpe;SecretName=GRAPH-TENANT-ID)` | |
| 10 | 設定値 | AZURE_OPENAI_CHAT_DEPLOYMENT | `gpt-4o-mini` | |
| 11 | 設定値 | AZURE_OPENAI_EMBEDDING_DEPLOYMENT | `text-embedding-3-large` | |
| 12 | 設定値 | AZURE_SEARCH_INDEX_NAME | `sprag-index` | |
| 13 | 設定値 | COSMOS_DB_DATABASE | `ChatDB` | |
| 14 | 設定値 | COSMOS_DB_CONTAINER | `conversations` | |
| 15 | 設定値 | BLOB_CONTAINER_NAME | `sharepoint-documents` | |
| 16 | 自動 | APPLICATIONINSIGHTS_CONNECTION_STRING | **#8 作成後記入** | App Insights 連携時に自動設定 |

### 取得値

| 項目 | 値 | 用途 |
|------|-----|------|
| 関数アプリ URL | `https://func-sprag-poc-jpe-xxxxxxxxxx.japaneast-01.azurewebsites.net` | App Service からのバックエンド API 呼び出し。※新しい Azure 命名形式: `{name}-{hash}.{region}-01.azurewebsites.net` |
| デフォルトキー | `***REDACTED***` | App Service → Functions 認証（必要に応じ） |

---

## #10 App Service

> **設計変更**: Japan East で B1 クォータ不足 (Basic VMs: 0) のため East Asia に変更。PoC 用途のため影響なし。

### 基本情報

| 項目 | 値 |
|------|-----|
| リソース名 | `app-sprag-poc-jpe` |
| サービス | App Service |
| リソースグループ | `rg-sprag-poc-jpe` |
| リージョン | **East Asia**（設計時: Japan East） |
| SKU / プラン | **B1** Linux（月額 $14.60） |
| 関連文書 | リソース設計書 #10 |

### パラメータ一覧

| # | カテゴリ | 設定項目 | 設定値 | 既定値 | 備考 |
|---|---------|---------|--------|--------|------|
| 1 | 基本 | ランタイムスタック | Node.js 22 LTS | — | チャット UI |
| 2 | 基本 | OS | Linux | — | |
| 3 | 基本 | App Service プラン | 新規作成 | — | B1 |
| 4 | セキュリティ | マネージド ID | システム割り当て | 無効 | Key Vault 参照用 |
| 5 | 認証 | Entra ID 認証 | 有効 | 無効 | SSO（作成後に構成） |
| 6 | 認証 | 認証プロバイダ | Microsoft（Entra ID） | — | `app-sprag-poc` アプリを使用 |
| 7 | ネットワーク | パブリックアクセス | 有効 | 有効 | PoC |
| 8 | タグ | Environment | `poc` | — | |
| 9 | タグ | Project | `sp-rag` | — | |
| 10 | タグ | Owner | `project-owner` | — | |
| 11 | タグ | CreatedDate | `2026-03-14` | — | |
| 12 | タグ | DeleteAfter | `2026-03-31` | — | |

### アプリケーション設定

| # | 種別 | 設定名 | 値 | 備考 |
|---|------|--------|-----|------|
| 1 | 設定値 | BACKEND_API_URL | `https://func-sprag-poc-jpe-xxxxxxxxxx.japaneast-01.azurewebsites.net` | Functions のエンドポイント URL |
| 2 | 設定値 | FUNCTIONS_KEY | `***REDACTED***` | Functions のデフォルトキー（API 認証用） |
| 3 | 自動 | APPLICATIONINSIGHTS_CONNECTION_STRING | 自動設定済 | App Insights 連携時に自動設定 |

---

## #11 Storage Account（Functions 用）

### 基本情報

| 項目 | 値 |
|------|-----|
| リソース名 | `stfuncspragpoc` |
| サービス | Storage Account |
| リソースグループ | `rg-sprag-poc-jpe` |
| リージョン | Japan East |
| SKU / プラン | Standard LRS |
| 関連文書 | リソース設計書 #11 |

### パラメータ一覧

| # | カテゴリ | 設定項目 | 設定値 | 既定値 | 備考 |
|---|---------|---------|--------|--------|------|
| 1 | 基本 | パフォーマンス | Standard | Standard | |
| 2 | 基本 | 冗長性 | LRS | RA-GRS | |
| 3 | セキュリティ | TLS 最小バージョン | 1.2 | 1.2 | |
| 4 | セキュリティ | 安全な転送が必須 | 有効 | 有効 | |
| 5 | タグ | Environment | `poc` | — | |
| 6 | タグ | Project | `sp-rag` | — | |
| 7 | タグ | Owner | `project-owner` | — | |
| 8 | タグ | CreatedDate | `2026-03-14` | — | |
| 9 | タグ | DeleteAfter | `2026-03-31` | — | |

> Functions 作成時に同時作成されるため、個別作成は不要な場合がある。Functions 作成画面で新規ストレージを選択した場合、命名規則に注意。

---

## #12 Cognitive Services（マルチサービス）

### 基本情報

| 項目 | 値 |
|------|-----|
| リソース名 | `cog-sprag-poc-jpe` |
| サービス | Cognitive Services（マルチサービスアカウント） |
| リソースグループ | `rg-sprag-poc-jpe` |
| リージョン | Japan East |
| SKU / プラン | S0 |
| 用途 | DI Layout スキルの課金リソース。20doc/日超の処理に必須 |

> **注**: DI 単体リソース (`di-sprag-poc-jpe`) のキーでは `cognitiveServices` に接続不可（`InvalidApiType` エラー）。マルチサービスアカウントが必要。

### 取得値

| 項目 | 値 | 用途 |
|------|-----|------|
| API キー (KEY 1) | `***REDACTED***` | AI Search スキルセットの `cognitiveServices` プロパティに設定 |

---

## RBAC 設定一覧

リソース作成完了後、以下の RBAC ロール割り当てを実施する。

| # | 付与先 | 対象リソース | ロール | 設定状況 |
|---|--------|------------|--------|---------|
| 1 | AI Search MI (#5) | Storage (#4) | Storage Blob Data Reader | **設定済** |
| 2 | AI Search MI (#5) | Azure OpenAI (#2) | Cognitive Services OpenAI User | **設定済** |
| 3 | Functions MI (#9) | Key Vault (#7) | Key Vault Secrets User | **設定済** |
| 4 | Functions MI (#9) | Storage (#4) | Storage Blob Data Contributor | **設定済** |
| 5 | Functions MI (#9) | Azure OpenAI (#2) | Cognitive Services OpenAI User | **設定済** |
| 6 | App Service MI (#10) | Key Vault (#7) | Key Vault Secrets User | **設定済** |
| 7 | 自分自身 | AI Search (#5) | Search Service Contributor | **設定済** |
| 8 | 自分自身 | AI Search (#5) | Search Index Data Contributor | **設定済** |
| 9 | 自分自身 | AI Search (#5) | Search Index Data Reader | **設定済** |
| 10 | 自分自身 | Key Vault (#7) | Key Vault Secrets Officer | **設定済** |

---

## 関連文書

| 文書 | 内容 |
|------|------|
| 要件定義書 | 前提条件・制約 |
| アーキテクチャ設計書 | コンポーネント構成・インデックス設計 |
| リソース設計書 | SKU・命名・コスト・作成順 |
| セキュリティ設計書 | 認証・認可・ネットワーク・脅威モデル |
| 構築手順書 | 各リソースの作成手順（ポータル操作） |

---

以上
