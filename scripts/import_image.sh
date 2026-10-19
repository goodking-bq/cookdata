#!/usr/bin/env bash
# 把一张原始生成的图处理成 App 用的规格。
#
# 三个动作都不可省：
# 1. 裁掉底部 ~15.6% —— 生成工具会在右下角打角标，裁不掉就不能上架；
# 2. 缩到 1200px 宽 —— 原图 1536 在 3x 屏上已经超出显示需要，纯浪费流量；
# 3. 转 JPEG —— PNG 的 2MB 变 180KB，200 张从 400MB 降到 36MB。
#
# 用法：scripts/import_image.sh <源图> <dish-id>
set -euo pipefail

SRC="${1:?usage: import_image.sh <source image> <dish-id>}"
ID="${2:?usage: import_image.sh <source image> <dish-id>}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/images"
mkdir -p "$OUT_DIR"

if ! printf '%s' "$ID" | grep -Eq '^[a-z0-9_]{1,64}$'; then
  echo "invalid dish id: $ID (must be a lowercase slug)" >&2
  exit 1
fi

W=$(sips -g pixelWidth "$SRC" | awk '/pixelWidth/{print $2}')
H=$(sips -g pixelHeight "$SRC" | awk '/pixelHeight/{print $2}')
KEEP=$(( H * 844 / 1000 ))

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

sips --cropOffset 0 0 -c "$KEEP" "$W" "$SRC" --out "$TMP/cropped.png" >/dev/null
sips --resampleWidth 1200 -s format jpeg -s formatOptions 78 \
     "$TMP/cropped.png" --out "$OUT_DIR/$ID.jpg" >/dev/null

BYTES=$(wc -c < "$OUT_DIR/$ID.jpg" | tr -d ' ')
echo "$ID.jpg  ${BYTES} bytes"
