# CloudFormationテンプレート詳細ガイド

## 概要
このプロジェクトでは、AWS環境を段階的に構築するために複数のCloudFormationテンプレートを使用しています。

## テンプレート一覧

### 1. network.yaml - ネットワーク基盤
**目的**: VPC、サブネット、ルーティングの構築

#### 主要リソース
| リソース | タイプ | 説明 |
|----------|--------|------|
| VPC | AWS::EC2::VPC | メインネットワーク (10.0.0.0/16) |
| PublicSubnet1/2 | AWS::EC2::Subnet | ALB配置用 (10.0.1.0/24, 10.0.2.0/24) |
| PrivateSubnet1/2 | AWS::EC2::Subnet | ECS配置用 (10.0.11.0/24, 10.0.12.0/24) |
| InternetGateway | AWS::EC2::InternetGateway | インターネット接続 |
| NatGateway1 | AWS::EC2::NatGateway | プライベートサブネットのアウトバウンド |
| RouteTable | AWS::EC2::RouteTable | ルーティング制御 |

#### パラメータ
- `ProjectName`: プロジェクト名（デフォルト: ecs-bg-deploy）

#### 出力値
- `VPC`: VPC ID
- `PublicSubnets`: パブリックサブネットIDのカンマ区切り
- `PrivateSubnets`: プライベートサブネットIDのカンマ区切り

#### 依存関係
- なし（最初に作成）

---

### 2. ecr.yaml - コンテナレジストリ
**目的**: Dockerイメージ保存用ECRリポジトリの作成

#### 主要リソース
| リソース | タイプ | 説明 |
|----------|--------|------|
| ECRRepository | AWS::ECR::Repository | コンテナイメージ保存 |

#### パラメータ
- `ProjectName`: プロジェクト名（デフォルト: ecs-bg-deploy）

#### 出力値
- `ECRRepository`: ECRリポジトリURI

#### 依存関係
- なし

---

### 3. github-oidc.yaml - CI/CD認証
**目的**: GitHub ActionsからAWSリソースへのアクセス権限設定

#### 主要リソース
| リソース | タイプ | 説明 |
|----------|--------|------|
| GitHubActionsRole | AWS::IAM::Role | GitHub Actions実行用IAMロール |

#### パラメータ
- `GitHubOrg`: GitHubユーザー名/組織名
- `GitHubRepo`: リポジトリ名
- `ProjectName`: プロジェクト名（デフォルト: ecs-bg-deploy）

#### 権限設定
```json
{
  "ECR": ["GetAuthorizationToken", "BatchCheckLayerAvailability", "PutImage"],
  "ECS": ["DescribeTaskDefinition", "RegisterTaskDefinition"],
  "CodeDeploy": ["CreateDeployment", "GetApplication", "GetDeployment"],
  "IAM": ["PassRole"]
}
```

#### 出力値
- `GitHubActionsRoleArn`: IAMロールARN

#### 依存関係
- GitHub OIDCプロバイダーが事前作成済みであること

---

### 4. ecs-simple.yaml - シンプルECS構成
**目的**: 基本的なECSサービスの構築（Blue/Green未対応）

#### 主要リソース
| リソース | タイプ | 説明 |
|----------|--------|------|
| ECSCluster | AWS::ECS::Cluster | Fargateクラスター |
| TaskDefinition | AWS::ECS::TaskDefinition | コンテナ定義 |
| ECSService | AWS::ECS::Service | サービス定義（2タスク） |
| ApplicationLoadBalancer | AWS::ElasticLoadBalancingV2::LoadBalancer | ロードバランサー |
| TargetGroup | AWS::ElasticLoadBalancingV2::TargetGroup | ターゲットグループ |
| ALBListener | AWS::ElasticLoadBalancingV2::Listener | リスナー設定 |
| TaskExecutionRole | AWS::IAM::Role | タスク実行ロール |
| LogGroup | AWS::Logs::LogGroup | CloudWatch Logs |
| SecurityGroup | AWS::EC2::SecurityGroup | セキュリティグループ |

#### パラメータ
- `ProjectName`: プロジェクト名（デフォルト: ecs-bg-deploy）
- `ImageTag`: コンテナイメージタグ（デフォルト: latest）

#### タスク定義設定
```yaml
CPU: 256
Memory: 512
NetworkMode: awsvpc
LaunchType: FARGATE
ContainerPort: 80
```

#### 出力値
- `LoadBalancerDNS`: ALBのDNS名

#### 依存関係
- network.yaml（VPC、サブネット）
- ecr.yaml（ECRリポジトリ）
- ECRにコンテナイメージがプッシュ済み

---

### 5. ecs-bluegreen.yaml - Blue/Green ECS構成
**目的**: CodeDeployを使用したBlue/Greenデプロイメント対応ECSサービス

