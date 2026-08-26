#!/bin/bash
# new-report — 출하 검증 리포트 뼈대 생성
#
# 존재 이유: 형식이 진입 장벽이었다. 대장 헤더 한 줄(`**판정** … **open BLOCKER** N`)이
# 빠지면 lint 가 거부하는데, 사람은 그 형식을 외워서 손으로 만들고 있었다. 감정에서
# 「사용성 · 비용」이 가장 낮게 나온 이유의 절반이 이것이다. 뼈대를 기계가 만들면
# 형식 오류는 0 이 되고, 사람은 내용에만 집중한다.
#
# 시작 판정은 언제나 **판정 불가**다 — 아직 아무것도 안 봤으니 그게 사실이다.
# 「출하 가능」으로 시작해 두고 나중에 내리는 것은 이 스킬이 금지하는 사후 승인이다.
#
# 사용: new-report.sh <대상 경로> [--full] [--date YYYY-MM-DD] [--axes 1,2,5]
#   기본(경량)  <대상>/readiness.md + evidence/
#   --full     <대상>/docs/release-readiness/<날짜>/ 에 정식 골격(축 파일 + 대장)
#   --axes     **볼 축을 착수 시점에 고른다.** 코어 ④⑥⑧⑨ 는 목록에서 빠져 있어도 자동으로
#              들어간다 — 사용자도 뺄 수 없는 축이다(SKILL.md 「착수 첫 단계」). 고른 결과는
#              리포트 머리의 `축:`/`뺀 축:` 줄과 「보지 않은 것 → 가. 의도적 제외」에 남는다.
#              정식 모드에서는 **고른 축의 파일만** 만든다 — 안 볼 축의 빈 파일이 남으면
#              다음 사람이 「봤는데 비어 있다」로 읽는다.
# 종료코드: 0=생성 · 1=이미 있음(덮어쓰지 않는다) · 2=사용법
set -u

usage() {
  cat <<'EOF'
new-report.sh — 출하 검증 리포트 뼈대 생성

사용:
  new-report.sh <대상 경로> [--full] [--date YYYY-MM-DD] [--axes 1,2,5]

  <대상 경로>   리포트를 둘 프로젝트 루트(없으면 만든다)
  --full        정식 모드 — docs/release-readiness/<날짜>/ 에 축 파일까지
  --date        정식 모드의 날짜 디렉터리(기본: 오늘)
  --axes        볼 축 번호(1–11, 쉼표/공백 구분). 코어 ④⑥⑧⑨ 는 자동 포함 — 못 뺀다.
                생략하면 경량은 코어만, 정식은 11축 전부.
                예) --axes 3,5,7   → 본 축 ③④⑤⑥⑦⑧⑨ · 뺀 축 ①②⑩⑪

축 번호: ①기능 ②백엔드 ③UI·접근성 ④사용성·E2E ⑤성능 ⑥보안 ⑦공급망
        ⑧논리·정합성 ⑨결정성 ⑩배포·롤백 ⑪운영·관측성

생성 후:
  1. 게이트 표의 목표를 **착수 전에** 수치로 채운다 (Iron Rule 1)
  2. 발견을 대장에 적는다 — 발견 즉시, 몰아 쓰지 않는다
  3. bash bin/ledger-lint.sh <대상>   # 판정 전 필수
EOF
}

TARGET=""; FULL=0; DATE=""; AXES=""; AXES_GIVEN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --full) FULL=1 ;;
    --date) shift; DATE="${1:-}" ;;
    --axes) shift; AXES="${1:-}"; AXES_GIVEN=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "알 수 없는 옵션: $1"; usage; exit 2 ;;
    *) [ -z "$TARGET" ] && TARGET="$1" || { echo "대상 경로는 하나만"; exit 2; } ;;
  esac
  shift
done
[ -n "$TARGET" ] || { usage; exit 2; }
# 대상이 이미 파일이면 mkdir 의 날 오류가 새어 나갔다 — 사람이 읽을 안내로 바꾼다.
[ -e "$TARGET" ] && [ ! -d "$TARGET" ] && { echo "대상은 디렉터리여야 한다(파일이 있다): $TARGET"; exit 2; }
[ -n "$DATE" ] || DATE=$(date +%Y-%m-%d)
# 날짜는 디렉터리 이름이 된다 — 형식을 안 보면 `--date ../../etc` 로 의도한 자리 밖에
# 리포트를 만든다(적대적 라운드 12에서 실측).
case "$DATE" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *) echo "날짜 형식이 아니다: '$DATE' (YYYY-MM-DD)"; exit 2 ;;
esac

