#!/bin/bash
# ledger-lint — 결함 대장 기계 검증 (verifying-production-readiness)
#
# 존재 이유: 이 스킬의 핵심 규칙 「measured 아닌 근거로 출하 가능을 낼 수 없다」를
# 사람(또는 LLM)의 자기보고에만 맡기면 measured 를 지어내는 것을 막을 수 없다.
# 이 스크립트는 대장을 기계로 검사해 measurement theater 의 비용을 높인다 —
# 인용 파일의 존재·줄 번호 범위·비어 있지 않음(공백뿐 포함)까지 검사하지만
# **내용이 진짜 근거인지까지 검증하지는 못한다**.
# 그것은 사람/모델이 재진입 시 의심하는 몫이다(report-template 재진입 절차).
#
# [2026-08-23 감정 수정] 이 머리말은 오래 사실과 반대였다. 「measured 없이는 GO 를 못 낸다」를
# 기계로 검사한다고 적어 두고, R1~R7 어디에도 그 검사가 없었다 — 근거가 전부 `claimed` 인
# 대장에 「출하 가능」을 달아도 `✓ 대장 무결` 이 나왔다(적대적 실측으로 확인). 그 규칙은
# 이제 **R8** 이 실제로 검사한다. 함께 들어온 것:
#   · **R9** 게이트 표의 「실측」칸 검사 — 실측이 실제로 사는 곳인데 무검사였다.
#   · **인용 경로 해석에서 CWD 를 뺐다** — 같은 대장이 실행 위치에 따라 통과/100건 위반으로
#     갈렸다. 축 ⑨(결정성)를 코어로 잠근 스킬이 자기 검증기에서 비결정이면 안 된다.
#
# 사용: ledger-lint.sh <ledger.md 경로 | 리포트 디렉터리>
#   디렉터리를 주면 그 안의 ledger.md 를 검사한다. 경량 모드의 단일 readiness.md 도
#   파일 경로로 직접 주면 된다(표 형식만 같으면 검사된다).
#
# 규칙:
#   R1 `measured` 행은 근거·닫은증거 셀에 **실존 파일**(경로[:줄])을 하나 이상 인용해야
#      한다. `파일:줄` 형태면 그 줄 번호가 파일 길이 안에 있어야 유효 인용으로 친다.
#      없으면 claimed 강등 대상.
#      **인용 기준(고정·결정적)**: ① 리포트 디렉터리 ② 저장소 루트(git) ③ 절대경로.
#      **CWD 는 기준이 아니다** — 실행 위치가 판정을 바꾸면 그 판정은 재현되지 않는다.
#      대장이 **자기 자신**을 인용하는 것은 R1 에서는 유효다(대장 자신이 증거인 결함이
#      실재한다). 다만 R8 의 실측 근거로는 세지 않는다 — 자기참조는 관측이 아니다.
#   R2 `verified` 행(심각도 — 제외)은 「닫은 증거」가 비어 있으면 안 된다.
#   R3 ID 중복 금지.
#   R4 심각도(BLOCKER/HIGH/MED/LOW/—) · 상태(open/fixing/fixed/verified/rejected/deferred)
#      · 근거등급(claimed/code/measured) 은 정해진 어휘만.
#   R5 `rejected`/`deferred` 행은 사유(닫은 증거 칸)가 있어야 한다.
#   R6 판정 줄(**판정**/**Verdict**)과 **open BLOCKER** <수> 는 헤더 필수 — 없으면 위반
#      (조용히 건너뛰지 않는다). 헤더 수 = 표의 실제 open/fixing BLOCKER 수.
#      판정이 「출하 가능」/GO(조건부 아님)인데 open BLOCKER > 0 이면 위반.
#      판정 어휘는 고정: 출하 가능·조건부 출하 가능·출하 불가·판정 불가
#      (영문: GO·CONDITIONAL GO·NO-GO·UNVERIFIABLE). 마커 뒤 판정 텍스트만 잘라
#      고정 어휘 접두로 분류한다 — 부분 문자열 오인(본문의 「불가」·NOT GOOD 의 GO) 금지.
#   R7 `measured` 행이 인용한 증거 파일이 0바이트·공백뿐이거나, `파일:줄` 인용이 공백 줄을
#      가리키면 위반 — touch/echo 로 만든 껍데기 증거·죽은 줄 인용의 비용을 높인다.
#   R8 판정이 「출하 가능」(GO)이면 **실측 근거가 최소 하나** 있어야 한다 — 유효 인용을 가진 `measured` 대장 행, 또는 게이트 표 「실측」칸의
#      유효 인용. 전부 claimed/code 인 통과 판정은 **판정 불가(UNVERIFIABLE)** 로 강등하라.
#      이것이 이 스크립트의 간판 규칙이다(위 「존재 이유」).
#   R9 게이트 표에 「실측」(Measured) 열이 있으면, 각 행의 그 칸은 **수치 또는 유효 인용**을
#      담아야 한다. 비었거나 자리표시자(-, TBD, ?)면 위반이고, 수치도 인용도 없는 서술
#      (「팀이 통과했다고 함」·「아마 없을 것」)도 위반이다. 아직 안 쟀으면 숨기지 말고
#      `미실시`/`미측정`/`N/A` 라고 적어라 — 그 행은 R8 의 실측 근거로 세지 않는다.
#   R10 통과 계열 판정(출하 가능·조건부 출하 가능)은 **게이트 표 없이** 낼 수 없다.
#      Iron Rule 1 이 요구하는 「착수 전 확정한 수치」가 문서 어디에도 없으면, 그 통과는
#      기준 없이 난 것이다. 대장 파일 안의 게이트 표 또는 같은 디렉터리의 `gates.md`
#      /`00-summary.md`(정식 모드에서 게이트가 사는 곳) 중 하나면 충족된다.
#   R11 「조건부 출하 가능」은 **조건이 명시돼야** 한다. 조건부는 R8(실측 필수)의 탈출구라
#      조건을 적지 않으면 「무근거 통과」의 우회로가 된다. 조건 건수·목록이 보이는 줄
#      (「조건 N건」·「## 조건」·「출하 전 충족 조건」)이 하나도 없으면 위반이다.
#   R12 같은 디렉터리의 형제 리포트 파일(`00-summary.md`·`NN-*.md`·`gates.md`·
#      `fixes-round*.md`·다른 대장 파일)이 판정 줄을 가지고 있으면, 그 판정은 대장의 판정과
#      **같아야** 한다. 정식 모드는 사람이 읽는 판정이 요약 파일에 살아서, 요약만 「출하 가능」
#      으로 바꾸면 R6·R8·R10·R11 을 통째로 비켜 갈 수 있었다. 판정을 주장하는 파일은
#      **open BLOCKER 헤더 수치**도 대장과 맞아야 한다. 리포트 가족 밖의 문서(README·
#      progress 등)는 보지 않는다 — 남의 문서에서 판정 줄을 주우면 거짓 위반이 된다.
#   R13 `축:`/`뺀 축:` 선언이 있으면 그 선언이 정합해야 한다. **코어 축 ④⑥⑧⑨ 를 「뺀 축」에
#      넣을 수 없다**(볼 수 없었던 것은 「나. 확인 불가」다). 통과 계열 판정에서 뺀 축이
#      있으면 **사유**가 있어야 한다 — 「뺀 축: … — <사유>」 또는 「가. 의도적 제외」.
#      선언이 없는 리포트는 검사하지 않는다(없던 규약의 소급 적용은 거짓 위반이다).
#
# 옵션: --strict 는 증거 인용을 **리포트 디렉터리·저장소 루트 안**으로 제한한다(기본 아님 —
#      /var/log 같은 시스템 로그를 인용하는 정당한 감사를 막지 않기 위해서다).
#
# 한계: 경로에 공백이 있는 파일은 인식하지 못한다. 셀 안의 `\|`(마크다운 이스케이프)는
# 지원한다 — 날 '|' 는 여전히 셀 구분자로 읽힌다.
# 종료코드: 0=통과 · 1=위반 · 2=사용법/대상 없음
set -u

