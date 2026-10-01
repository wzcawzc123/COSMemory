#!/bin/sh
# 发布打包: 根布局 + 排除死重(module原版物料/image文档图/docs/tests/node_modules)
# 用法: sh tools/pack_release.sh <version如v0.4.0> <cosguard-apk>
set -e
VER="$1"; APK="$2"
[ -n "$VER" ] && [ -f "$APK" ] || { echo "usage: $0 <ver> <cosguard.apk>"; exit 1; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STAGE=$(mktemp -d)
git -C "$ROOT" archive "$VER" | tar -x -C "$STAGE"
OUT="/workspace/COSMemory_${VER}.zip"; rm -f "$OUT"
STAGE="$STAGE" OUT="$OUT" APK="$APK" python3 - <<'PY'
import zipfile, os
stage, out, apk = os.environ['STAGE'], os.environ['OUT'], os.environ['APK']
skip = {'panel/node_modules', 'panel/dist', '.git', 'docs', 'tests', 'module', 'image',
        'data', '.gitignore', 'changelog.md', 'version.json', 'magisk.sh', 'tools',
        'deploy_clean.sh', 'forensic.sh', 'watchdog_test.sh', 'restart_engine.sh',
        'panel/package-lock.json',
        'config/JSON-CONFIG.md', 'config/JSON-CONFIG-zh.md', 'config/JSON-CONFIG-ru.md',
        'config/README.md'}
n = 0
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for dp, dns, fns in os.walk(stage):
        rel = os.path.relpath(dp, stage)
        if rel != '.' and any(rel == s or rel.startswith(s + os.sep) for s in skip):
            dns.clear(); continue
        for fn in fns:
            relf = fn if rel == '.' else os.path.join(rel, fn)
            if relf in skip: continue
            p = os.path.join(dp, fn)
            z.write(p, relf); n += 1
    z.write(apk, 'assets/COSGuard-' + os.path.basename(out).split('_',1)[1].replace('.zip','') + '.apk'); n += 1
print(f'entries={n}')
PY
md5sum "$OUT"; rm -rf "$STAGE"
