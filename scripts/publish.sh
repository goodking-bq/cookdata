#!/usr/bin/env bash
# 发布一版内容到 cookdata。
#
# 为什么要有脚本：manifest 里的 contentVersion / tag / dishCount 三个值都是
# **dishes.json 的派生值**。手写它们必然会漂移——上一次就漂了：dishes.json 升到
# 2026.10.19.2，manifest 里的 tag 字段忘了加，结果所有设备同步失败并静默停在旧内容。
# 所以这里不接收这三个参数，只从 dishes.json 读出来重写 manifest。
#
# 用法：
#   scripts/publish.sh                    # 自动把日期段最后一位 +1 后发布
#   scripts/publish.sh 2026.10.20.1       # 指定版本号
#   scripts/publish.sh --dry-run          # 只生成 manifest，不提交不推送
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DRY_RUN=0
TARGET_VERSION=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) TARGET_VERSION="$arg" ;;
  esac
done

[ -f dishes.json ] || { echo "dishes.json not found in $REPO_ROOT" >&2; exit 1; }

read -r CURRENT_VERSION DISH_COUNT < <(python3 - <<'PY'
import json
d = json.load(open('dishes.json', encoding='utf-8'))
print(d.get('contentVersion', '0.0.0.0'), len(d['dishes']))
PY
)

if [ -z "$TARGET_VERSION" ]; then
  TARGET_VERSION=$(python3 - "$CURRENT_VERSION" <<'PY'
import sys
parts = sys.argv[1].split('.')
parts[-1] = str(int(parts[-1]) + 1)
print('.'.join(parts))
PY
  )
fi

if [ "$TARGET_VERSION" = "$CURRENT_VERSION" ]; then
  echo "refusing to publish: version would stay at $CURRENT_VERSION" >&2
  echo "clients only update when the version moves forward, so republishing the same version reaches nobody." >&2
  exit 1
fi

echo "content: $CURRENT_VERSION -> $TARGET_VERSION"
echo "dishes : $DISH_COUNT"

# 1) 版本号写回内容本身（单一真相源）
python3 - "$TARGET_VERSION" <<'PY'
import json, sys, io
version = sys.argv[1]
path = 'dishes.json'
raw = open(path, encoding='utf-8').read()
data = json.loads(raw)
data['contentVersion'] = version
# indent=2 + ensure_ascii=False：与手写风格一致，diff 才不会整文件翻红
open(path, 'w', encoding='utf-8').write(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
PY

# 2) 从内容派生 manifest —— 三个字段不可能再对不上
python3 - "$TARGET_VERSION" <<'PY'
import json, sys
version = sys.argv[1]
dishes = json.load(open('dishes.json', encoding='utf-8'))
manifest = {
    "schemaVersion": dishes['schemaVersion'],
    "contentVersion": dishes['contentVersion'],
    "tag": "v" + dishes['contentVersion'],
    "dishCount": len(dishes['dishes']),
    "dishesFile": "dishes.json",
}
open('manifest.json', 'w', encoding='utf-8').write(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
PY

# 3) 发布前自检：重复 id 会让 App 静默丢菜
python3 - <<'PY'
import json, sys
d = json.load(open('dishes.json', encoding='utf-8'))
ids = [x['id'] for x in d['dishes']]
dupes = {i for i in ids if ids.count(i) > 1}
if dupes:
    sys.exit('duplicate dish ids: ' + ', '.join(sorted(dupes)))
if not ids:
    sys.exit('catalog is empty')
m = json.load(open('manifest.json', encoding='utf-8'))
assert m['tag'] == 'v' + m['contentVersion'], 'tag/version drift'
assert m['dishCount'] == len(ids), 'dishCount drift'
print('preflight ok')
PY

if [ "$DRY_RUN" = "1" ]; then
  echo "--- manifest.json (dry run, not committed) ---"
  cat manifest.json
  exit 0
fi

# 4) 提交 + 打标签 + 推送。**标签必须与 manifest 同时推**：
#    App 拉 manifest 里声明的 tag 路径，标签没推上去就会 404 → 整次更新被丢弃。
#
#    **图片刻意不进这个提交**。配图走 main 分支的 images/，与内容版本解耦：
#    内容必须版本严对应（新内容配旧图 = 张冠李戴），图片则是纯加法，且
#    按 tag 取图必然出一次错配——App 内置快照停在 v6 而图片随 v7 才加，
#    就会去取 v6/images/x.jpg 得 404，用户看到「有菜没图」。
#    详见 WokItCore/Catalog/CatalogManifest.swift 里 imageURL 的说明。
#    加图请单独提交（git add images），不要混进内容发布。
git add dishes.json manifest.json
git commit -q -m "content: v$TARGET_VERSION ($DISH_COUNT dishes)"
git tag -f "v$TARGET_VERSION"
git push -q origin HEAD
git push -q -f origin "v$TARGET_VERSION"

echo "published v$TARGET_VERSION"
echo "manifest: https://raw.githubusercontent.com/$(git config --get remote.origin.url | sed -E 's#.*[:/]([^/]+/[^/.]+)(\.git)?$#\1#')/main/manifest.json"
