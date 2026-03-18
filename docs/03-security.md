# セキュリティ設計書

## 変更履歴

| 版数 | 日付 | 変更者 | 変更内容 |
|------|------|--------|----------|
| 0.1 | 2026-03-14 | 構築担当者 | 初版ドラフト作成 |
| 0.2 | 2026-03-14 | 構築担当者 | DFD・STRIDE脅威モデル・Shared Responsibility・インシデント対応を追加（ベストプラクティス調査に基づく構成改善） |
| 0.3 | 2026-03-15 | 構築担当者 | プロセスノート削除、監査ログに保持期間追加、機能要件完了条件を検証可能に改善 |
| 0.4 | 2026-03-15 | 構築担当者 | ACL 制御を Phase 2 から Phase 1 に統合。フェーズ分け廃止 |
| 0.5 | 2026-03-18 | 構築担当者 | ACL 実装を実装実績に基づき更新。citation 抑制の説明を追加 |

---

## 1. 適用範囲と前提

### 1.1 適用範囲

本書は SharePoint RAG チャットボット PoC のセキュリティ設計を定義する。

- 対象: Azure 上の全コンポーネント（リソース設計書記載の12リソース）
- PoC 構成（10名）の設計を記述

### 1.2 準拠規格・方針

Azure Security Benchmark を参考に構成。PoC のため外部認証は不要。

---

## 2. データフロー図と Trust Boundary

```
                    ┌─ TB1: Internet ─────────────────────────┐
                    │                                          │
  [ユーザー] ──TLS──→ [App Service (チャット UI)]                │
                    │         │                                │
                    └─────────┼────────────────────────────────┘
                              │ TB2: Frontend → Backend
                    ┌─────────┼────────────────────────────────┐
                    │         ▼                                │
                    │  [Azure Functions (オーケストレーション)]     │
                    │    │         │         │         │       │
                    │    │TB4      │TB5      │TB6      │TB3    │
                    │    ▼         ▼         ▼         ▼       │
                    │ [AI Search] [OpenAI] [Cosmos DB] [Graph]  │
                    │    │                              │       │
                    │    │TB7                            │       │
                    │    ▼                              ▼       │
                    │ [Blob Storage]            [SharePoint]    │
                    │                                          │
                    │  [Key Vault] ← 全サービスから参照             │
                    │  [App Insights] ← 全サービスからログ送信       │
                    └─ TB8: Azure サブスクリプション ────────────────┘
```

### Trust Boundary 定義

| ID | 境界 | 説明 |
|----|------|------|
| TB1 | Internet → App Service | ユーザーアクセスの入口。認証が必須 |
| TB2 | App Service → Functions | フロント→バックエンド。内部通信 |
| TB3 | Functions → Graph API | Azure → Microsoft 365。API 権限制御 |
| TB4 | Functions → AI Search | バックエンド → 検索エンジン |
| TB5 | Functions → OpenAI | バックエンド → LLM |
| TB6 | Functions → Cosmos DB | バックエンド → データストア |
| TB7 | AI Search → Blob Storage | 検索 → 文書ストレージ |
| TB8 | Azure サブスクリプション境界 | 外部との全体境界 |

---

## 3. STRIDE 脅威モデル

標準的な脅威（なりすまし、改ざん、情報漏洩等）は Entra ID SSO、TLS、Key Vault、ACL フィルタで緩和。PoC のため正式なペネトレーションテストは実施しない。

---

## 4. 認証

### 4.1 ユーザー認証

| 項目 | PoC | 100-300名時 |
|------|-----|-------------|
| 方式 | Entra ID SSO（OAuth 2.0） | 同左 + 条件付きアクセス |
| 適用箇所 | App Service 認証 | 同左 |
| MFA | なし | 必須 |

> 対応脅威: T-01（Spoofing）

### 4.2 サービス間認証

| 経路 | 方式（PoC） | 100-300名時 |
|------|------------|-------------|
| Functions → Graph API | クライアントシークレット（Entra ID アプリ登録） | 証明書認証 |
| Functions → OpenAI | API キー（Key Vault 参照） | マネージド ID |
| Functions → Cosmos DB | 接続文字列（Key Vault 参照） | マネージド ID |
| Functions → Blob | マネージド ID（RBAC） | 同左 |
| AI Search → Blob / OpenAI | マネージド ID（RBAC） | 同左 |
| Functions / App Service → Key Vault | マネージド ID（RBAC） | 同左 |

> 対応脅威: T-04, T-09

### 4.3 Entra ID アプリ登録