usage() {
  cat <<'EOF'
ledger-lint.sh — 결함 대장 기계 검증 (R1–R13)

사용:
  ledger-lint.sh [--strict] <ledger.md | readiness.md | 리포트 디렉터리>

  --strict   증거 인용을 리포트 디렉터리·저장소 루트 안으로 제한한다.
             (기본은 허용 — /var/log 같은 시스템 로그를 인용하는 정당한 감사가 있다)

핵심 규칙:
  R8  판정 「출하 가능(GO)」은 실측 근거 없이 낼 수 없다
  R9  게이트 표 「실측」칸은 수치 또는 유효 인용 (안 쟀으면 '미실시')
  R10 통과 계열 판정은 게이트 표 없이 낼 수 없다 (Iron Rule 1)
  R11 「조건부 출하 가능」은 조건이 명시돼야 한다
  R12 형제 리포트 파일(00-summary.md 등)의 판정이 대장과 갈리면 위반
  R13 축 선택 선언의 정합성 — 코어 축은 못 뺀다 · 뺀 축엔 사유
  전문은 README.md 「규칙 요약」.

인용 경로는 ①리포트 디렉터리 ②저장소 루트(git) ③절대경로 순으로만 찾는다 —
현재 작업 디렉터리는 기준이 아니다(어디서 돌려도 같은 판정).

종료코드: 0=통과 · 1=위반 · 2=사용법/대상 없음
EOF
}

# 필수 도구 선점검 — 없으면 **자기 탓을 자기가 말한다.** 예전에는 awk 가 없으면 모든 행이
# 안 잡혀 「대장 데이터 행이 없습니다(표 형식 확인)」로 끝났다. 도구가 깨졌는데 사용자의
# 표를 탓하는 메시지는, 이 스킬이 다른 곳에서 금지하는 「거짓 안내」와 같은 부류다.
for _c in awk grep sed mktemp; do
  command -v "$_c" >/dev/null 2>&1 || { echo "필수 도구가 없다: $_c — 이 환경에서는 검사할 수 없다(대장 문제가 아니다)"; exit 2; }
done

# 이 스크립트가 만드는 파일은 임시 사본뿐이고, 그 내용은 **아직 게시하지 않은 출하 검증
# 리포트 전문**(미공개 결함 포함)이다. mktemp 는 0600 을 보장하지만 파생 파일(.cond/.sum/.sib)
# 은 리다이렉트로 생성돼 umask 를 탄다 — 공유 /tmp(TMPDIR 미설정 CI·cron)에서 lint 실행
# 동안 월드 리더블이 됐다(자기감사 VPR-25). 전 산출물을 0600 으로 강제한다.
umask 077

# 인자 파싱은 순서 무관 + 미지 인자 거부(자기감사 VPR-22): 예전에는 $1 만 봐서
# `ledger-lint.sh <대상> --strict` 의 --strict 가 **조용히 무시**됐다 — vpr 도움말이
# 가르치는 순서가 정확히 그 형태였고, 사용자는 범위 제한이 적용된 줄 알고 게시한다.
# 통제가 소리 없이 꺼지는 것은 통제가 없는 것보다 나쁘다. 오타(--strcit)·쓰레기 인자도
# 수용하지 않는다 — 미지 입력은 fail-closed(exit 2).
STRICT=0; TARGET=""
for _arg in "$@"; do
  case "$_arg" in
    -h|--help) usage; exit 0 ;;
    --strict) STRICT=1 ;;
    -*) echo "알 수 없는 옵션: $_arg — 사용법은 --help"; exit 2 ;;
    *) if [ -n "$TARGET" ]; then
         echo "대상은 하나만 받는다: '$TARGET' 뒤에 '$_arg' — 사용법은 --help"; exit 2
       fi
       TARGET="$_arg" ;;
  esac
done
[ -n "$TARGET" ] || { usage; exit 2; }
# 디렉터리를 주면 정식 모드의 `ledger.md` → 경량 모드의 `readiness.md` 순으로 찾는다.
# 예전에는 ledger.md 만 봤다 — 그래서 퀵스타트가 안내하는 `vpr lint <프로젝트>` 가 경량
# 리포트에서 「대장 파일이 없습니다」로 죽었다(적대적 라운드 7에서 실측). 문서가 안내하는
# 경로가 도구에서 안 되는 것은 그 자체로 결함이다.
if [ -d "$TARGET" ]; then
  if [ -f "$TARGET/ledger.md" ]; then LEDGER="$TARGET/ledger.md"
  elif [ -f "$TARGET/readiness.md" ]; then LEDGER="$TARGET/readiness.md"
  else echo "대장 파일이 없습니다: $TARGET/{ledger.md,readiness.md} — 뼈대는 \`vpr new\` 로 만든다"; exit 2; fi
else LEDGER="$TARGET"; fi
[ -f "$LEDGER" ] || { echo "대장 파일이 없습니다: $LEDGER"; exit 2; }