# ── 축 선택 ────────────────────────────────────────────────────────────
# 「어떤 축을 볼지」는 착수 **전에** 정해져야 한다(Iron Rule 1 의 범위 판). 예전에는 그
# 합의가 산문 규약으로만 있어서, 고른 결과가 리포트 어디에도 기계가 읽는 형태로 남지
# 않았다. 여기서 골라 뼈대에 박으면 다음 사람이 「무엇을 안 봤는지」를 추측하지 않는다.
#
# 코어 ④⑥⑧⑨ 는 목록에 없어도 넣는다 — 사용자도 뺄 수 없는 축이다. 볼 수 **없었던**
# 경우는 「빼는 것」이 아니라 「나. 확인 불가」다(둘을 섞으면 다음 세션이 근거 부재를
# 결함으로 착각한다).
CORE_AXES="4 6 8 9"
circle() {
  case "$1" in
    1) printf '①' ;; 2) printf '②' ;; 3) printf '③' ;; 4) printf '④' ;;
    5) printf '⑤' ;; 6) printf '⑥' ;; 7) printf '⑦' ;; 8) printf '⑧' ;;
    9) printf '⑨' ;; 10) printf '⑩' ;; 11) printf '⑪' ;;
  esac
}
axis_name() {
  case "$1" in
    1) printf 'features' ;; 2) printf 'backend' ;; 3) printf 'ui' ;; 4) printf 'usability' ;;
    5) printf 'perf' ;; 6) printf 'security' ;; 7) printf 'supply-chain' ;; 8) printf 'logic' ;;
    9) printf 'determinism' ;; 10) printf 'deploy' ;; 11) printf 'ops' ;;
  esac
}
SEEN=""; DROPPED=""; FORCED=""
if [ "$AXES_GIVEN" = 1 ]; then
  [ -n "$AXES" ] || { echo "--axes 에 축 번호가 없다 (예: --axes 3,5,7)"; exit 2; }
  PICKED=$(printf '%s' "$AXES" | tr ',;' '  ')
  for n in $PICKED; do
    case "$n" in
      [1-9]|10|11) ;;
      *) echo "축 번호가 아니다: '$n' — 1~11 만 (예: --axes 3,5,7)"; exit 2 ;;
    esac
  done
  for n in 1 2 3 4 5 6 7 8 9 10 11; do
    hit=0
    for m in $PICKED; do [ "$m" = "$n" ] && hit=1; done
    core=0
    for c in $CORE_AXES; do [ "$c" = "$n" ] && core=1; done
    if [ "$hit" = 1 ] || [ "$core" = 1 ]; then
      SEEN="$SEEN $n"
      [ "$hit" = 0 ] && FORCED="$FORCED $n"
    else
      DROPPED="$DROPPED $n"
    fi
  done
  [ -n "$FORCED" ] && {
    printf '코어 축은 뺄 수 없다 — 자동 포함:'
    for n in $FORCED; do printf ' %s' "$(circle "$n")"; done
    printf '  (볼 수 없었던 축은 「나. 확인 불가」에 적어라)\n'
  }
else
  # 생략 시: 경량은 코어만, 정식은 11축 전부 — 기존 동작.
  if [ "$FULL" = 1 ]; then SEEN=" 1 2 3 4 5 6 7 8 9 10 11"; else SEEN=" 4 6 8 9"; fi
fi
axis_list() { for n in $1; do printf '%s' "$(circle "$n")"; done; }
SEEN_C=$(axis_list "$SEEN")
DROPPED_C=$(axis_list "$DROPPED")
# 축 선언 줄 — 기계도 사람도 읽는 한 줄. 고르지 않았으면 예전 자리표시자를 그대로 둔다
# (자리표시자를 채우는 것은 사람의 몫이고, lint 는 자리표시자를 검사하지 않는다).
if [ "$AXES_GIVEN" = 1 ]; then
  if [ -n "$DROPPED" ]; then
    AXIS_LINE="대상 \`<커밋>\` · 축: $SEEN_C · 뺀 축: $DROPPED_C — <누가·왜 — 착수 전에 적는다>"
    EXCLUDED_LINE="가. 의도적 제외: $DROPPED_C — <누가·왜> · 나. 확인 불가: <누가 무엇을 주면 볼 수 있는지>"
  else
    AXIS_LINE="대상 \`<커밋>\` · 축: $SEEN_C (전 축) · 뺀 축: 없음"
    EXCLUDED_LINE="가. 의도적 제외: 없음 · 나. 확인 불가: <누가 무엇을 주면 볼 수 있는지>"
  fi
