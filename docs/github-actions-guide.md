# GitHub Actions デプロイガイド

## トリガー設定

### 実行条件

| トリガー | 条件 | 実行タイミング | 用途 |
|---------|------|--------------|------|
| **タグプッシュ** | `v*` パターン | `git push origin v1.0.0` | 本番リリース |
| **手動実行** | `workflow_dispatch` | Actions画面から手動 | テスト・緊急デプロイ |

### 実行されない条件

| 操作 | 理由 | 代替手段 |
|------|------|----------|
| **ブランチプッシュ** | 意図しないデプロイ防止 | 手動実行またはタグプッシュ |
| **Pull Request** | レビュー段階での実行不要 | マージ後にタグプッシュ |

## デプロイ手順

### 1. タグプッシュでの自動デプロイ

```bash
# 1. バージョンタグ作成
git tag v1.0.0

# 2. タグプッシュ（自動実行）
git push origin v1.0.0

# 3. GitHub Actionsで自動実行確認
# GitHub > Actions > "Blue/Green Deploy"
```

### 2. 手動実行でのデプロイ

```bash
# GitHub Web UI で実行
# 1. GitHub > Actions
# 2. "Blue/Green Deploy" を選択
# 3. "Run workflow" をクリック
# 4. バージョンを入力（例: manual-v1.0.0）
# 5. "Run workflow" で実行
```

## Environment設定

### Production Environment

| 設定項目 | 値 | 説明 |
|---------|---|------|
| **Environment名** | `production` | 本番環境識別 |
| **Protection rules** | 無効 | サンプルプロジェクトのため |
| **Environment secrets** | `AWS_ROLE_ARN` | OIDC認証用IAMロール |

### Secrets設定

```bash
# GitHub リポジトリで設定
# Settings > Environments > production > Environment secrets
# Name: AWS_ROLE_ARN
# Value: arn:aws:iam::ACCOUNT_ID:role/ecs-bg-deploy-github-actions-role
```

## トラブルシューティング

### よくあるエラー

| エラー | 原因 | 対処法 |
|-------|------|--------|
| **Credentials could not be loaded** | AWS_ROLE_ARN未設定 | Environment secretsを確認 |
| **Permission denied** | IAMロール権限不足 | CloudFormationスタック確認 |
| **Workflow not found** | ワークフローファイル未プッシュ | mainブランチにマージ |

### デバッグ手順

```bash
# 1. ワークフロー実行ログ確認
# GitHub > Actions > 失敗したワークフロー > ログ確認

# 2. AWS認証確認
# Configure AWS credentials ステップのログ確認

# 3. IAMロール確認
aws iam get-role --role-name ecs-bg-deploy-github-actions-role
```

## セキュリティ考慮事項

### OIDC認証

| 項目 | 設定 | セキュリティ効果 |
|------|------|-----------------|
| **信頼関係** | 特定リポジトリのみ | 他リポジトリからのアクセス拒否 |
| **権限スコープ** | 最小権限 | 必要最小限のAWS権限のみ |
| **一時認証** | STS AssumeRole | 長期認証情報不要 |

### 推奨設定

```yaml
# 最小権限設定例
permissions:
  id-token: write    # OIDC認証用
  contents: read     # リポジトリ読み取り用
```