# 심볼릭 링크로 준 대장은 **실체 위치**를 기준으로 삼는다. 링크가 놓인 자리를 기준으로
# 잡으면 `evidence/…` 인용이 통째로 어긋나 거짓 위반이 쏟아진다(라운드 7 실측).
_hops=0
while [ -L "$LEDGER" ] && [ "$_hops" -lt 8 ]; do
  _t=$(readlink "$LEDGER")
  case "$_t" in /*) LEDGER="$_t" ;; *) LEDGER="$(cd "$(dirname "$LEDGER")" && pwd)/$_t" ;; esac
  _hops=$((_hops + 1))
done
BASE=$(cd "$(dirname "$LEDGER")" && pwd -P)
# 저장소 루트 — 실제 대장의 지배적 인용 형태가 `core/src/hook.ts:385` 처럼 **루트 기준**이다.
# 이걸 기준에 넣지 않으면 사람들이 CWD 를 맞춰 실행하게 되고, 그 순간 판정이 실행 위치의
# 함수가 된다(그 상태를 실측으로 확인했다 — 같은 대장이 통과/100위반/102위반).
REPO_ROOT=$(git -C "$BASE" rev-parse --show-toplevel 2>/dev/null || true)
# 대상이 git 저장소가 아니면 저장소 루트 기준이 없어, 정식 모드 기본 배치
# (<대상>/docs/release-readiness/<날짜>/)에서 --strict 가 프로젝트 소스를 어떤 표기로도
# 인용할 수 없었다(자기감사 VPR-10). 이 배치는 new-report.sh 가 만드는 이 스킬 자신의
# 레이아웃이므로, git 이 없을 때는 그 상위(대상 루트)를 저장소 루트로 삼는다.
if [ -z "$REPO_ROOT" ]; then
  case "$BASE" in
    */docs/release-readiness/*) REPO_ROOT="${BASE%/docs/release-readiness/*}" ;;
  esac
fi
# --strict 물리 경계(자기감사 VPR-09): 렉시컬 `..` 차단만으로는 리포트 안 심볼릭 링크가
# 밖의 파일을 끌어온다. BASE 는 pwd -P 라 이미 물리 경로, REPO_ROOT 도 물리로 고정해 둔다.
RROOT_REAL=""
[ -n "$REPO_ROOT" ] && RROOT_REAL=$(cd "$REPO_ROOT" 2>/dev/null && pwd -P || true)
# 대장 파일의 절대 경로 — 자기 인용 판정은 여기에만 건다. 상대/절대 어느 쪽으로 호출해도
# 같은 판정이 나와야 한다(호출 형태가 판정을 바꾸면 그것도 비결정이다).
LEDGER_ABS="$BASE/$(basename "$LEDGER")"

# **코드펜스 안은 예시지 리포트가 아니다.** report-template.md 가 대장·게이트 골격을
# ```markdown 펜스로 보여 주므로, 그 골격을 인용한 리포트가 곧 「게이트 표가 있다」·
# 「조건이 적혀 있다」·「판정이 이것이다」로 계산됐다(적대적 라운드 6에서 실측).
# 그래서 문서 수준 판정(판정 줄·헤더 수·게이트 표·조건·대장 행)은 전부 **펜스를 걷어낸
# 사본**으로 한다. 인용 검사는 원본 경로를 쓰므로 영향이 없다.
strip_fences() {
  awk '/^[[:space:]]*(```|~~~)/ { f = !f; next } !f' "$1"
}
# 인터럽트에도 임시파일이 남지 않게: ① trap 을 **파일 생성 전에** 건다 ② 파생 파일
# (COND_SCAN·SUM_STRIP·SIB_STRIP)은 mktemp 를 다시 부르지 않고 **WORK 이름에서 파생**한다 —
# mktemp 의 「파일 생성 → 변수 대입」 사이 경합 창에서 TERM 이 오면 trap 이 빈 이름을
# 지우는 누수가 있었다(자기감사 VPR-19: 13/25 → VPR-23: SIB_STRIP 3/50 실측). 파생 이름은
# 대입이 생성보다 먼저라 창이 없다. WORK 자체의 mktemp 창 하나만 남는다(실측 0/50).
WORK=""; COND_SCAN=""; SUM_STRIP=""; SIB_STRIP=""
trap 'rm -f "$WORK" "$COND_SCAN" "$SUM_STRIP" "$SIB_STRIP"' EXIT
WORK=$(mktemp "${TMPDIR:-/tmp}/vprlint.XXXXXX") || exit 2
strip_fences "$LEDGER" > "$WORK"

VIOL=0
fail() { echo "✗ $1"; VIOL=$((VIOL + 1)); }

# 판정 줄 해석 — 대장과 형제 리포트 파일이 **같은 해석**을 쓰게 하려고 함수로 묶었다.
# 두 벌로 두면 한쪽만 고쳐져 「대장에선 GO, 형제에선 미인식」 같은 균열이 난다.
verdict_count() { grep -v '^|' "$1" | grep -cE '\*\*(판정|Verdict):?\*\*' || true; }
verdict_text() {
  grep -v '^|' "$1" | grep -m1 -E '\*\*(판정|Verdict):?\*\*' \
    | sed -E 's/.*\*\*(판정|Verdict):?\*\*[[:space:]]*//; s/[[:space:]]*·.*//; s/[[:space:]]+$//' \
    | sed -E 's/^[*_`[:space:]]+//; s/[*_`[:space:]]+$//'
}
# 판정 텍스트를 **부류**로 접는다. 「출하 가능」과 「GO」는 같은 판정이다 — 원문 문자열로만
# 비교하면 영문·한글을 섞어 쓴 리포트가 거짓 위반을 맞는다(라운드 17 실측).
verdict_class() {
  case "$1" in
    "조건부 출하 가능"*|"CONDITIONAL GO"*) echo COND ;;
    "출하 가능"*|"GO"|"GO "*|"GO("*)      echo GO ;;
    "출하 불가"*|"NO-GO"*)                 echo NOGO ;;
    "판정 불가"*|"UNVERIFIABLE"*)          echo UNVERIF ;;
    *)                                     echo OTHER ;;
  esac
}
# 강조·인용 표시를 벗기고 「·」 뒤를 자른다 — 판정 줄과 같은 정규화를 쓴다.
verdict_norm() {
  printf '%s' "$1" \
    | sed -E 's/^[>#*_`[:space:]]+//; s/[[:space:]]*·.*//; s/[*_`>[:space:]]+$//; s/[[:space:]]+$//'
}
# **마커 없는 판정**도 찾는다. report-template.md 의 `00-summary.md` 골격이 바로 그 형태다:
#   # 판정
#   > ## <출하 가능 | 조건부 출하 가능 | 출하 불가>
# 즉 **이 스킬이 스스로 권하는 요약 형식이 R12 의 사각지대였다**(라운드 17 실측). 표 행
# 「| 판정 | 출하 가능 |」도 같은 사각이다(대장 판정 줄 탐색이 표 행을 제외하므로).
# 다만 이 두 형태는 **고정 어휘로 분류될 때만** 판정으로 친다 — 절 아래 산문을 판정으로
# 오인하면 거짓 위반이 되고, 거짓 위반은 사람이 도구를 끄게 만든다.
verdict_unmarked() {   # $1 = 펜스 걷은 파일 → 분류 가능한 첫 후보의 원문(없으면 빈 줄)
  {
    awk '/^#+[ \t]*(판정|Verdict)[ \t]*:?[ \t]*$/ { f = 1; next }
         f && /^#/ { f = 0 }
         f && NF { print; n++; if (n >= 6) exit }' "$1"
    awk -F'|' '/^\|/ {
           k = $2; gsub(/^[ \t*_`]+|[ \t*_`]+$/, "", k)
           if (k == "판정" || k == "Verdict") { v = $3; gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit } }' "$1"
  } | while IFS= read -r cand; do
        case "$cand" in *"<"*|*"|"*) continue ;; esac   # 안 채운 골격의 자리표시자
        n=$(verdict_norm "$cand")
        [ "$(verdict_class "$n")" = OTHER ] && continue
        printf '%s' "$n"; break
      done
}
blocker_hdr() {
  grep -v '^|' "$1" | grep -oE '\*\*open BLOCKER\*\*:? *[0-9]+' | head -1 | grep -oE '[0-9]+$' || true
}
# 이 리포트에 속한 형제 파일인가 — 정식 모드의 파일 가족만 본다. 경량 모드의
# `readiness.md` 는 프로젝트 루트에 놓이므로, 가족을 좁히지 않으면 README·progress 같은
# 남의 문서에서 판정 줄을 주워 거짓 위반을 만든다(과차단은 결함과 같은 무게다).
is_report_sibling() {
  case "$(basename "$1")" in
    [0-9][0-9]-*.md|ledger.md|readiness.md|gates.md|fixes-round*.md) return 0 ;;
    *) return 1 ;;
  esac
}

