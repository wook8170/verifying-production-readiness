#!/bin/bash
# package — 이 스킬을 Claude Code **플러그인**으로 배포할 수 있는 형태로 조립한다.
#
# 존재 이유: 감정에서 「배포 준비」가 가장 낮았다. 설치 경로가 「이 디렉터리를 복사해라」
# 하나뿐이면, 받는 쪽은 무엇이 최신인지·무엇을 받았는지 알 수 없다. 플러그인 레이아웃은
# 스킬 디렉터리와 **구조가 다르므로**(스킬은 루트에 SKILL.md, 플러그인은 skills/<이름>/),
# 원본을 그 형태로 바꾸면 지금 설치된 스킬이 깨진다. 그래서 **조립본을 따로 만든다.**
#
# 사용: package.sh <출력 경로> [--version X.Y.Z]
# 종료코드: 0=조립 완료 · 1=출력 경로가 이미 있음 · 2=사용법·원본 이상
set -u

SRC=$(cd "$(dirname "$0")/.." && pwd)
NAME=$(basename "$SRC")

usage() {
  cat <<EOF
package.sh — $NAME 을 플러그인 배포 형태로 조립

사용:
  package.sh <출력 경로> [--version X.Y.Z]

만들어지는 것:
  <출력>/.claude-plugin/plugin.json        플러그인 매니페스트
  <출력>/.claude-plugin/marketplace.json   로컬 마켓플레이스 항목
  <출력>/skills/$NAME/                     스킬 본체(문서·bin·test)
  <출력>/README.md · LICENSE

설치(받는 쪽):
  claude plugin marketplace add <출력 경로>
  claude plugin install $NAME@$NAME
EOF
}

OUT=""; VER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --version) shift; VER="${1:-}" ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "알 수 없는 옵션: $1"; usage; exit 2 ;;
    *) [ -z "$OUT" ] && OUT="$1" || { echo "출력 경로는 하나만"; exit 2; } ;;
  esac
  shift
done
[ -n "$OUT" ] || { usage; exit 2; }
[ -e "$OUT" ] && { echo "이미 있다(덮어쓰지 않는다): $OUT"; exit 1; }

# 버전 정본은 README 머리의 「- 버전: **X.Y.Z**」 한 줄이다. 이력 맨 위 항목에서 읽던 때는
# 헤더만 올리고 이력을 안 고친 커밋에서 조용히 옛 버전이 배포됐다(실측으로 잡았다).
if [ -z "$VER" ]; then
  VER=$(grep -m1 -oE '^- 버전: \*\*[0-9]+\.[0-9]+\.[0-9]+\*\*' "$SRC/README.md" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
fi
[ -n "$VER" ] || { echo "버전을 못 읽었다 — README 머리의 '- 버전: **X.Y.Z**' 를 확인하거나 --version 을 줘라"; exit 2; }
# 버전 형식을 검사한다. 안 하면 --version 에 무엇을 주든 그대로 매니페스트에 실려
# 「설치는 되는데 버전이 말이 안 되는」 배포본이 나간다(적대적 라운드 11에서 실측).
case "$VER" in
  [0-9]*.[0-9]*.[0-9]*) case "$VER" in *[!0-9.]*) echo "버전 형식이 아니다: '$VER' (X.Y.Z)"; exit 2 ;; esac ;;
  *) echo "버전 형식이 아니다: '$VER' (X.Y.Z)"; exit 2 ;;
esac

DESC=$(grep -m1 '^description:' "$SRC/SKILL.md" | sed 's/^description: *//')
[ -n "$DESC" ] || { echo "SKILL.md 머리말에 description 이 없다"; exit 2; }

mkdir -p "$OUT/.claude-plugin" "$OUT/skills/$NAME" || exit 2

# 스킬 본체 — 개발 부산물(.git·__pycache__·감정 문서)은 싣지 않는다.
for item in SKILL.md axes.md report-template.md measurement-hygiene.md media-adapters.md README.md LICENSE bin test; do
  [ -e "$SRC/$item" ] && cp -R "$SRC/$item" "$OUT/skills/$NAME/"
done
rm -rf "$OUT/skills/$NAME/bin/__pycache__"
cp "$SRC/README.md" "$OUT/README.md"
[ -f "$SRC/LICENSE" ] && cp "$SRC/LICENSE" "$OUT/LICENSE"

# JSON 은 python 으로 쓴다 — 셸 문자열 조립은 설명문의 따옴표 하나에 깨진다.
python3 - "$OUT" "$NAME" "$VER" "$DESC" <<'PY'
import json, sys
out, name, ver, desc = sys.argv[1:5]
author = {"name": "장욱 (Wook Jang)"}
plugin = {
    "name": name,
    "version": ver,
    "description": desc,
    "author": author,
    "keywords": ["readiness", "release", "go-no-go", "audit", "quality-gate"],
}
market = {
    "name": name,
    "owner": author,
    "metadata": {"description": f"Local marketplace for {name}", "version": ver},
    "plugins": [{
        "name": name, "source": "./", "version": ver,
        "description": desc, "author": author, "category": "workflow",
    }],
}
for path, data in ((".claude-plugin/plugin.json", plugin), (".claude-plugin/marketplace.json", market)):
    with open(f"{out}/{path}", "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
PY

echo "조립 완료: $OUT (v$VER)"
echo "  설치: claude plugin marketplace add \"$OUT\" && claude plugin install $NAME@$NAME"
echo "  검증: bash \"$OUT/skills/$NAME/test/run-tests.sh\""
