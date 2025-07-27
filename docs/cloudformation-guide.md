# CloudFormationテンプレート詳細ガイド

## 概要
このプロジェクトでは、Blue/Green ECS環境を構築するために4つのCloudFormationテンプレートを使用しています。

## テンプレート構成

```
aws/cloudformation/
├── network.yaml        # 基盤: VPC・サブネット・IGW
├── ecr.yaml           # 基盤: ECRリポジトリ
├── github-oidc.yaml   # 基盤: CI/CD用OIDC認証
└── ecs-bluegreen.yaml # メイン: Blue/Green ECS環境
```

## テンプレート詳細

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

### 4. ecs-bluegreen.yaml - Blue/Green ECS環境（メイン）
**目的**: 完全なBlue/Green デプロイメント環境の構築

#### 主要リソース
| カテゴリ | リソース | タイプ | 説明 |
|----------|----------|--------|------|
| **ECS** | ECSCluster | AWS::ECS::Cluster | Fargateクラスター |
| | TaskDefinition | AWS::ECS::TaskDefinition | コンテナ定義 |
| | ECSService | AWS::ECS::Service | CodeDeploy制御のサービス |
| | TaskExecutionRole | AWS::IAM::Role | タスク実行ロール |
| **ALB** | ApplicationLoadBalancer | AWS::ElasticLoadBalancingV2::LoadBalancer | ロードバランサー |
| | TargetGroup1 | AWS::ElasticLoadBalancingV2::TargetGroup | Blue環境用 |
| | TargetGroup2 | AWS::ElasticLoadBalancingV2::TargetGroup | Green環境用 |
| | ALBListener | AWS::ElasticLoadBalancingV2::Listener | 本番トラフィック（:80） |
| | TestListener | AWS::ElasticLoadBalancingV2::Listener | テストトラフィック（:8080） |
| **CodeDeploy** | CodeDeployApplication | AWS::CodeDeploy::Application | デプロイアプリケーション |
| | CodeDeployDeploymentGroup | AWS::CodeDeploy::DeploymentGroup | デプロイグループ |
| | CodeDeployServiceRole | AWS::IAM::Role | CodeDeploy実行ロール |
| **セキュリティ** | ALBSecurityGroup | AWS::EC2::SecurityGroup | ALB用 |
| | ECSSecurityGroup | AWS::EC2::SecurityGroup | ECS用 |
| **監視** | LogGroup | AWS::Logs::LogGroup | CloudWatch Logs |

#### パラメータ
- `ProjectName`: プロジェクト名（デフォルト: ecs-bg-deploy）
- `ImageTag`: コンテナイメージタグ（デフォルト: v1.0.0）

#### Blue/Green設定
```yaml
DeploymentController: CODE_DEPLOY
DeploymentConfigName: CodeDeployDefault.ECSAllAtOnce
DeploymentType: BLUE_GREEN
```

#### トラフィック制御
- **本番トラフィック**: ALBListener（:80） → TargetGroup1（Blue）
- **テストトラフィック**: TestListener（:8080） → TargetGroup2（Green）

#### 自動ロールバック設定
- デプロイ失敗時に自動ロールバック
- CloudWatchアラーム検知時に自動ロールバック
- 手動停止時に自動ロールバック

#### 出力値
- `LoadBalancerDNS`: ALBのDNS名
- `TestEndpoint`: テスト環境のURL
- `CodeDeployApplication`: CodeDeployアプリケーション名
- `CodeDeployDeploymentGroup`: デプロイメントグループ名

#### 依存関係
- network.yaml（VPC、サブネット）
- ecr.yaml（コンテナイメージ）
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
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-network \
  --template-body file://aws/cloudformation/network.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy

# 2. ECRリポジトリ
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-ecr \
  --template-body file://aws/cloudformation/ecr.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy

# 3. GitHub OIDC（CI/CD用）
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-github-oidc \
  --template-body file://aws/cloudformation/github-oidc.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy \
               ParameterKey=GitHubOrg,ParameterValue=YOUR_USERNAME \
               ParameterKey=GitHubRepo,ParameterValue=sample-aws-ecs-blue-green-deploy \
  --capabilities CAPABILITY_NAMED_IAM

# 4. コンテナイメージプッシュ
./scripts/build.sh v1.0.0

# 5. Blue/Green ECS環境
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-bluegreen \
  --template-body file://aws/cloudformation/ecs-bluegreen.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy \
               ParameterKey=ImageTag,ParameterValue=v1.0.0 \
  --capabilities CAPABILITY_IAM
```

# 2. Blue/Green構成作成
aws cloudformation create-stack --stack-name ecs-bg-deploy-bluegreen --template-body file://aws/cloudformation/ecs-bluegreen.yaml
```

## トラブルシューティング

### よくあるエラー

### Blue/Greenデプロイの実行
```bash
# 新しいバージョンのデプロイ
./scripts/deploy.sh v2.0.0

# または統合スクリプト（ビルド＋デプロイ）
./scripts/dev-deploy.sh v2.0.0
```

## トラブルシューティング

#### 1. スタック間依存関係エラー
```
Export ecs-bg-deploy-VPC cannot be deleted as it is in use
```
**原因**: 他のスタックが出力値を参照している  
**解決**: 依存するスタックを先に削除

#### 2. DeploymentConfigエラー
```
No deployment configuration found for name: CodeDeployDefault.ECSAllAtOnceBlueGreen
```
**原因**: 存在しないCodeDeploy設定名を指定  
**解決**: `CodeDeployDefault.ECSAllAtOnce` に修正

#### 3. イメージプルエラー
```
CannotPullContainerError: image manifest does not contain descriptor
```
**原因**: ECRにイメージが存在しない、またはプラットフォーム不一致  
**解決**: `--platform linux/amd64` でビルド・プッシュ

### デバッグコマンド

#### スタック状態確認
```bash
aws cloudformation describe-stacks --stack-name <stack-name>
aws cloudformation describe-stack-events --stack-name <stack-name>
```

#### ECS・CodeDeploy確認
```bash
# ECSサービス状態
aws ecs describe-services --cluster ecs-bg-deploy-cluster --services ecs-bg-deploy-service

# CodeDeployアプリケーション・デプロイメントグループ確認
aws deploy list-applications
aws deploy list-deployment-groups --application-name ecs-bg-deploy-app

# デプロイメント履歴
aws deploy list-deployments \
  --application-name ecs-bg-deploy-app \
  --deployment-group-name ecs-bg-deploy-dg

# 最新デプロイ状況
aws deploy get-deployment --deployment-id <deployment-id> \
  --query 'deploymentInfo.{Status:status,CreatedTime:createTime,CompleteTime:completeTime}'

# リアルタイム監視
watch -n 5 'aws deploy get-deployment --deployment-id <deployment-id> --query "deploymentInfo.status" --output text'

# ALBターゲット状態
aws elbv2 describe-target-health --target-group-arn <target-group-arn>
```

#### CodeDeployコンソール
AWS Management Console → CodeDeploy → Applications → `ecs-bg-deploy-app`  
https://console.aws.amazon.com/codesuite/codedeploy/applications

## ベストプラクティス

### 環境管理
- パラメータファイルで環境ごとの設定を分離
- タグを活用したリソース管理
- Cost Explorerでコスト監視

### セキュリティ
```yaml
# 最小権限の原則
SecurityGroups:
  - SourceSecurityGroupId: !Ref ALBSecurityGroup  # IP直接指定を避ける

# ログ保持期間設定
LogGroup:
  RetentionInDays: 7  # 適切な期間設定
```
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