# R8 — 통과 계열 판정은 실측 근거 없이 낼 수 없다.
# 이 스크립트가 존재하는 이유가 이 한 줄이었는데 오래 구현이 없었다(머리말 참조).
# 근거는 두 자리 중 어디에 있어도 된다: 대장의 measured 행(R1 통과) 또는 게이트 표 실측 칸.
# 세는 단위는 「유효 인용」이다 — 등급 글자만 measured 로 적는 것으로는 세지 않는다.
# R10 — 통과 계열 판정은 게이트 표 없이 낼 수 없다(Iron Rule 1: 게이트는 착수 전에 못 박는다).
# 정식 모드는 게이트가 형제 파일에 산다 — 그것도 인정한다. 목적은 「기준 없이 난 통과」를
# 막는 것이지 파일 배치를 강제하는 게 아니다(그러면 과차단이다).
require_gate_table() {
  [ "$GATE_TABLE" = 1 ] && return 0
  # 형제 파일 어디에 있어도 인정한다 — 게이트가 gates.md 에 있든 00-summary.md 나 축 파일에
  # 있든, 목적은 「기준이 문서에 있다」이지 파일명이 아니다(파일명을 강제하면 과차단이다).
  for sib in "$BASE"/*.md; do
    [ -f "$sib" ] || continue
    [ "$sib" = "$LEDGER_ABS" ] && continue
    has_gate_table <(strip_fences "$sib") && return 0
  done
  fail "R10 판정 '$VTXT' 인데 게이트 표가 없다 — 착수 전 확정한 임계값이 문서 어디에도 없으면 그 통과는 기준 없이 난 것이다(Iron Rule 1). 대장에 게이트 표를 넣거나 gates.md 를 함께 두어라"
}

require_measured() {
  [ $((MEASURED_OK + GATE_MEASURED)) -gt 0 ] && return 0
  fail "R8 판정 '출하 가능(GO)' 인데 실측 근거가 0건이다 — measured 대장 행(유효 인용)도, 게이트 표 실측 칸의 인용도 없다. 실측을 붙이거나 '판정 불가(UNVERIFIABLE)' 로 강등하라"
}

# 셀 텍스트에서 경로 후보를 뽑아 검사한다. 결과는 전역:
#   CIT_VALID  유효 인용 수 (실존 + 0바이트 아님 + 줄 번호가 범위 안·공백 줄 아님)
#   CIT_EMPTY  0바이트 인용 파일 목록 (R7)
#   CIT_BLANK  공백 줄을 가리키는 파일:줄 인용 목록 (R7)
scan_citations() {
  local tok t f ln
  CIT_VALID=0; CIT_EXT=0; CIT_EMPTY=""; CIT_BLANK=""; CIT_OUT=""
  # 백틱·쉼표·괄호를 공백으로 바꿔 토큰화한다.
  # set -f: 셀의 `*.log` 같은 와일드카드가 CWD 글로빙으로 무관한 실파일에 매칭되는 것을
  # 차단한다(그 자체가 measurement theater 우회 경로다).
  set -f
  for tok in $(printf '%s' "$1" | tr '`,()' '    '); do
    case "$tok" in *\**|*\?*|*\[*) continue ;; esac   # 와일드카드 토큰은 인용이 아니다
    t="${tok%%:*}"                          # 파일:줄 → 파일 (확장자 판정은 :줄 제거 후)
    case "$t" in
      */*|*.md|*.ts|*.js|*.py|*.sh|*.swift|*.log|*.png|*.jpg|*.txt|*.json|*.yml|*.yaml|*.csv|*.html|*.out|*.jsonl|*.har|*.xml|*.pdf|*.svg)
        f=""
        # --strict: `..` 세그먼트가 든 상대경로는 「리포트·저장소 안」이 아니다 — BASE 기준
        # 해석이 리포트 밖으로 탈출해 README 의 --strict 범위 규정이 안 걸리던 구멍
        # (자기감사 VPR-06: `../../../../etc/passwd:1` 이 유효 실측으로 계수됐다).
        # 같은 파일이 정말 저장소 안이면 저장소 루트 기준 상대경로로 다시 쓰면 된다.
        if [ "$STRICT" = 1 ]; then
          case "$t" in ..|../*|*/..|*/../*) CIT_OUT="$CIT_OUT $tok"; continue ;; esac
        fi
        # 기준 순서 고정: 리포트 디렉터리 → 저장소 루트 → 절대경로. CWD 는 쓰지 않는다.
        if [ -f "$BASE/$t" ]; then f="$BASE/$t"
        elif [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/$t" ]; then f="$REPO_ROOT/$t"
        else case "$t" in
               /*) # **실존하는 파일일 때만** 범위 밖 인용으로 취급한다. 예전에는 산문 속
                   # 맨 '/'(「A / B」) 같은 토큰까지 절대경로로 보고 --strict 에서 거짓
                   # 위반을 쏟아냈다(실물 대장에서 10건, 적대적 라운드 12에서 실측).
                   if [ -f "$t" ]; then
                     if [ "$STRICT" = 1 ]; then CIT_OUT="$CIT_OUT $tok"; else f="$t"; fi
                   fi ;;
             esac
        fi
        [ -n "$f" ] || continue
        # --strict: 인용 파일의 **물리 경로**가 리포트 디렉터리·저장소 루트 안이어야 한다.
        # 렉시컬 검사만으로는 evidence/ 안 심볼릭 링크(→ /etc/passwd)가 밖의 파일을 유효
        # measured 로 계수했다(자기감사 VPR-09). readlink -f 실패 시 렉시컬로 폴백.
        if [ "$STRICT" = 1 ]; then
          RP=$(readlink -f -- "$f" 2>/dev/null || printf '%s' "$f")
          IN=0
          case "$RP" in "$BASE"/*) IN=1 ;; esac
          [ -n "$RROOT_REAL" ] && case "$RP" in "$RROOT_REAL"/*) IN=1 ;; esac
          if [ "$IN" != 1 ]; then CIT_OUT="$CIT_OUT $tok"; continue; fi
        fi
        # 자기 인용(대장이 자기 자신을 가리킴)의 취급 — 두 갈래로 나눈다.
        #  · R1(인용 무결)에서는 **유효로 인정**한다. 대장 자신이 증거인 결함이 실재한다
        #    (예: 「lint 가 이 대장의 어떤 ID 를 건너뛴다」). 막으면 과차단이다 —
        #    실물 리포트에서 이 과차단을 실측하고 되돌렸다.
        #  · R8(GO 의 실측 근거)로는 **세지 않는다**. 「밖에서 관측했다」는 주장이 문서
        #    안에서 닫히면 그건 관측이 아니라 자기참조다. 그래서 CIT_EXT 를 따로 센다.
        SELFCITE=0
        case "$f" in "$LEDGER_ABS") SELFCITE=1 ;; esac
        if [ ! -s "$f" ] || ! grep -q '[^[:space:]]' "$f"; then
          CIT_EMPTY="$CIT_EMPTY $tok"; continue          # 0바이트·공백뿐 (R7)
        fi
        ln="${tok#"$t"}"; ln="${ln#:}"; ln="${ln%%:*}"   # :줄[:…] → 첫 줄 번호
        case "$ln" in
          ''|*[!0-9]*)                                  # 줄 없음·범위(12-20) — 존재로 유효
             CIT_VALID=$((CIT_VALID + 1))
             [ "$SELFCITE" = 1 ] || CIT_EXT=$((CIT_EXT + 1)) ;;
          *) # awk NR: 끝 개행 없는 마지막 줄도 센다(wc -l 은 과소계수). 자릿수 상한은
             # bash 산술 한계 보호 — 초과하면 유효 인용으로 치지 않는다(→ R1).
             if [ "${#ln}" -le 9 ] && [ "$ln" -ge 1 ] \
                && [ "$ln" -le "$(line_count "$f")" ]; then
               if sed -n "${ln}p" "$f" | grep -q '[^[:space:]]'; then
                 CIT_VALID=$((CIT_VALID + 1))
                 [ "$SELFCITE" = 1 ] || CIT_EXT=$((CIT_EXT + 1))
               else
                 CIT_BLANK="$CIT_BLANK $tok"
               fi
             fi ;;
        esac
        ;;
    esac
  done
  set +f
}

# 파일 줄 수 메모이제이션 — 같은 증거 파일이 대장 곳곳에서 인용되므로 awk 를 인용마다
# 띄우면 프로세스 수가 인용 수만큼 늘어난다. 캐시는 문자열 하나로 충분하다(bash 3.2 호환).
LC_CACHE="|"
line_count() {
  local key="|$1=" rest n
  case "$LC_CACHE" in
    *"$key"*) rest="${LC_CACHE#*"$key"}"; printf '%s' "${rest%%|*}"; return ;;
  esac
  n=$(awk 'END{print NR}' "$1")
  LC_CACHE="$LC_CACHE$1=$n|"
  printf '%s' "$n"
}

# 행 필드 추출: | ID | 심각도 | 축 | 한 줄 | 상태 | 근거등급 | 근거 | 닫은 증거 |
# 순수 bash 분할 — awk 를 행마다 6번 띄우면 153행 대장에서 900개 넘는 프로세스가 뜬다
# (실측: lint 한 번에 2.6초). 의미는 awk -F'|' 의 n 번째 필드와 같다: 맨 앞 '|' 앞의 빈 칸이 1.
field() {
  local IFS='|' i=$1 v raw
  local -a parts
  # 마크다운은 셀 안의 파이프를 `\|` 로 이스케이프한다. 그대로 쪼개면 한 셀이 두 개로
  # 갈려 그 뒤 열이 통째로 밀린다 — 정상 대장에 거짓 위반이 뜬다(실측으로 확인).
  # 분할 전에 센티넬로 치환하고 값에서 되돌린다.
  raw="${2//\\|/$'\001'}"
  read -r -a parts <<< "$raw"
  v="${parts[$((i - 1))]:-}"
  v="${v//$'\001'/|}"
  v="${v#"${v%%[![:space:]]*}"}"      # 앞 공백 제거
  v="${v%"${v##*[![:space:]]}"}"      # 뒤 공백 제거
  printf '%s' "$v"
}

SEEN_IDS=" "
OPEN_BLOCKERS=0
ROWS=0
MEASURED_OK=0     # 유효 인용을 가진 measured 대장 행 수 (R8 입력)
GATE_MEASURED=0   # 게이트 표 「실측」칸의 유효 인용 수 (R8 입력)

while IFS= read -r line; do
  case "$line" in "|"*) ;; *) continue ;; esac
  ID=$(field 2 "$line")
  # ID 패턴은 「대문자류-영숫자」다. 예전에는 `-` 뒤에 **숫자**만 인정해서 `SEC-A`·`UX-A1`
  # 같은 글자접미 ID 가 통째로 검사에서 빠졌다 — 그 행의 BLOCKER 는 세지도 않는다.
  # (실물 대장이 이 구멍을 QUAL-115 로 기록해 뒀는데 정작 lint 에는 남아 있었다.)
  # 「대문자로 시작하고 영숫자·하이픈만」 — 공백·괄호·한글이 섞이면 ID 가 아니라 산문이다.
  # 이 가드가 없으면 「TCC 권한 프롬프트 재출현(ad-hoc …)」 같은 다른 표의 칸이 ID 로 잡혀
  # 무관한 표가 대장으로 검사된다(실물 리포트에서 실측한 과차단).
  ID_RAW="$ID"                              # 메시지에는 사람이 실제로 쓴 값을 보여 준다
  case "$ID" in
    *[!A-Za-z0-9-]*) ID="" ;;               # ID 문자 집합 밖 → 데이터 행 아님
  esac
  case "$ID" in
    [A-Z]*-[A-Za-z0-9]*) ;;                 # 데이터 행
    *)
      # 헤더·구분선은 조용히 넘기되, **데이터 행처럼 생겼는데 ID 만 어긋난 행**은 잡는다.
      # 조용히 건너뛰면 그 행의 결함은 대장에 적혀 있는데 아무도 안 세는 상태가 된다.
      ST_C=$(field 6 "$line"); GR_C=$(field 7 "$line")
      case "$ST_C" in
        open|fixing|fixed|verified|rejected|deferred)
          fail "R3 ID 형식이 아니다('$ID_RAW') — 이 행은 모든 검사에서 빠진다(BLOCKER 도 안 세어진다). 영문 대문자·숫자·하이픈만 쓴 'SEC-01'·'UX-A1' 형태로 적어라" ;;
        *) case "$GR_C" in
             claimed|code|measured)
               fail "R3 ID 형식이 아니다('$ID_RAW') — 이 행은 모든 검사에서 빠진다. 영문 대문자·숫자·하이픈만 쓴 'SEC-01'·'UX-A1' 형태로 적어라" ;;
           esac ;;
      esac
      continue ;;
  esac
  ROWS=$((ROWS + 1))
  SEV=$(field 3 "$line"); ST=$(field 6 "$line")
  GRADE=$(field 7 "$line"); EV=$(field 8 "$line"); CLOSE=$(field 9 "$line")

  # R3 — ID 중복
  case "$SEEN_IDS" in
    *" $ID "*) fail "R3 [$ID] ID 중복 — 한 번 부여한 ID 는 재사용 금지" ;;
    *) SEEN_IDS="$SEEN_IDS$ID " ;;
  esac

  # R4 — 어휘
  case "$SEV" in BLOCKER|HIGH|MED|LOW|—|-) ;; *) fail "R4 [$ID] 심각도 어휘 위반: '$SEV'" ;; esac
  case "$ST" in open|fixing|fixed|verified|rejected|deferred) ;; *) fail "R4 [$ID] 상태 어휘 위반: '$ST'" ;; esac
  case "$GRADE" in claimed|code|measured) ;; *) fail "R4 [$ID] 근거등급 어휘 위반: '$GRADE'" ;; esac

  # R1 — measured 는 실존 파일(유효 줄 번호) 인용 필수
  # R7 — 인용한 증거가 0바이트 파일이거나 공백 줄이면 위반 (measurement theater 비용 상승)
  if [ "$GRADE" = "measured" ]; then
    scan_citations "$EV $CLOSE"
    # CIT_OUT 이 있으면 「부재」가 아니라 「범위 밖」이다 — 실존하는 파일을 「파일 부재」로
    # 오발화하면 사용자가 엉뚱한 원인을 쫓는다(자기감사 VPR-16). strict 메시지가 정본.
    if [ "$CIT_VALID" -eq 0 ] && [ -z "$CIT_EMPTY" ] && [ -z "$CIT_BLANK" ] && [ -z "${CIT_OUT:-}" ]; then
      fail "R1 [$ID] measured 인데 유효한 파일 근거가 없다(파일 부재 또는 줄 번호가 파일 길이 초과) — claimed 로 강등하거나 evidence 를 남겨라"
    fi
    [ "$CIT_EXT" -eq 0 ] || MEASURED_OK=$((MEASURED_OK + 1))   # R8 은 외부 증거만 센다
    [ -z "$CIT_EMPTY" ] || fail "R7 [$ID] 인용 증거 파일이 비어 있다(0바이트 또는 공백뿐):$CIT_EMPTY — 실측 출력을 파일에 남겨라"
    [ -z "$CIT_BLANK" ] || fail "R7 [$ID] 파일:줄 인용이 공백 줄을 가리킨다:$CIT_BLANK — 실제 근거 줄을 인용하라"
    [ -z "${CIT_OUT:-}" ] || fail "R1 [$ID] --strict: 리포트·저장소 밖 인용:$CIT_OUT — 증거를 evidence/ 로 복사하거나 저장소 루트 기준 상대경로로 적어라(대상이 git 저장소가 아니고 정식 배치도 아니면 저장소 기준을 세울 수 없다)"
  fi

  # R2 — verified 는 닫은 증거 필수 (문제없음 행(심각도 —)은 예외)
  if [ "$ST" = "verified" ] && [ "$SEV" != "—" ] && [ "$SEV" != "-" ]; then
    case "$CLOSE" in ""|—|-) fail "R2 [$ID] verified 인데 '닫은 증거'가 비어 있다" ;; esac
  fi

  # R5 — rejected/deferred 는 사유 필수
  if [ "$ST" = "rejected" ] || [ "$ST" = "deferred" ]; then
    case "$CLOSE" in ""|—|-) fail "R5 [$ID] $ST 인데 사유(닫은 증거 칸)가 없다" ;; esac
  fi

  # R6 집계 — open BLOCKER
  if [ "$SEV" = "BLOCKER" ] && { [ "$ST" = "open" ] || [ "$ST" = "fixing" ]; }; then
    OPEN_BLOCKERS=$((OPEN_BLOCKERS + 1))
  fi
done < "$WORK"

# 데이터 행이 0인데 위반이 잡혀 있으면, 그건 「표가 없다」가 아니라 「행이 전부 어긋났다」다.
# 그때 exit 2 로 빠지면 방금 잡은 R3 위반이 통째로 버려지고 사람은 원인을 못 본다
# (자체 테스트가 이 실수를 잡았다 — 위반을 삼키는 경로는 조용해서 더 위험하다).
if [ "$ROWS" -eq 0 ]; then
  if [ "$VIOL" -gt 0 ]; then
    echo "— $VIOL 건 위반. 유효한 대장 행이 하나도 없다 — 위 지적을 먼저 고쳐라."
    exit 1
  fi
  # 행 0 은 그 자체로 오류가 아니다 — 결함 0건의 청정 감사(정상 결과)일 수도, 갓 만든
  # 뼈대(판정 불가)일 수도 있다. 어느 쪽인지는 아래 판정급 규칙이 가른다: GO 면 R8 이
  # 실측을 요구하고, 판정 불가면 부담이 없다. 예전에는 여기서 exit 2 로 조기 종료했는데
  # 그러면 R8·R10·R11·R13 이 한 줄도 실행되지 않아 「GO + 빈 대장」이 lint 를 통과하고
  # 렌더 게이트(exit 1 만 차단)까지 지나 게시됐다 — 자기감사 VPR-01(BLOCKER) 실측.
  # 같은 유형(판정 전 조기 이탈)의 세 번째 발생이었다. 여기서는 계속 진행한다.
  :
fi

# ── R9 — 게이트 표의 「실측」칸 ─────────────────────────────────────
# 왜 여기가 필요한가: 실측은 대장이 아니라 **게이트 표**에 사는 경우가 많다(경량 모드가 특히
# 그렇다). 그 칸을 아무도 안 보면 「팀이 다 통과했다고 함」이 실측 자리에 앉아도 통과다.
# 실제 리포트에서 그 상태를 확인했다 — 대장은 code 2행뿐인데 lint 는 초록이었다.
# 과차단 방지: 「실측」 열이 없는 표(목표만 선확정한 게이트 표)는 검사 대상이 아니다.
# 헤더 판정은 **구분선(|---|)이 바로 뒤따르는 줄**로만 한다. 이 가드가 없으면 대장 데이터
# 행의 근거등급 셀('measured')을 헤더로 오인해 대장 자신을 게이트 표로 검사한다
# (자체 테스트가 이 실수를 잡았다 — 과차단은 결함과 같은 무게다).
IN_GATE=0; MCOL=""; CAND_COL=""; GATE_TABLE=0
# 파일에 「실측/Measured」가 한 번도 없으면 게이트 표가 없다 — 순회할 이유가 없다.
# 게이트 표가 문서 어딘가에 있는가(R10). 「게이트/Gate」가 **어느 열**에 있어도 되지만,
# **구분선이 뒤따르는 머리말 행**이어야 한다 — 본문에서 「게이트」를 언급한 데이터 행이
# 게이트 표 행세를 하면 R10 이 무력해진다(실측: NFD 리포트는 게이트가 3번째 열이었다).
has_gate_table() {
  # 머리말(게이트 열) → 구분선 → **데이터 행 최소 1개**. 빈 표는 게이트 표가 아니다 —
  # 「| 게이트 | 목표 |」 두 줄만 붙여 R10 을 만족시키는 우회를 적대적 실측에서 발견했다.
  #
  # 판별식은 **R9 와 같아야 한다.** 예전에는 여기만 머리말에 「게이트」라는 글자를 요구해서
  # `| 기준 | 임계값 | 실측 |` 같은 표를 R8·R9 는 게이트 표로 세는데 R10 만 「게이트 표가
  # 없다」고 했다(감정 F2 실측 — 두 파일의 diff 가 한 단어였다). 같은 표를 두고 규칙끼리
  # 반대로 말하면 사람은 도구를 끄고, 끈 도구의 방어력은 0이다. 그래서 어휘 의존을 버리고
  # R9 와 같은 조건을 함께 쓴다: 「실측/Measured」로 **시작하는 열**이 있고 · 대장 표가 아니다.
  awk 'state == 1 && /^\|/ && $0 !~ /^\|[ |:-]+$/ { found = 1; exit }
       state == 1 { state = 0 }
       prev ~ /^\|/ && /^\|[ |:-]+$/ &&
         (prev ~ /게이트|Gate/ ||
          (prev ~ /(^|\|)[ \t]*(실측|[Mm]easured)/ && prev !~ /근거등급|닫은 증거/)) { state = 1 }
       { prev = $0 }
       END { exit found ? 0 : 1 }' "$1"
}
has_gate_table "$WORK" && GATE_TABLE=1
if grep -q '실측\|[Mm]easured' "$WORK"; then
while IFS= read -r line; do
  case "$line" in
    "|"*)
      # 구분선은 **오직 |, -, :, 공백만** 있는 줄이다. 느슨하게 '---' 포함으로 보면
      # 본문에 '---' 가 든 데이터 행이 구분선 행세를 해 엉뚱한 표가 열린다(실측으로 확인).
      SEPTEST="${line//[|:-]/}"; SEPTEST="${SEPTEST// /}"; SEPTEST="${SEPTEST//	/}"
      if [ -z "$SEPTEST" ]; then
        if [ -n "$CAND_COL" ]; then MCOL="$CAND_COL"; IN_GATE=1; fi
        CAND_COL=""; continue
      fi
      if [ "$IN_GATE" -eq 0 ]; then
        # 후보 헤더 조건: ① 셀이 '실측/Measured' 로 **시작**하고(설명문 안의 단어 배제)
        # ② 대장 표 자신이 아니다(근거등급·닫은 증거 열이 있으면 대장이다).
        CAND_COL=""
        case "$line" in
          *근거등급*|*"닫은 증거"*) ;;
          *실측*|*Measured*|*measured*)
            CAND_COL=$(printf '%s' "$line" | awk -F'|' '{for(i=1;i<=NF;i++){gsub(/^[ \t]+|[ \t]+$/,"",$i); if($i ~ /^(실측|[Mm]easured)/){print i; exit}}}') ;;
        esac
      else
        GCELL=$(field "$MCOL" "$line")
        GID=$(field 2 "$line")
        case "$GCELL" in
          ""|-|—|TBD|tbd|\?)
            fail "R9 [게이트 ${GID:-?}] 실측 칸이 비었다('$GCELL') — 아직 안 쟀으면 '미실시' 라고 적어라(그 행은 실측 근거로 세지 않는다)" ;;
          *미실시*|*미측정*|*N/A*|*해당없음*) ;;       # 정직한 미실시 — 위반 아님, 근거로도 안 셈
          *)
            scan_citations "$GCELL"
            if [ "$CIT_EXT" -gt 0 ]; then
              GATE_MEASURED=$((GATE_MEASURED + 1))
            elif ! printf '%s' "$GCELL" | grep -q '[0-9]'; then
              fail "R9 [게이트 ${GID:-?}] 실측 칸에 수치도 유효 인용도 없다('$GCELL') — 서술형 실측(「동일」·「통과」)은 인용을 붙여라: 예) 동일 (evidence/diff.log:1)"
            fi ;;
        esac
      fi ;;
    *) IN_GATE=0; MCOL=""; CAND_COL="" ;;   # GATE_TABLE 은 파일 단위 사실이라 초기화하지 않는다
  esac
done < "$WORK"
fi

# R6 — 헤더 정합·판정 어휘. 판정 줄과 open BLOCKER 카운트는 헤더 필수다 — 없으면
# 검사를 조용히 건너뛰는 게 아니라 위반이다. 데이터 행(| 시작)은 헤더 탐색에서 제외해
# 「한 줄」 셀의 **판정** 문자열을 헤더로 오인하지 않는다.
# 판정 줄·헤더가 **여럿이면 어느 것이 정본인지 기계가 고를 수 없다.** 예전에는 첫 줄만
# 봤는데, 그러면 무해한 「판정 불가」를 앞에 두고 아래에 진짜 「출하 가능」을 적는 것만으로
# R8·R10 검사를 통째로 비켜 갈 수 있었다(적대적 라운드 6에서 실측). 고르지 말고 거부한다.
VERDICT_N=$(verdict_count "$WORK")
HDRBLK_N=$(grep -v '^|' "$WORK" | grep -cE '\*\*open BLOCKER\*\*' || true)
[ "${VERDICT_N:-0}" -le 1 ] || fail "R6 판정 줄이 $VERDICT_N 개다 — 어느 것이 정본인지 기계가 고를 수 없다. 하나만 남겨라(낡은 판정은 지우거나 이력 절로 옮겨라)"
[ "${HDRBLK_N:-0}" -le 1 ] || fail "R6 **open BLOCKER** 헤더가 $HDRBLK_N 개다 — 하나만 남겨라"

HDR_BLK=$(blocker_hdr "$WORK")
if [ -z "$HDR_BLK" ]; then
  fail "R6 헤더에 **open BLOCKER** <수> 가 없다 — 대장 헤더 형식(report-template.md)을 지켜라"
elif [ "$HDR_BLK" != "$OPEN_BLOCKERS" ]; then
  fail "R6 헤더 open BLOCKER($HDR_BLK) ≠ 표 실제($OPEN_BLOCKERS)"
fi
VERDICT_LINE=$(grep -v '^|' "$WORK" | grep -m1 -E '\*\*(판정|Verdict):?\*\*' || true)
if [ -z "$VERDICT_LINE" ]; then
  fail "R6 판정 줄(**판정**/**Verdict**)이 없다 — 판정 없는 대장은 이어받을 수 없다"
