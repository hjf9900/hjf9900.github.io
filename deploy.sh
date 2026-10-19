#!/bin/bash
echo "清理缓存并生成..."
hexo clean && hexo generate

echo "提交并推送到 GitHub..."
git add .
git commit -m "update: $(date +'%Y-%m-%d %H:%M:%S')"
git push origin main

