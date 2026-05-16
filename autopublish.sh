#!/bin/bash

FILE_PATH="$1"
TAG="$2"

# 1. 检查输入参数和文件是否存在
if [ -z "$FILE_PATH" ]; then
    echo "❌ 错误：请提供 Markdown 文件的路径！"
    echo "用法: sh publish.sh <文件路径> [标签]"
    exit 1
fi

if [ ! -f "$FILE_PATH" ]; then
    echo "❌ 错误：找不到文件 '$FILE_PATH'"
    exit 1
fi

# 2. 提取第一行（tr -d '\r' 是为了抹平 Windows 和 Linux 换行符的差异）
FIRST_LINE=$(head -n 1 "$FILE_PATH" | tr -d '\r')

# 3. 正则匹配检查 '# ' 格式并提取标题
if [[ ! "$FIRST_LINE" =~ ^#[[:space:]]+(.+) ]]; then
    echo "❌ 错误：Markdown 文件的第一行必须是 '# 文章标题' 的格式！"
    echo "当前第一行内容为: $FIRST_LINE"
    exit 1
fi

TITLE="${BASH_REMATCH[1]}"
echo "📄 提取到文章标题: $TITLE"

# 4. 生成当前时间
DATE_STR=$(date +"%Y-%m-%d %H:%M:%S")

# 5. 将非法字符替换为 '-' 生成安全的文件名
SAFE_TITLE=$(echo "$TITLE" | sed 's/[\\/:*?"<>|]/-/g')
TARGET_PATH="source/_posts/${SAFE_TITLE}.md"

# 6. 生成新的 YAML Front-matter 并覆盖写入目标文件
{
    echo "---"
    echo "title: \"$TITLE\""
    echo "date: $DATE_STR"
    if [ -n "$TAG" ]; then
        echo "tags:"
        echo "  - $TAG"
    fi
    echo "---"
} > "$TARGET_PATH"

# 7. 把原文件从第 2 行开始的内容追加到新文件尾部
tail -n +2 "$FILE_PATH" >> "$TARGET_PATH"

echo "✅ 文件已成功处理并拷贝至: $TARGET_PATH"

# 8. 执行 Hexo 和 Git 自动化操作
echo "🚀 开始清理并生成前端网页..."
hexo clean
hexo d -g

echo "📦 开始备份源码到 GitHub source 分支..."
git add .
git commit -m "Auto publish: $TITLE"
git push origin source

echo "🎉 自动发布与备份流程成功执行！"