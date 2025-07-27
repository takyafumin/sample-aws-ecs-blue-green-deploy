# Blue/Greenデプロイメント手順

## 前提条件
- ネットワーク、ECR、既存ECSサービスが構築済み
- 新しいコンテナイメージがECRにプッシュ済み

## 1. 既存環境からBlue/Green環境への移行

### 既存スタックの削除
```bash
aws cloudformation delete-stack --stack-name ecs-bg-deploy-ecs
```

### Blue/Green環境の構築
```bash
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-bluegreen \
  --template-body file://aws/cloudformation/ecs-bluegreen.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy \
               ParameterKey=ImageTag,ParameterValue=latest \
  --capabilities CAPABILITY_IAM
```

## 2. 新バージョンのデプロイ

### 新しいタスク定義の作成
```bash
# 新しいイメージタグでタスク定義を更新
aws ecs register-task-definition \
  --family ecs-bg-deploy-task \
  --network-mode awsvpc \
  --requires-compatibilities FARGATE \
  --cpu 256 \
  --memory 512 \
  --execution-role-arn arn:aws:iam::<ACCOUNT_ID>:role/ecs-bg-deploy-TaskExecutionRole-* \
  --container-definitions '[
    {
      "name": "app",
      "image": "<ACCOUNT_ID>.dkr.ecr.ap-northeast-1.amazonaws.com/ecs-bg-deploy-app:v2.0.0",
      "portMappings": [{"containerPort": 80}],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/ecs-bg-deploy",
          "awslogs-region": "ap-northeast-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]'
```

### CodeDeployでのデプロイ実行
```bash
aws deploy create-deployment \
  --application-name ecs-bg-deploy-app \
  --deployment-group-name ecs-bg-deploy-dg \
  --revision revisionType=AppSpecContent,appSpecContent='{
    "version": 0.0,
    "Resources": [{
      "TargetService": {
        "Type": "AWS::ECS::Service",
        "Properties": {
          "TaskDefinition": "arn:aws:ecs:ap-northeast-1:<ACCOUNT_ID>:task-definition/ecs-bg-deploy-task:<REVISION>",
          "LoadBalancerInfo": {
            "ContainerName": "app",
            "ContainerPort": 80
          }
        }
      }
    }]
  }'
```

## 3. デプロイメント監視

### デプロイメント状況の確認
```bash
aws deploy get-deployment --deployment-id <DEPLOYMENT_ID>
```

### ECSサービスの状況確認
```bash
aws ecs describe-services \
  --cluster ecs-bg-deploy-cluster \
  --services ecs-bg-deploy-service
```

## 4. ロールバック

### 手動ロールバック
```bash
aws deploy stop-deployment \
  --deployment-id <DEPLOYMENT_ID> \
  --auto-rollback-enabled
```

## 注意事項
- デプロイ中は一時的にリソース使用量が2倍になります
- Blue環境は成功後5分で自動終了されます
- 失敗時は自動ロールバックが実行されます