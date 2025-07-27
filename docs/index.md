# ドキュメント一覧

AWS ECS Blue/Greenデプロイメントサンプルプロジェクトのドキュメント集です。

## 📋 目的別ガイド

### 🚀 はじめに
- **[クイックスタート](quick-start.md)** - 5ステップで簡単構築（初心者向け）
- **[デプロイメントガイド](deployment-guide.md)** - 環境構築の完全手順（詳細版）

### 🏗️ アーキテクチャ理解
- **[システムアーキテクチャ](architecture.md)** - 構成図とネットワーク設計
- **[CloudFormationガイド](cloudformation-guide.md)** - テンプレート詳細とトラブルシューティング

### 🔄 デプロイメント
- **[Blue/Greenデプロイ](blue-green-deploy.md)** - CodeDeployを使用したデプロイ手順
- **[ECS構築ガイド](ecs-setup.md)** - ECS固有の設定とベストプラクティス

### 🔐 セキュリティ・認証
- **[OIDC設定ガイド](oidc-setup.md)** - GitHub ActionsとAWSの連携設定

## 📚 学習パス

### 初心者向け
1. [クイックスタート](quick-start.md) - まずは簡単構築
2. [システムアーキテクチャ](architecture.md) - 全体像を理解
3. [Blue/Greenデプロイ](blue-green-deploy.md) - デプロイを実行

### 運用担当者向け
1. [CloudFormationガイド](cloudformation-guide.md) - インフラ詳細を理解
2. [ECS構築ガイド](ecs-setup.md) - ECS運用のベストプラクティス
3. [OIDC設定ガイド](oidc-setup.md) - CI/CD環境構築

## 🔍 クイックリファレンス

| 知りたいこと | 参照ドキュメント |
|-------------|-----------------|
| 簡単に構築したい | [quick-start.md](quick-start.md) |
| システム全体の構成 | [architecture.md](architecture.md) |
| 詳細な環境構築手順 | [deployment-guide.md](deployment-guide.md) |
| CloudFormationテンプレート詳細 | [cloudformation-guide.md](cloudformation-guide.md) |
| Blue/Greenデプロイ方法 | [blue-green-deploy.md](blue-green-deploy.md) |
| ECS設定とトラブルシューティング | [ecs-setup.md](ecs-setup.md) |
| GitHub Actions設定 | [oidc-setup.md](oidc-setup.md) |

## 💡 よくある質問

**Q: 初めて構築する場合、どこから始めればいい？**  
A: [クイックスタート](quick-start.md)から始めてください。詳細な手順は[デプロイメントガイド](deployment-guide.md)を参照。

**Q: Blue/Greenデプロイがうまくいかない**  
A: [Blue/Greenデプロイ](blue-green-deploy.md)のトラブルシューティングセクションを確認してください。

**Q: コストを最適化したい**  
A: [システムアーキテクチャ](architecture.md)のコスト最適化セクションを参照してください。

**Q: CloudFormationでエラーが発生する**  
A: [CloudFormationガイド](cloudformation-guide.md)のトラブルシューティングセクションを確認してください。

---

📝 **更新情報**: このドキュメントは定期的に更新されます。最新情報は各ドキュメントを直接確認してください。