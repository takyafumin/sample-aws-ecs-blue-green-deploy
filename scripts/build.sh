#!/bin/bash
# イメージビルド・プッシュスクリプト
# 使用方法: ./scripts/build.sh <VERSION>

set -e

PROJECT_NAME="ecs-bg-deploy"
REGION="ap-northeast-1"

if [ $# -ne 1 ]; then
    echo "使用方法: $0 <VERSION>"
    echo "例: $0 v2.0.0"
    exit 1
fi

VERSION=$1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${PROJECT_NAME}-app"

echo "=== イメージビルド・プッシュ ==="
echo "バージョン: $VERSION"

# ビルド
echo "Dockerイメージをビルド中..."
docker build --platform linux/amd64 -t ${PROJECT_NAME}-app:${VERSION} .

# ECRプッシュ
echo "ECRにプッシュ中..."
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_URI}
docker tag ${PROJECT_NAME}-app:${VERSION} ${ECR_URI}:${VERSION}
docker push ${ECR_URI}:${VERSION}

echo "ビルド・プッシュ完了: ${ECR_URI}:${VERSION}"