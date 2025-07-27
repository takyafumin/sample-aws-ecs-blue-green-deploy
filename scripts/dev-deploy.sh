#!/bin/bash
# 開発者向け統合デプロイスクリプト（ビルド→デプロイ）
# 使用方法: ./scripts/dev-deploy.sh <VERSION>

set -e

if [ $# -ne 1 ]; then
    echo "使用方法: $0 <VERSION>"
    echo "例: $0 v2.0.0"
    exit 1
fi

VERSION=$1

echo "=== 開発者向け統合デプロイ ==="
echo "バージョン: $VERSION"

# ビルド・プッシュ
./scripts/build.sh $VERSION

# デプロイ
./scripts/deploy.sh $VERSION

echo "統合デプロイ完了"