else
  AXIS_LINE="대상 \`<커밋>\` · 축: $SEEN_C + <변경이 닿는 축> · 뺀 축: <목록 — 사유>"
  EXCLUDED_LINE="가. 의도적 제외: <누가·왜> · 나. 확인 불가: <누가 무엇을 주면 볼 수 있는지>"
fi

# 뼈대 조각 — 대장 표 형식은 report-template.md 와 한 벌이어야 한다.
# 여기가 갈리면 스캐폴더가 만든 리포트를 lint 가 거부하는 최악의 조합이 된다.
LEDGER_HEAD='| ID | 심각도 | 축 | 한 줄 | 상태 | 근거등급 | 근거 | 닫은 증거 |
|---|---|---|---|---|---|---|---|'

gate_table() {
  cat <<'EOF'
| 게이트 | 목표 (착수 전 확정 — 결과 보고 조정 금지) | 실측 |
|---|---|---|
| G1 테스트 | <스위트> 전건 pass · **fail 0** | 미실시 |
| G2 보안 | 프로덕션 도달 취약점 **0** | 미실시 |
| G3 E2E | 시나리오 실패 **0** | 미실시 |
| G4 결정성 | 3회 반복 동일 · 플레이키 **0** | 미실시 |
EOF
}

if [ "$FULL" = 0 ]; then
  # ── 경량 모드 ────────────────────────────────────────────────
  OUT="$TARGET/readiness.md"
  [ -e "$OUT" ] && { echo "이미 있다(덮어쓰지 않는다): $OUT"; exit 1; }
  mkdir -p "$TARGET/evidence" || exit 2
  {
    printf '# <대상> 출하 검증 — 경량 모드\n\n'
    printf '**갱신** %s · **판정** 판정 불가 · **open BLOCKER** 0 · **open 전체** 0\n' "$DATE"
    printf '%s\n\n' "$AXIS_LINE"
    printf '## 게이트 (착수 전 확정 — Iron Rule 1)\n'
    gate_table
    printf '\n## 결함 대장\n%s\n\n' "$LEDGER_HEAD"
    printf '## 보지 않은 것\n'
    printf '%s\n\n' "$EXCLUDED_LINE"
    printf '## 조건 (판정이 「조건부」일 때만 — 누가·무엇을·어떻게 확인하면 풀리나)\n\n'
  } > "$OUT"
  echo "생성: $OUT · $TARGET/evidence/"
else
  # ── 정식 모드 ────────────────────────────────────────────────
  DIR="$TARGET/docs/release-readiness/$DATE"
  [ -e "$DIR" ] && { echo "이미 있다(덮어쓰지 않는다): $DIR"; exit 1; }
  mkdir -p "$DIR/evidence" || exit 2
  {
    printf '# 출하 검증 — 판정 요약\n\n'
    printf '**갱신** %s · **판정** 판정 불가 · **open BLOCKER** 0 · **open 전체** 0\n' "$DATE"
    printf '%s\n\n' "$AXIS_LINE"
    printf '## 게이트 (착수 전 확정 — Iron Rule 1)\n'
    gate_table
    printf '\n## 축별 한 줄\n\n## 보지 않은 것\n'
    printf '%s\n' "$EXCLUDED_LINE"
  } > "$DIR/00-summary.md"
  {
    printf '# 결함 대장 (정본)\n\n'
    printf '**갱신** %s · **판정** 판정 불가 · **open BLOCKER** 0 · **open 전체** 0\n\n' "$DATE"
    printf '%s\n' "$LEDGER_HEAD"
  } > "$DIR/ledger.md"
  n_axes=0
  for i in $SEEN; do
    name=$(axis_name "$i")
    printf '# %02d %s\n\n**감사 모델** <예: fable/opus/sonnet> · **위임 도구** <이름 @버전 | 직접>\n\n<무엇을 어떻게 봤는지 · 발견은 대장으로>\n' "$i" "$name" > "$DIR/$(printf '%02d' "$i")-$name.md"
    n_axes=$((n_axes + 1))
  done
  echo "생성: $DIR (00-summary.md · ledger.md · 축 파일 $n_axes 개 · evidence/)"
  [ -n "$DROPPED" ] && echo "  뺀 축: $DROPPED_C — 「보지 않은 것 → 가. 의도적 제외」에 사유를 적어라"
fi

cat <<EOF

다음:
  1. 게이트 목표를 **착수 전에** 수치로 채운다 (결과를 보고 고치면 사후 승인이다)
  2. 발견을 대장에 즉시 적는다 — ID·심각도·근거등급·근거(파일:줄)
  3. bash "$(cd "$(dirname "$0")" && pwd)/ledger-lint.sh" <대상>
EOF
