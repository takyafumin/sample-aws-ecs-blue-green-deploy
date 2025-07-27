# AWS ECS Blue/Green デプロイメントサンプル

AWS ECS Fargateを使用したコンテナ実行環境で、CodeDeployによるBlue/Greenデプロイメントを実装するサンプルプロジェクトです。

## 特徴

- **マルチAZ構成**: 高可用性を実現するVPC設計
- **Blue/Greenデプロイ**: CodeDeployによる無停止デプロイメント
- **CI/CD対応**: GitHub ActionsとOIDC認証
- **Infrastructure as Code**: CloudFormationによる環境管理
- **コスト最適化**: Fargateによる従量課金とリソース最適化

## アーキテクチャ概要

```mermaid
graph LR
    Internet([Internet]) --> ALB[Application Load Balancer]
    ALB --> CodeDeploy[CodeDeploy<br/>Traffic Control]
    CodeDeploy --> Blue[Blue Environment<br/>ECS Fargate]
    CodeDeploy --> Green[Green Environment<br/>ECS Fargate]
    Blue -.-> ECR[ECR Repository]
    Green -.-> ECR
    
    classDef blueEnv fill:#e8f5e8
    classDef greenEnv fill:#fff3e0
    classDef codeDeploy fill:#ffebee
    
    class Blue blueEnv
    class Green greenEnv
    class CodeDeploy codeDeploy
```

- **VPC**: 10.0.0.0/16 (マルチAZ構成)
- **ECS Fargate**: CPU 256, Memory 512MB × 2タスク
- **CodeDeploy**: Blue/Green無停止デプロイメント

## クイックスタート

**[クイックスタートガイド](docs/quick-start.md)** で5ステップの簡単構築手順を確認できます。

## ドキュメント

詳細な情報は **[docs/](docs/)** フォルダを参照してください。

👉 **[ドキュメント一覧](docs/index.md)** から目的に応じたガイドを選択できます。

## プロジェクト構成

```
├── aws/cloudformation/     # CloudFormationテンプレート
├── docs/                   # 詳細ドキュメント
├── scripts/               # デプロイスクリプト
├── .github/workflows/     # GitHub Actions
├── Dockerfile             # アプリケーションイメージ
└── appspec.yaml          # CodeDeploy設定
```