else
  # 마커 뒤 판정 텍스트만 잘라(다음 「·」 전까지) 고정 어휘 **접두**로만 분류한다.
  # 부분 문자열 매칭 금지 — 판정문 본문의 「불가」가 NO-GO 로 새서 GO 게이트를 무력화하거나
  # NOT GOOD 의 GO 가 GO 로 새는 것을 막는다. 어휘 밖 판정은 위반(R4 와 같은 원칙).
  # 마커 뒤 판정 텍스트만 자르고, **굵게·기울임·백틱 같은 강조 표시는 벗겨서** 비교한다.
  # 「**판정** **출하 가능**」은 사람이 흔히 쓰는 형식인데 어휘 미인식으로 막혔다(라운드 12).
  VTXT=$(verdict_text "$WORK")
  case "$VTXT" in
    "조건부 출하 가능"*|"CONDITIONAL GO"*)                 # 실측 불가 시의 정직한 탈출구(SKILL.md) — R8 비적용
      require_gate_table
      # R11 — 조건부는 조건이 적혀야 한다. 조건 없는 조건부는 R8 을 비켜 가는 무근거 통과다.
      # 「조건 0건」은 조건 명시가 아니라 **자기모순**이다 — 조건이 없으면 그냥 「출하 가능」
      # 이거나(그러면 R8 이 실측을 요구한다) 「판정 불가」다. 이 문법 모순을 잡는 것이
      # 조건부를 R8 의 우회로로 쓰지 못하게 하는 마지막 고리다.
      # R11 조건 탐색(자기감사 VPR-07·08·12~15·17 누적 수정):
      # · 범위(VPR-12): 템플릿은 조건을 00-summary.md 에 적으라고 가르친다 — R10 이 게이트
      #   표를 「형제 파일이든 무방」으로 보는 것과 같은 이유로, 대장 + 형제 리포트 가족
      #   전체에서 찾는다(펜스 제외). 정식 모드 조건부가 구조적으로 lint 불통이던 원인.
      # · 헤딩(VPR-08): H2 이하만 조건 절 후보 — H1 문서 제목 「# 조건부 …」 오발화 차단.
      #   인용부호(> ) 는 벗겨서 본다(VPR-15 — 템플릿 요약 골격이 인용부호를 쓴다).
      #   「조건부」·「무조건」을 지운 뒤에도 「조건」이 남아야 조건 절이다(VPR-17).
      # · 내용(VPR-13·14): 조건 절 안의 비어 있지 않은 줄이면 표기(목록·표·①②·산문)를
      #   가리지 않는다 — 진짜 조건 헤딩 아래라면 형식이 아니라 존재가 중요하다.
      #   이 검사는 렉시컬이다(내용의 진위·실행 가능성은 재진입 세션의 몫 — README 한계 절).
      COND_SCAN="$WORK.cond"
      cat "$WORK" > "$COND_SCAN"
      for csib in "$BASE"/*.md; do
        [ -f "$csib" ] || continue
        [ "$csib" = "$LEDGER_ABS" ] && continue
        is_report_sibling "$csib" || continue
        strip_fences "$csib" >> "$COND_SCAN"
      done
      # 「조건 0건」 자기모순 검사의 범위는 **판정을 지는 파일**(대장 + 00-summary.md)로
      # 좁힌다 — 형제 가족 전체로 넓히면 축 파일의 「임계값 미충족 조건 0건」·수정 라운드
      # 이력의 「남은 조건 0」 같은 무관 문구가 조건을 정확히 명시한 정당한 리포트를
      # 차단한다(자기감사 VPR-18 과차단 실측). 존재 검사(아래)는 가족 전체가 맞다 —
      # 템플릿이 조건을 요약에 적으라고 가르치기 때문이다(VPR-12).
      # 모순 검사 범위 = **게시물에 실리는 마크다운 전부** — 선택된 대장 + 00-summary.md +
      # readiness.md(대장과 별개로 공존할 때). 예전에는 대장·요약만 봐서, ledger.md 와
      # readiness.md 가 공존하는 디렉터리에서 readiness.md 의 「남은 조건 0건」이 검사는
      # 비켜 가고 렌더에는 실렸다(자기감사 VPR-26 실측 — 문서의 「= 게시 범위」 등식이
      # 거짓이 되는 반례). 게시되는 파일은 전부 검사한다.
      # 모순 스캔의 오발화 방지(자기감사 VPR-27 과차단): ① 표 행은 뺀다 — 대장·게이트 표
      # 셀의 「재현 조건: 없음」은 출하 조건에 대한 주장이 아니다(판정줄 스캔 :grep -v '^|'
      # 과 같은 규약). ② 이력 절(## 이력/History)은 뺀다 — 「남은 조건 0건 이었다」는 과거
      # 서술이다. ③ 「조건」 앞에 낱말 경계(행머리/공백)를 요구한다 — 「전제조건 0건」류
      # 합성어 차단. 제외 줄은 지우지 않고 비워 줄 번호를 보존한다(위치 표기용).
      # 낱말 경계는 「합성어(앞이 한글 음절)만 배제」다 — 행머리·공백 외에 강조·인용·괄호
      # 기호(**·「」·`·(·탭·_ 등)도 정당한 접두다. 예전 (^| ) 경계는 「**조건 0건**」 같은
      # 흔한 마크다운 표기의 진짜 모순 7형을 놓쳤다(자기감사 VPR-28 HIGH — v0.14.0 대비 회귀,
      # 게시까지 도달 실측). 다국어 인용부호는 바이트 브래킷에 못 넣으므로 대안으로 나열한다.
      CB="(^|[[:space:]]|[]*_~<>#=+.,;:!?/\\\\(\"'\`[-]|「|『|“|‘|»|·)"
      # 「조건: 없음」 분기는 조건과 콜론 **사이**의 강조 기호·괄호 주석도 허용해야 한다 —
      # 템플릿이 가르치는 표기 「**남은 조건**(조건부일 때만): 없음」이 이 틈으로 통과해
      # 조건 0건짜리 조건부 GO 가 게시까지 도달했다(자기감사 VPR-29 HIGH, 3버전 잠복).
      # 존재 검사(아래 인라인 grep)가 굵게 표기를 인정하는 것과 대칭이어야 한다.
      CONTRA_PAT="${CB}조건[^0-9]{0,8}0[ ]*건|${CB}조건[]*_\`」』\"'[-]*( *\\([^)]*\\))? *: *(해당 *)?없음|남은 조건 *0|[Nn]o conditions|${CB}0 conditions"
      contra_filter() {
        awk '/^#/ { hist = ($0 ~ /이력|[Hh]istory/) ? 1 : 0 }
             hist || /^\|/ { print ""; next }
             { print }' "$1"
      }
      CONTRA=$(contra_filter "$WORK" | grep -nE "$CONTRA_PAT" | head -1 | sed 's|^|대장 |')
      for cfile in 00-summary.md readiness.md ledger.md; do
        [ -n "$CONTRA" ] && break
        [ -f "$BASE/$cfile" ] || continue
        [ "$BASE/$cfile" = "$LEDGER_ABS" ] && continue
        SUM_STRIP="$WORK.sum"
        strip_fences "$BASE/$cfile" > "$SUM_STRIP"
        CONTRA=$(contra_filter "$SUM_STRIP" | grep -nE "$CONTRA_PAT" | head -1 | sed "s|^|$cfile:|")
      done
      if [ -n "$CONTRA" ]; then
        fail "R11 판정 '조건부 출하 가능' 인데 조건이 0건이라고 적혀 있다($CONTRA) — 조건이 없으면 '출하 가능'(실측 필요) 이거나 '판정 불가' 다. 문법 모순"
      elif ! { grep -qE '조건[^0-9]{0,8}[1-9][0-9]*[ ]*건|[1-9][0-9]* *conditions?' "$COND_SCAN" \
               || grep -qE '\*\*남은 *조건\*\*[^:|]*:[[:space:]]*[^[:space:]]' "$COND_SCAN" \
               || awk '{ line = $0; sub(/^(> ?)+/, "", line) }
                       line ~ /^##/ { t = line; gsub(/조건부|무조건/, "", t)
                                      f = (t ~ /조건|[Cc]onditions?/) ? 1 : 0; next }
                       line ~ /^#/ { f = 0; next }
                       f && line ~ /[^ \t]/ { found = 1; exit }
                       END { exit found ? 0 : 1 }' "$COND_SCAN"; }; then
        fail "R11 판정 '조건부 출하 가능' 인데 조건이 대장·형제 리포트 어디에도 명시돼 있지 않다 — 「조건 N건」, 「**남은 조건**: …」, 또는 「## 조건」류 헤딩 아래 내용으로, 누가·무엇을·어떻게 확인하면 풀리는지 적어라(적을 수 없으면 '판정 불가')"
      fi
      rm -f "$COND_SCAN" ;;
    "출하 불가"*|"판정 불가"*|"NO-GO"*|"UNVERIFIABLE"*) ;;       # 공존 가능
    "출하 가능"*|"GO"|"GO "*|"GO("*)
      [ "$OPEN_BLOCKERS" -eq 0 ] || fail "R6 판정 '출하 가능(GO)' 인데 open BLOCKER $OPEN_BLOCKERS 건"
      require_measured; require_gate_table ;;
    *) fail "R6 판정 어휘 인식 불가('$VTXT') — 고정 어휘만: 출하 가능·조건부 출하 가능·출하 불가·판정 불가 (영문 GO·CONDITIONAL GO·NO-GO·UNVERIFIABLE)" ;;
  esac
fi

# R12 — 형제 리포트 파일의 판정도 대장과 같아야 한다.
# 정식 모드에서 **사람이 읽는 판정은 `00-summary.md` 에 사는데 lint 는 대장 하나만 봤다.**
# 그래서 요약에 「출하 가능」을 적고 대장은 「판정 불가 · open BLOCKER 1」로 둔 리포트가
# R6·R8·R10·R11 을 통째로 비켜 `exit 0` 으로 렌더·게시까지 통과했다 — 게시된 HTML 머리에는
# 「출하 가능 · BLOCKER 0」, 바로 아래 표에는 열린 BLOCKER 가 찍힌 채로(감정 F1 실측).
# 이 스킬이 존재하는 이유가 정확히 그 한 장면이다. 판정이 갈리면 어느 쪽이 정본인지 기계가
# 고를 수 없으므로 — R6 이 대장 안에서 하는 것과 같은 이유로 — 고르지 말고 거부한다.
# 판정을 주장하는 파일은 그 판정의 **헤더 수치(open BLOCKER)** 도 대장과 맞아야 한다.
if [ -n "${VTXT:-}" ]; then
  LCLASS=$(verdict_class "$VTXT")
  for sib in "$BASE"/*.md; do
    [ -f "$sib" ] || continue
    [ "$sib" = "$LEDGER_ABS" ] && continue
    is_report_sibling "$sib" || continue
    # 값싼 선별 먼저 — 판정 마커가 아예 없는 파일(축 파일 대부분)에 mktemp·awk·grep 여섯 개를
    # 붙이면 정식 모드 lint 가 2.5배 느려진다(실측). 펜스 안 예시만 있는 파일은 이 선별을
    # 통과해도 아래 strip_fences 사본에서 0건으로 걸러진다 — 선별은 상위집합이라 안전하다.
    grep -qE '\*\*(판정|Verdict):?\*\*|^#+[[:space:]]*(판정|Verdict)[[:space:]]*:?[[:space:]]*$|^\|[[:space:]*_`]*(판정|Verdict)[[:space:]*_`]*\|' "$sib" || continue
    SIB_STRIP="$WORK.sib"
    strip_fences "$sib" > "$SIB_STRIP"
    SBN=$(basename "$sib")
    SVN=$(verdict_count "$SIB_STRIP")
    SVT=""
    if [ "${SVN:-0}" -gt 1 ]; then
      fail "R12 [$SBN] 판정 줄이 $SVN 개다 — 어느 것이 정본인지 기계가 고를 수 없다. 하나만 남겨라(낡은 판정은 **판정** 마커를 떼고 이력 절로 옮겨라)"
    elif [ "${SVN:-0}" -eq 1 ]; then
      SVT=$(verdict_text "$SIB_STRIP")
    else
      SVT=$(verdict_unmarked "$SIB_STRIP")
    fi
    if [ -n "$SVT" ]; then
      SCLASS=$(verdict_class "$SVT")
      if [ "$SCLASS" != "$LCLASS" ] || { [ "$SCLASS" = OTHER ] && [ "$SVT" != "$VTXT" ]; }; then
        fail "R12 [$SBN] 판정 '$SVT' 이 대장의 판정 '$VTXT' 과 다르다 — 사람은 요약을 읽고 기계는 대장을 읽으므로, 갈리면 검사받지 않은 판정이 게시된다. 둘을 일치시키거나 낡은 쪽에서 판정 표기를 떼라"
      fi
      SHB=$(blocker_hdr "$SIB_STRIP")
      if [ -n "$SHB" ] && [ "$SHB" != "$OPEN_BLOCKERS" ]; then
        fail "R12 [$SBN] 헤더 open BLOCKER($SHB) ≠ 대장 실제($OPEN_BLOCKERS) — 판정을 주장하는 파일은 그 판정의 수치도 대장과 같아야 한다"
      fi
    fi
    rm -f "$SIB_STRIP"
  done
fi

# R13 — 축 선택 선언의 정합성.
# 「어떤 축을 봤나」는 판정의 범위다. 「출하 가능」은 **본 축에 한한** 판정인데, 뺀 축이
# 사유 없이 사라지면 다음 사람은 그것을 「봤는데 괜찮았다」로 읽는다. 그리고 코어
# ④⑥⑧⑨ 는 사용자도 뺄 수 없다 — 볼 수 **없었던** 것은 「빼는 것」이 아니라
# 「나. 확인 불가」다(둘을 섞으면 근거 부재가 결함으로 둔갑한다).
# 선언이 아예 없는 리포트는 검사하지 않는다 — 없던 규약을 소급 적용하면 멀쩡한 옛
# 리포트가 거짓 위반을 맞는다. 선언은 `vpr new --axes` 가 만들어 준다.
AXIS_DECL=$(grep -v '^|' "$WORK" | grep -m1 -E '축:|Axes:' || true)
if [ -n "$AXIS_DECL" ]; then
  DROP_PART=$(printf '%s' "$AXIS_DECL" | sed -E 's/.*(뺀 축|뺀축|제외 축|제외축|Excluded):[[:space:]]*//')
  case "$AXIS_DECL" in
    *"뺀 축:"*|*"뺀축:"*|*"제외 축:"*|*"제외축:"*|*"Excluded:"*) ;;
    *) DROP_PART="" ;;
  esac
  # 축 부분과 사유 부분을 가른다. **구분자를 하나로 못 박지 않는다** — 사람이 「— 사유」도
  # 「- 사유」도 「(사유)」도 쓴다. 앞쪽의 축 토큰·구분자만 떼어 내고 **남은 것이 있으면
  # 사유가 있는 것**으로 본다(구분자를 못 박았더니 붙임표·괄호 사유가 거짓 위반이었다).
  AXPART=$(printf '%s' "$DROP_PART" | sed -E 's/^([①②③④⑤⑥⑦⑧⑨⑩⑪0-9,;·、[:space:]]*).*/\1/')
  REASON_PART=$(printf '%s' "${DROP_PART#"$AXPART"}" | sed -E 's/^[—–:：()[:space:]-]+//; s/[[:space:]]+$//')
  # 코어 축은 **원문자로도 숫자로도** 잡는다 — `--axes` 가 숫자를 받으므로 사람도 숫자로 적는다.
  CORE_HIT=""
  for c in ④ ⑥ ⑧ ⑨; do
    case "$AXPART" in *"$c"*) CORE_HIT="$CORE_HIT $c" ;; esac
  done
  for tok in $(printf '%s' "$AXPART" | tr ',;·、' '    '); do
    case "$tok" in
      4) CORE_HIT="$CORE_HIT ④" ;; 6) CORE_HIT="$CORE_HIT ⑥" ;;
      8) CORE_HIT="$CORE_HIT ⑧" ;; 9) CORE_HIT="$CORE_HIT ⑨" ;;
    esac
  done
  [ -n "$CORE_HIT" ] && fail "R13 코어 축${CORE_HIT} 를 「뺀 축」에 넣었다 — 코어 ④사용성·E2E ⑥보안 ⑧논리 ⑨결정성 은 사용자도 뺄 수 없다. 볼 수 없었던 것이면 「빼는 것」이 아니라 「보지 않은 것 → 나. 확인 불가」다"
  # 뺀 축이 있는데 사유가 없다 — 통과 계열 판정에서만 위반으로 본다(R10·R11 과 같은 원칙:
  # 통과에는 근거가 필요하고, NO-GO·판정 불가는 그 부담을 지지 않는다).
  case "$(verdict_class "${VTXT:-}")" in
    GO|COND)
      case "$DROP_PART" in
        ""|*"<"*) ;;                                  # 선언 없음 · 아직 안 채운 자리표시자
        *)
          HAS_AX=0
          case "$AXPART" in *[①②③④⑤⑥⑦⑧⑨⑩⑪]*|*[0-9]*) HAS_AX=1 ;; esac
          if [ "$HAS_AX" = 1 ] && [ -z "$REASON_PART" ]; then
            EXCL=$(grep -v '^|' "$WORK" | grep -m1 -E '의도적 제외' | sed -E 's/.*의도적 제외:?[[:space:]]*//; s/[[:space:]]*·.*//' || true)
            case "$EXCL" in ""|*"<"*|*없음*) EXCL="" ;; esac
            [ -n "$EXCL" ] || fail "R13 판정 '$VTXT' 인데 뺀 축($AXPART)의 사유가 없다 — 안 적으면 다음 사람이 「봤는데 괜찮았다」로 읽는다. 「뺀 축: … — <누가·왜>」 또는 「보지 않은 것 → 가. 의도적 제외」에 적어라"
          fi ;;
      esac ;;
  esac
fi

if [ "$VIOL" -eq 0 ]; then
  NOTE=""
  [ "$ROWS" -eq 0 ] && NOTE=" · 대장 0행(결함 0건이면 정상, 뼈대 상태면 채워라)"
  echo "✓ 대장 무결 — $ROWS 행, R1–R13 통과 (open BLOCKER $OPEN_BLOCKERS · 실측 근거 대장 $MEASURED_OK · 게이트 $GATE_MEASURED)$NOTE"
  exit 0
else
  echo "— $VIOL 건 위반. measured 지어내기·근거 없는 verified 는 판정을 무효로 만든다."
  exit 1
fi