#### 主要リソース
| リソース | タイプ | 説明 |
|----------|--------|------|
| ECSCluster | AWS::ECS::Cluster | Fargateクラスター |
| TaskDefinition | AWS::ECS::TaskDefinition | コンテナ定義 |
| ECSService | AWS::ECS::Service | Blue/Green対応サービス |
| ApplicationLoadBalancer | AWS::ElasticLoadBalancingV2::LoadBalancer | ロードバランサー |
| TargetGroup1 | AWS::ElasticLoadBalancingV2::TargetGroup | Blueターゲットグループ |
| CodeDeployApplication | AWS::CodeDeploy::Application | CodeDeployアプリケーション |
| CodeDeployDeploymentGroup | AWS::CodeDeploy::DeploymentGroup | デプロイメントグループ |
| CodeDeployServiceRole | AWS::IAM::Role | CodeDeploy実行ロール |

#### パラメータ
- `ProjectName`: プロジェクト名（デフォルト: ecs-bg-deploy）
- `ImageTag`: コンテナイメージタグ（デフォルト: latest）

#### Blue/Green設定
```yaml
DeploymentController: CODE_DEPLOY
DeploymentConfig: CodeDeployDefault.ECSAllAtOnceBlueGreen
TerminationWaitTime: 5分
AutoRollback: 有効（失敗時、アラーム時）
```

#### 出力値
- `LoadBalancerDNS`: ALBのDNS名
- `CodeDeployApplication`: CodeDeployアプリケーション名
- `CodeDeployDeploymentGroup`: デプロイメントグループ名

#### 依存関係
- network.yaml（VPC、サブネット）
- ecr.yaml（ECRリポジトリ）
- ECRにコンテナイメージがプッシュ済み

---

## デプロイ順序

### 初期構築
```bash
# 1. ネットワーク基盤
aws cloudformation create-stack --stack-name ecs-bg-deploy-network --template-body file://aws/cloudformation/network.yaml

# 2. ECRリポジトリ
aws cloudformation create-stack --stack-name ecs-bg-deploy-ecr --template-body file://aws/cloudformation/ecr.yaml

# 3. GitHub OIDC（CI/CD用）
aws cloudformation create-stack --stack-name ecs-bg-deploy-github-oidc --template-body file://aws/cloudformation/github-oidc.yaml

# 4. コンテナイメージプッシュ
docker build --platform linux/amd64 -t ecs-bg-deploy-app .
# ECRプッシュ処理...

# 5. ECSサービス（シンプル構成）
aws cloudformation create-stack --stack-name ecs-bg-deploy-ecs --template-body file://aws/cloudformation/ecs-simple.yaml
```

### Blue/Green移行
```bash
# 1. 既存サービス削除
aws cloudformation delete-stack --stack-name ecs-bg-deploy-ecs

# 2. Blue/Green構成作成
aws cloudformation create-stack --stack-name ecs-bg-deploy-bluegreen --template-body file://aws/cloudformation/ecs-bluegreen.yaml
```

## トラブルシューティング

### よくあるエラー

#### 1. スタック間依存関係エラー
```
Export ecs-bg-deploy-VPC cannot be deleted as it is in use
```
**原因**: 他のスタックが出力値を参照している
**解決**: 依存するスタックを先に削除

#### 2. イメージプルエラー
```
CannotPullContainerError: image manifest does not contain descriptor
```
**原因**: ECRにイメージが存在しない、またはプラットフォーム不一致
**解決**: AMD64プラットフォームでビルド・プッシュ

#### 3. セキュリティグループ削除エラー
```
DependencyViolation: resource has a dependent object
```
**原因**: ENIがアタッチされたまま
**解決**: ECSタスク停止後に削除

### デバッグコマンド

#### スタック状態確認
```bash
aws cloudformation describe-stacks --stack-name <stack-name>
aws cloudformation describe-stack-events --stack-name <stack-name>
```

#### リソース確認
```bash
# ECSサービス状態
aws ecs describe-services --cluster ecs-bg-deploy-cluster --services ecs-bg-deploy-service

# ALBターゲット状態
aws elbv2 describe-target-health --target-group-arn <target-group-arn>
```

## ベストプラクティス

### パラメータ管理
- 環境ごとにパラメータファイルを作成
- 機密情報はSystems Manager Parameter Storeを使用

### タグ戦略
```yaml
Tags:
  - Key: Environment
    Value: !Ref Environment
  - Key: Project
    Value: !Ref ProjectName
  - Key: Owner
    Value: DevOps
```

### 更新戦略
- 本番環境では変更セットを使用
- ロールバック計画を事前準備
- 段階的デプロイメント（dev → staging → prod）