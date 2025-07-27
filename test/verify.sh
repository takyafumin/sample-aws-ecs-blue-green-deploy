#!/bin/bash
# Blue/Greenデプロイ機能検証スクリプト
# 使用方法: ./test/verify.sh

set -e

PROJECT_NAME="ecs-bg-deploy"
REGION="ap-northeast-1"

echo "=== Blue/Greenデプロイ機能検証 ==="

# 前提条件チェック
echo "1. 前提条件チェック"

# AWS認証確認
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "❌ AWS認証が設定されていません"
    exit 1
fi
echo "✅ AWS認証OK"

# Docker確認
if ! docker --version >/dev/null 2>&1; then
    echo "❌ Dockerが利用できません"
    exit 1
fi
echo "✅ Docker OK"

# 必要なAWSリソース確認
echo "2. AWSリソース確認"

# ECRリポジトリ
if ! aws ecr describe-repositories --repository-names ${PROJECT_NAME}-app >/dev/null 2>&1; then
    echo "❌ ECRリポジトリが存在しません"
    exit 1
fi
echo "✅ ECRリポジトリ OK"

# ECSクラスター
if ! aws ecs describe-clusters --clusters ${PROJECT_NAME}-cluster >/dev/null 2>&1; then
    echo "❌ ECSクラスターが存在しません"
    exit 1
fi
echo "✅ ECSクラスター OK"

# CodeDeployアプリケーション
if ! aws deploy get-application --application-name ${PROJECT_NAME}-app >/dev/null 2>&1; then
    echo "❌ CodeDeployアプリケーションが存在しません"
    exit 1
fi
echo "✅ CodeDeployアプリケーション OK"

# ALB
if ! aws elbv2 describe-load-balancers --names ${PROJECT_NAME}-alb >/dev/null 2>&1; then
    echo "❌ ALBが存在しません"
    exit 1
fi
echo "✅ ALB OK"

# 現在の状態確認
echo "3. 現在の状態確認"

# ECSサービス状態
SERVICE_STATUS=$(aws ecs describe-services \
  --cluster ${PROJECT_NAME}-cluster \
  --services ${PROJECT_NAME}-service \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}' \
  --output table)
echo "ECSサービス状態:"
echo "$SERVICE_STATUS"

# ALBエンドポイント
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names ${PROJECT_NAME}-alb \
  --query 'LoadBalancers[0].DNSName' --output text)
echo "ALBエンドポイント: http://$ALB_DNS"

# アプリケーション応答確認
echo "4. アプリケーション応答確認"
if curl -s -f http://$ALB_DNS >/dev/null; then
    echo "✅ アプリケーション応答OK"
    echo "現在の応答:"
    curl -s http://$ALB_DNS | head -3
else
    echo "❌ アプリケーションが応答しません"
    exit 1
fi

echo ""
echo "=== 検証完了 ==="
echo "Blue/Greenデプロイの実行準備が整っています"