| 設定 | 値 | 備考 |
|------|-----|------|
| テナント種別 | シングルテナント | 自社のみ |
| API 権限 | Sites.Read.All, Files.Read.All（アプリケーション） | 管理者同意が必要 |
| シークレット有効期限 | 6ヶ月 | PoC 終了後に失効 |
| 100-300名時 | Sites.Selected + 証明書認証 | 対象サイト限定（最小権限） |

> 対応脅威: T-03

---

## 5. 認可（ACL）

### 5.1 認可モデル

| 項目 | 設計 |
|------|------|
| 認可 | SP 権限連動 ACL |
| フィルタ | OData セキュリティフィルタ |
| 粒度 | フォルダ単位 |

> 対応脅威: T-06

### 5.2 ACL 実装

**インジェスション時**:
1. `sp_to_blob.py` が Graph API でフォルダの権限（permissions エンドポイント）を取得
2. 明示的権限がある場合: 閲覧可能ユーザーの UPN（メールアドレス）リストを JSON 配列として Blob メタデータに格納
3. 継承権限（明示的権限なし）の場合: `["*"]` を格納（全員アクセス可を意味する）
4. `update_index_metadata.py` が Blob メタデータを読み取り、インデックスの `allowed_groups` フィールドに merge 更新

**クエリ時**:
1. App Service（server.js）が `X-MS-CLIENT-PRINCIPAL-NAME` ヘッダからユーザーのメールアドレスを取得
2. メールアドレスを `user_groups` として Azure Functions に渡す
3. `search.py` が OData フィルタを構築し、ワイルドカード `*` にも対応:

```
$filter=(allowed_groups/any(g: search.in(g, 'user@example.com')) or allowed_groups/any(g: g eq '*'))
```

**citation 抑制**: LLM が「該当する情報が見つかりませんでした」と回答した場合、ファイル名漏洩防止のため citation（根拠リンク）を空にして返す。

**権限同期**: PoC では手動実行（sp_to_blob.py → インデクサー → update_index_metadata.py）。スケール時は 15-30分間隔の自動化を検討。

### 5.3 データ分類と権限マッピング

| SP フォルダ | 機密レベル | ACL 設定 |
|---|---|---|
| 01_経営 | 機密 | 経営層グループ限定 |
| 02_人事労務 | 社内 | 全社員 |
| 03_営業 | 部署限定 | 営業部グループ限定 |

---

## 6. ネットワーク

| 項目 | PoC |
|------|-----|
| エンドポイント | パブリック（全サービス） |
| VNet | なし |
| WAF | なし |
| NSG | なし |

> PoC ではパブリックエンドポイントを使用。期間限定かつ機密データの実害が限定的なため許容。

---

## 7. データ保護

### 7.1 暗号化

| 項目 | 方式 |
|------|------|
| 保存時暗号化 | Azure 標準 SSE（全サービスで自動有効、AES-256） |
| 転送時暗号化 | TLS 1.2 以上 |
| Blob Storage | SSE + 論理削除有効 |
| Cosmos DB | SSE（自動） |
| AI Search | SSE（自動） |

> 対応脅威: T-05, T-10

### 7.2 シークレット管理

シークレット一覧および RBAC 設定の詳細はリソース設計書を参照。

セキュリティ方針:
- 全シークレットは Key Vault に一元化し、環境変数への直書きを禁止
- Key Vault へのアクセスは RBAC モデル（アクセスポリシーではなく RBAC）
- アプリケーションには読み取り専用ロール（Secrets User）のみ付与

> 対応脅威: T-04, T-08

---

## 8. 監査ログ

| ログ種別 | ソース | 内容 | 保持期間（PoC） |
|---|---|---|---|
| アプリケーションログ | Application Insights | クエリ内容・応答時間・エラー | 90日（既定） |
| Azure Activity Log | Azure プラットフォーム | リソース操作（作成・変更・削除） | 90日（既定） |
| Entra ID サインインログ | Entra ID | ユーザー認証イベント | 30日（Free） |
| Key Vault 監査ログ | Key Vault | シークレットアクセス記録 | 90日（既定） |

> 対応脅威: T-11（否認防止）

---

## 9. インシデント対応

PoC のため正式なインシデント対応プロセスは策定しない。障害時はリソース再作成で対応する。

---

## 10. 関連文書

| 文書 | 内容 |
|------|------|
| 要件定義書 | セキュリティ要件（NF-S01〜S05） |
| アーキテクチャ設計書 | 認証経路・コンポーネント構成 |
| リソース設計書 | RBAC 設定・Key Vault シークレット一覧 |
| 構築手順書 | Entra ID・Key Vault の設定手順 |

---

以上
