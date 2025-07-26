# GitHub OIDC設定ガイド

## 概要
GitHub ActionsからAWSリソースにアクセスするためのOIDC（OpenID Connect）認証設定について説明します。

## 必要なリソース

### 1. OIDC Identity Provider
- **リソースタイプ**: `AWS::IAM::OidcProvider`
- **URL**: `https://token.actions.githubusercontent.com`
- **Client ID**: `sts.amazonaws.com`
- **Thumbprint**: `6938fd4d98bab03faadb97b34396831e3780aea1`

> **重要**: Thumbprintは時間の経過とともに変更される可能性があります。最新の値は[GitHubドキュメント](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)または[AWSドキュメント](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc_verify-thumbprint.html)で確認してください。

### 2. IAM Role
- **リソースタイプ**: `AWS::IAM::Role`
- **Trust Policy**: GitHub ActionsからのAssumeRoleを許可（全ブランチ対応）
- **Permissions**: ECR、ECS、CodeDeployへのアクセス権限
- **PassRole制限**: プロジェクト関連ロールのみに制限
- **Branch Pattern**: `repo:${GitHubOrg}/${GitHubRepo}:*` （全ブランチ・PRからのデプロイ可能）

## CloudFormationテンプレート
[aws/cloudformation/github-oidc.yaml](../aws/cloudformation/github-oidc.yaml)

## GitHub Actions設定
[.github/workflows/deploy.yml](../.github/workflows/deploy.yml)

## 参考ドキュメント
- [AWS CloudFormation - AWS::IAM::OidcProvider](https://docs.aws.amazon.com/ja_jp/AWSCloudFormation/latest/TemplateReference/aws-resource-iam-oidcprovider.html)
- [GitHub Actions - Configuring OpenID Connect in Amazon Web Services](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS - Creating OpenID Connect (OIDC) identity providers](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)

## トラブルシューティング

### OIDCプロバイダーが既に存在するエラー
```
Provider with url https://token.actions.githubusercontent.com already exists
```

**解決方法**: 既存のプロバイダーを使用するため、CloudFormationテンプレートからOIDCプロバイダーリソースを削除し、既存のARNを参照する。

### Thumbprintの確認方法
現在のThumbprintを確認するコマンド:
```bash
echo | openssl s_client -servername token.actions.githubusercontent.com -connect token.actions.githubusercontent.com:443 2>/dev/null | openssl x509 -fingerprint -noout -sha1 | cut -d= -f2 | tr -d :
```

### 権限不足エラー
IAMロールに必要な権限が不足している場合は、[github-oidc.yaml](../aws/cloudformation/github-oidc.yaml)のPoliciesセクションを確認してください。