#!/bin/bash
# ensure-tools — 축 위임에 쓰는 하위 스킬·CLI 도구 존재 확인 + 자동 설치
#
# 사용: ensure-tools.sh [--install]
#   (없음)     존재 여부만 표로 보고. 하나라도 없으면 exit 1.
#   --install  없는 CLI 도구를 설치 시도(brew)하고, 없는 스킬을 **이미 등록된
#              마켓플레이스에서** 설치 시도(`claude plugin install`).
#
# 자동 설치의 안전 경계: **새 마켓플레이스를 이 스크립트가 추가하지 않는다.** 사용자가
# 이미 신뢰해 등록해 둔 출처에서만 받는다. 이름만 보고 아무 데서나 받아오는 것은 축 ⑦
# 공급망이 경고하는 바로 그 상황이고, 검증 도구가 그걸 하면 안 된다.
#
# 테스트 훅: ET_SKILLS_DIR(스킬 루트 재지정) · ET_PLUGINS_DIR(플러그인 루트 재지정) ·
#            ET_DRYRUN=1(설치 명령을 실행 대신 출력)
# 종료코드: 0=전부 있음 · 1=누락 있음
set -u

INSTALL=0
[ "${1:-}" = "--install" ] && INSTALL=1
SKILLS_DIR="${ET_SKILLS_DIR:-$HOME/.claude/skills}"
PLUGINS_DIR="${ET_PLUGINS_DIR:-$HOME/.claude/plugins}"

# 축 ↔ 위임 스킬 (axes.md 매핑표와 일치 유지)
#   ③ design-review(시각)  ④ qa·qa-only·browse  ⑤ benchmark  ⑥ cso
#   ⑧ codex(적대적 반박)   ⑪ canary(배포 후 감시)
SKILLS="qa qa-only browse benchmark cso design-review codex canary"
# 세션이 제공하는 스킬 — **디렉터리에 없는 것이 정상**이다(내장·플러그인 네임스페이스).
# 예전에는 이것들을 「없음」으로 세어서, 멀쩡히 쓸 수 있는 스킬을 설치하라고 안내했다.
# 존재 확인은 세션 스킬 목록의 몫이라 여기서는 누락으로 세지 않는다.
SESSION_SKILLS="security-review accessibility-review"
# CLI 도구 목록은 아래 heredoc(<명령>|<설치 명령>)에 있다.

# 스킬은 사용자 스킬 디렉터리 외에 플러그인으로도 설치돼 있을 수 있다 — 두 배치 모두 탐지:
#   plugins/marketplaces/<mp>/skills/<name>/SKILL.md
#   plugins/cache/<mp>/<plugin>/<버전>/skills/<name>/SKILL.md
skill_exists() { # <name> → 0=발견(SKILL_WHERE 에 위치), 1=없음
  local s="$1" f
  if [ -f "$SKILLS_DIR/$s/SKILL.md" ]; then SKILL_WHERE="skills"; return 0; fi
  for f in "$PLUGINS_DIR"/marketplaces/*/skills/"$s"/SKILL.md \
           "$PLUGINS_DIR"/cache/*/*/*/skills/"$s"/SKILL.md; do
    if [ -f "$f" ]; then SKILL_WHERE="plugin"; return 0; fi
  done
  return 1
}

# 스킬 자동 설치 — 등록된 마켓플레이스에서만. 0=설치 성공.
install_skill() {
  local s="$1"
  if [ "${ET_DRYRUN:-0}" = "1" ]; then echo "    DRYRUN: claude plugin install $s"; return 0; fi
  command -v claude >/dev/null 2>&1 || { echo "    claude CLI 가 없다 — 수동 설치 필요"; return 1; }
  if ! claude plugin marketplace list 2>/dev/null | grep -q 'Source:'; then
    echo "    등록된 마켓플레이스가 없다 — 신뢰하는 출처를 먼저 추가하라(이 스크립트는 출처를 추가하지 않는다)"
    return 1
  fi
  echo "    설치: claude plugin install $s"
  claude plugin install "$s" >/dev/null 2>&1 || { echo "    설치 실패 — 등록된 마켓플레이스에 '$s' 가 없다"; return 1; }
  skill_exists "$s"
}

MISSING=0
echo "— 하위 스킬 (${SKILLS_DIR} + 플러그인)"
MISSING_SKILLS=""
for s in $SKILLS; do
  if skill_exists "$s"; then
    echo "  ✓ /$s ($SKILL_WHERE)"
  else
    echo "  ✗ /$s — 없음"
    if [ "$INSTALL" -eq 1 ] && install_skill "$s"; then
      echo "  ✓ /$s (설치됨)"
      continue
    fi
    MISSING=$((MISSING + 1)); MISSING_SKILLS="$MISSING_SKILLS $s"
  fi
done

if [ -n "$SESSION_SKILLS" ]; then
  echo "— 세션 제공 스킬 (디렉터리에 없는 것이 정상 — 세션 스킬 목록에서 확인한다)"
  for s in $SESSION_SKILLS; do echo "  ● /$s"; done
fi

echo "— CLI 도구"
MISSING_TOOLS=""
while IFS='|' read -r t inst; do
  [ -n "$t" ] || continue
  if command -v "$t" >/dev/null 2>&1; then
    echo "  ✓ $t"
    continue
  fi
  echo "  ✗ $t — 없음"
  if [ "$INSTALL" -eq 1 ]; then
    if [ "${ET_DRYRUN:-0}" = "1" ]; then
      echo "    DRYRUN: $inst"
      continue                                  # 드라이런은 설치된 것으로 간주
    elif command -v brew >/dev/null 2>&1; then
      echo "    설치: $inst"
      $inst || echo "    설치 실패 — 수동 설치 필요: $inst"
    else
      echo "    brew 없음 — 수동 설치 필요: $inst"
    fi
    if command -v "$t" >/dev/null 2>&1; then
      continue                                  # 설치 성공
    fi
  fi
  MISSING=$((MISSING + 1)); MISSING_TOOLS="$MISSING_TOOLS $t"
done <<'TOOLS'
gitleaks|brew install gitleaks
TOOLS

if [ "$MISSING" -eq 0 ]; then
  echo "✓ 위임 도구 전부 사용 가능"
  exit 0
fi

echo
echo "— 누락 $MISSING 건. 다음을 수행하라:"
if [ -n "$MISSING_SKILLS" ]; then
  echo "  스킬 누락. 세션(모델)이 지금 할 일:"
  for s in $MISSING_SKILLS; do
    echo "    0) 세션 스킬 목록에 '$s' 가 이미 있는지 확인 — 내장·플러그인 스킬은 이 디렉터리에 없어도 쓸 수 있다"
    echo "    1) --install 로도 안 되면(등록된 마켓플레이스에 없다는 뜻) SearchSkills 로 찾아 설치를 제안하라"
    echo "    2) 그래도 없으면 축 파일에 「위임 불가 — 직접 수행」이라 적고 axes.md 의 「어떻게」대로 직접 감사하라"
    echo "       — 도구가 없다는 이유로 축을 빼지 마라"
  done
fi
if [ -n "$MISSING_TOOLS" ]; then
  echo "  CLI 도구:$MISSING_TOOLS → --install 로 재실행하거나 수동 설치"
fi
exit 1
