#!/bin/bash
# ledger-lint.sh 테스트 — 픽스처를 임시 디렉터리에 만들어 R1~R13 전 규칙과 결정성을 검증한다.
set -u
LINT="$(cd "$(dirname "$0")/.." && pwd)/bin/ledger-lint.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

check() { # <이름> <기대 exit> <출력에 있어야 할 패턴('' = 무검사)> <lint 인자>
  local name="$1" want="$2" pat="$3" arg="$4" out rc
  out=$(bash "$LINT" "$arg" 2>&1); rc=$?
  if [ "$rc" = "$want" ] && { [ -z "$pat" ] || printf '%s' "$out" | grep -q "$pat"; }; then
    PASS=$((PASS + 1)); echo "PASS  $name"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL  $name (exit=$rc want=$want, pat='$pat')"
    printf '%s\n' "$out" | sed 's/^/      /'
  fi
}

hdr() { # <open BLOCKER 수> <판정>
  # 통과 계열 판정은 게이트 표(R10)와, 조건부면 조건(R11)이 함께 있어야 성립한다 —
  # 픽스처도 그 형태를 따른다. 이 둘을 뺀 픽스처는 현실에 없는 리포트다.
  printf '# 결함 대장 — 테스트\n\n**갱신** 2026-08-20 · **판정** %s · **open BLOCKER** %s · **open 전체** 9\n\n' "$2" "$1"
  case "$2" in
    "출하 가능"|"조건부 출하 가능"|GO|"CONDITIONAL GO")
      printf '## 게이트 (착수 전 확정)\n| 게이트 | 목표 |\n|---|---|\n| G1 | fail 0 |\n\n' ;;
  esac
  case "$2" in
    "조건부 출하 가능"|"CONDITIONAL GO")
      printf '출하 전 충족 조건 1건: 담당자가 스모크 3동작을 확인한다.\n\n' ;;
  esac
}
thead() {
  printf '| ID | 심각도 | 축 | 한 줄 | 상태 | 근거등급 | 근거 | 닫은 증거 |\n|---|---|---|---|---|---|---|---|\n'
}

# ── 1. 전 규칙 통과하는 정상 대장 ─────────────────────────────
D="$TMP/ok"; mkdir -p "$D/evidence" "$D/src"
echo "measured output" > "$D/evidence/sec.log"; echo "measured output" > "$D/evidence/api.log"
seq 20 > "$D/src/a.ts"                     # 줄 번호 인용(R1) 검증용 — 20줄짜리 실파일
{ hdr 1 "조건부 출하 가능"; thead
  echo '| SEC-01 | BLOCKER | 06 | 저장형 XSS | open | measured | `evidence/sec.log` | — |'
  echo '| API-02 | HIGH | 02 | 권한 우회 | verified | measured | `src/a.ts:12` | `evidence/api.log` |'
  echo '| DEP-03 | MED | 07 | dep 도달 | open | claimed | 팀 진술만 있음 | — |'
  echo '| UX-04 | LOW | 03 | 빈 상태 카피 | deferred | code | `src/a.ts:1` | 출하 후 백로그 |'
  echo '| OK-05 | — | 09 | 3회 반복 동일 (문제없음) | verified | measured | `evidence/api.log` | — |'
} > "$D/ledger.md"
check "정상 대장 → 통과" 0 "대장 무결" "$D"
check "파일 경로 직접 지정도 동작" 0 "대장 무결" "$D/ledger.md"

# ── 1b. 경량 모드 — 단일 readiness.md 도 같은 형식으로 검사된다 ─
D="$TMP/lite"; mkdir -p "$D/evidence"; echo "e2e 3/3 pass" > "$D/evidence/e2e.log"
{ printf '# 예제앱 출하 검증 — 경량 모드\n\n**갱신** 2026-08-20 · **판정** 조건부 출하 가능 · **open BLOCKER** 0 · **open 전체** 1\n\n## 게이트 (착수 전 확정)\n| 게이트 | 목표 | 실측 |\n|---|---|---|\n| G1 E2E | 실패 0 | 3/3 — `evidence/e2e.log` |\n\n출하 전 충족 조건 1건: 온보딩 이탈 지점을 담당자가 재확인한다.\n\n## 결함 대장\n'
  thead
  echo '| USE-01 | HIGH | 04 | 온보딩 플로우 이탈 | open | measured | `evidence/e2e.log` | — |'
} > "$D/readiness.md"
check "경량 모드 readiness.md → lint 통과" 0 "대장 무결" "$D/readiness.md"

# ── 2. R1: measured 인데 실존 파일 근거 없음 ──────────────────
D="$TMP/r1"; mkdir -p "$D"
{ hdr 0 "조건부 출하 가능"; thead
  echo '| PERF-01 | HIGH | 05 | p95 초과 | fixed | measured | 재측정 p95 1.2s | — |'
} > "$D/ledger.md"
check "R1: measured 무근거 → 위반" 1 "R1 \[PERF-01\]" "$D"

# ── 2b. R1: 파일:줄 인용의 줄 번호 범위 검사 ──────────────────
D="$TMP/r1line"; mkdir -p "$D/src"; seq 3 > "$D/src/b.ts"   # 3줄짜리 파일
{ hdr 0 "조건부 출하 가능"; thead
  echo '| SEC-01 | HIGH | 06 | 죽은 줄 인용 | open | measured | `src/b.ts:99` | — |'
} > "$D/ledger.md"
check "R1: 줄 번호가 파일 길이 초과 → 위반" 1 "R1 \[SEC-01\]" "$D"
{ hdr 0 "조건부 출하 가능"; thead
  echo '| SEC-01 | HIGH | 06 | 유효 줄 인용 | open | measured | `src/b.ts:2` | — |'
} > "$D/ledger.md"
check "R1: 유효 줄 번호 → 통과" 0 "대장 무결" "$D"

# ── 3. R2: verified 인데 닫은 증거 없음 ───────────────────────
D="$TMP/r2"; mkdir -p "$D/evidence"; echo "measured output" > "$D/evidence/x.log"
{ hdr 0 "조건부 출하 가능"; thead
  echo '| SEC-01 | HIGH | 06 | 헤더 누락 | verified | measured | `evidence/x.log` | — |'
} > "$D/ledger.md"
check "R2: verified 닫은증거 없음 → 위반" 1 "R2 \[SEC-01\]" "$D"

# ── 4. R3: ID 중복 ────────────────────────────────────────────
D="$TMP/r3"; mkdir -p "$D"
{ hdr 0 "조건부 출하 가능"; thead
  echo '| API-01 | MED | 02 | a | open | code | `x` | — |'
  echo '| API-01 | LOW | 02 | b | open | code | `x` | — |'
} > "$D/ledger.md"
check "R3: ID 중복 → 위반" 1 "R3 \[API-01\]" "$D"

# ── 5. R4: 어휘 위반 (상태 done · 등급 tested) ────────────────
D="$TMP/r4"; mkdir -p "$D"
{ hdr 0 "조건부 출하 가능"; thead
  echo '| OPS-01 | MED | 11 | 알림 없음 | done | tested | 코드 봄 | — |'
} > "$D/ledger.md"
check "R4: 상태 어휘 위반 → 위반" 1 "R4 \[OPS-01\] 상태" "$D"
check "R4: 등급 어휘 위반도 잡힘" 1 "R4 \[OPS-01\] 근거등급" "$D"

# ── 6. R5: rejected 사유 없음 ─────────────────────────────────
D="$TMP/r5"; mkdir -p "$D"
{ hdr 0 "조건부 출하 가능"; thead
  echo '| API-09 | MED | 02 | 감사 오류였음 | rejected | code | 이전 릴리즈 반영 | — |'
} > "$D/ledger.md"
check "R5: rejected 사유 없음 → 위반" 1 "R5 \[API-09\]" "$D"

# ── 7. R6: 헤더 정합 ──────────────────────────────────────────
D="$TMP/r6a"; mkdir -p "$D/evidence"; echo "measured output" > "$D/evidence/s.log"
{ hdr 0 "조건부 출하 가능"; thead     # 헤더 0 인데 실제 open BLOCKER 1
  echo '| SEC-01 | BLOCKER | 06 | xss | open | measured | `evidence/s.log` | — |'
} > "$D/ledger.md"
check "R6: 헤더 open BLOCKER 불일치 → 위반" 1 "R6 헤더" "$D"

D="$TMP/r6b"; mkdir -p "$D/evidence"; echo "measured output" > "$D/evidence/s.log"
{ hdr 1 "출하 가능"; thead            # GO 인데 open BLOCKER 존재
  echo '| SEC-01 | BLOCKER | 06 | xss | open | measured | `evidence/s.log` | — |'
} > "$D/ledger.md"
check "R6: GO + open BLOCKER → 위반" 1 "R6 판정" "$D"

D="$TMP/r6c"; mkdir -p "$D/evidence"; echo "measured output" > "$D/evidence/s.log"
{ hdr 1 "출하 불가(NO-GO)"; thead     # NO-GO 는 open BLOCKER 와 공존 가능
  echo '| SEC-01 | BLOCKER | 06 | xss | open | measured | `evidence/s.log` | — |'
} > "$D/ledger.md"
check "R6: NO-GO + open BLOCKER → 통과" 0 "대장 무결" "$D"

# ── 7b. R6: 영문 판정 어휘 + 미인식 어휘 위반 ─────────────────
D="$TMP/r6d"; mkdir -p "$D/evidence"; echo "measured output" > "$D/evidence/s.log"
{ printf '# Ledger — test\n\n**Verdict** GO · **open BLOCKER** 1\n\n'; thead
  echo '| SEC-01 | BLOCKER | 06 | xss | open | measured | `evidence/s.log` | — |'
} > "$D/ledger.md"
check "R6: 영문 GO + open BLOCKER → 위반" 1 "R6 판정" "$D"

D="$TMP/r6e"; mkdir -p "$D/evidence"; echo "measured output" > "$D/evidence/s.log"
{ printf '# Ledger — test\n\n**Verdict** CONDITIONAL GO · **open BLOCKER** 1\n\n## Gates\n| Gate | Target |\n|---|---|\n| G1 | fail 0 |\n\n1 condition before ship: owner re-checks the XSS fix.\n\n'; thead
  echo '| SEC-01 | BLOCKER | 06 | xss | open | measured | `evidence/s.log` | — |'
} > "$D/ledger.md"
check "R6: CONDITIONAL GO + open BLOCKER → 통과" 0 "대장 무결" "$D"

D="$TMP/r6f"; mkdir -p "$D/evidence"; echo "measured output" > "$D/evidence/s.log"
{ hdr 0 "아마 괜찮음"; thead          # 어휘 밖 판정 — 조용히 넘기지 않는다
  echo '| UX-01 | LOW | 03 | 카피 | open | measured | `evidence/s.log` | — |'
} > "$D/ledger.md"
check "R6: 미인식 판정 어휘 → 위반" 1 "R6 판정 어휘 인식 불가" "$D"

# ── 7c. R6: 단어 경계 — GO 부분 문자열 오인 금지 ─────────────
D="$TMP/r6g"; mkdir -p "$D/evidence"; echo "measured output" > "$D/evidence/s.log"
{ hdr 0 "NOT GOOD"; thead                 # GOOD 의 GO 를 GO 판정으로 오인하면 안 된다
  echo '| UX-01 | LOW | 03 | 카피 | open | measured | `evidence/s.log` | — |'
} > "$D/ledger.md"
check "R6: NOT GOOD → 미인식 위반 (GO 오인 금지)" 1 "R6 판정 어휘 인식 불가" "$D"

D="$TMP/r6h"; mkdir -p "$D/evidence"; echo "measured output" > "$D/evidence/s.log"
{ printf '# Ledger — test\n\n**Verdict** NO-GO · **open BLOCKER** 1\n\n'; thead
  echo '| SEC-01 | BLOCKER | 06 | xss | open | measured | `evidence/s.log` | — |'
} > "$D/ledger.md"
check "R6: 영문 NO-GO + open BLOCKER → 통과" 0 "대장 무결" "$D"

# ── 7e. R6: 판정 텍스트 정밀 분류 (부분 문자열 오인 금지) ─────
D="$TMP/r6i"; mkdir -p "$D/evidence"; echo "measured output" > "$D/evidence/s.log"
{ printf '# t\n\n**갱신** 2026-08-20 · **판정** 출하 가능 — 잔여는 재현 불가 건뿐 · **open BLOCKER** 1\n\n'; thead
  echo '| SEC-01 | BLOCKER | 06 | xss | open | measured | `evidence/s.log` | — |'
} > "$D/ledger.md"
check "R6: 본문의 '불가'가 GO 게이트를 못 뚫는다" 1 "R6 판정" "$D"

D="$TMP/r6j"; mkdir -p "$D/evidence"; echo "measured output" > "$D/evidence/s.log"
{ printf '# t\n\n**갱신** 2026-08-20 · **판정** 판정 불가 — 근거 부재 · **open BLOCKER** 1\n\n'; thead
  echo '| SEC-01 | BLOCKER | 06 | xss | open | measured | `evidence/s.log` | — |'
} > "$D/ledger.md"
check "R6: '판정 불가' + open BLOCKER → 통과" 0 "대장 무결" "$D"

D="$TMP/r6k"; mkdir -p "$D/evidence"; echo "measured output" > "$D/evidence/s.log"
{ printf '# t\n\n**Verdict** UNVERIFIABLE · **open BLOCKER** 1\n\n'; thead
  echo '| SEC-01 | BLOCKER | 06 | xss | open | measured | `evidence/s.log` | — |'
} > "$D/ledger.md"
check "R6: UNVERIFIABLE + open BLOCKER → 통과" 0 "대장 무결" "$D"

D="$TMP/r6l"; mkdir -p "$D/evidence"; echo "measured output" > "$D/evidence/s.log"
{ printf '# t\n\n**Verdict:** GO · **open BLOCKER** 1\n\n'; thead
  echo '| SEC-01 | BLOCKER | 06 | xss | open | measured | `evidence/s.log` | — |'
} > "$D/ledger.md"
check "R6: 콜론 붙은 **Verdict:** 도 인식 → 위반" 1 "R6 판정" "$D"

D="$TMP/r6m"; mkdir -p "$D/evidence"; echo "measured output" > "$D/evidence/s.log"
{ hdr 0 "ONGOING"; thead
  echo '| UX-01 | LOW | 03 | 카피 | open | measured | `evidence/s.log` | — |'
} > "$D/ledger.md"
check "R6: ONGOING → 미인식 위반" 1 "R6 판정 어휘 인식 불가" "$D"

# ── 7f. R6: 헤더 필수 — 조용한 스킵 금지 ─────────────────────
D="$TMP/r6n"; mkdir -p "$D/evidence"; echo "measured output" > "$D/evidence/s.log"
{ printf '# t\n\n**갱신** 2026-08-20 · **open BLOCKER** 1\n\n'; thead   # 판정 줄 없음
  echo '| SEC-01 | BLOCKER | 06 | xss | open | measured | `evidence/s.log` | — |'
} > "$D/ledger.md"
check "R6: 판정 줄 없음 → 위반" 1 "R6 판정 줄" "$D"

D="$TMP/r6o"; mkdir -p "$D/evidence"; echo "measured output" > "$D/evidence/s.log"
{ printf '# t\n\n**갱신** 2026-08-20 · **판정** 출하 불가(NO-GO)\n\n'; thead   # 카운트 없음
  echo '| SEC-01 | BLOCKER | 06 | xss | open | measured | `evidence/s.log` | — |'
} > "$D/ledger.md"
check "R6: open BLOCKER 헤더 없음 → 위반" 1 "R6 헤더에" "$D"

# ── 7g. R1 강화: 끝 개행·글로빙·확장자 ───────────────────────
D="$TMP/r1nl"; mkdir -p "$D"; printf 'PASS 12/12' > "$D/last.log"   # 끝 개행 없음
{ hdr 0 "조건부 출하 가능"; thead
  echo '| DET-01 | LOW | 09 | 끝 개행 없는 로그 | open | measured | `last.log:1` | — |'
} > "$D/ledger.md"
check "R1: 끝 개행 없는 파일의 유효 인용 → 통과" 0 "대장 무결" "$D"

D="$TMP/r1glob"; mkdir -p "$D"; echo "hit" > "$D/hit.log"
{ hdr 0 "조건부 출하 가능"; thead
  echo '| SEC-01 | HIGH | 06 | 와일드카드 인용 | open | measured | `*.log` | — |'
} > "$D/ledger.md"
( cd "$D" && bash "$LINT" "$D" >/dev/null 2>&1 ); RC=$?
if [ "$RC" = "1" ]; then PASS=$((PASS+1)); echo "PASS  R1: 와일드카드 셀은 CWD 글로빙으로 통과 못 함"
else FAIL=$((FAIL+1)); echo "FAIL  R1: 와일드카드 셀은 CWD 글로빙으로 통과 못 함 (exit=$RC want=1)"; fi

D="$TMP/r1csv"; mkdir -p "$D"; echo "p95,120ms" > "$D/bench.csv"
{ hdr 0 "조건부 출하 가능"; thead
  echo '| PERF-01 | LOW | 05 | 벤치 결과 | open | measured | `bench.csv` | — |'
} > "$D/ledger.md"
check "R1: csv 등 추가 확장자 인용 → 통과" 0 "대장 무결" "$D"

# ── 7d. R7: 껍데기 증거 검출 ──────────────────────────────────
D="$TMP/r7a"; mkdir -p "$D/evidence"; touch "$D/evidence/empty.log"   # 0바이트
{ hdr 0 "조건부 출하 가능"; thead
  echo '| SEC-01 | HIGH | 06 | 빈 증거 | open | measured | `evidence/empty.log` | — |'
} > "$D/ledger.md"
check "R7: 0바이트 증거 파일 → 위반" 1 "R7 \[SEC-01\].*비어" "$D"

D="$TMP/r7b"; mkdir -p "$D/src"; printf 'a\n\nc\n' > "$D/src/c.ts"    # 2번 줄이 공백
{ hdr 0 "조건부 출하 가능"; thead
  echo '| API-01 | HIGH | 02 | 공백 줄 인용 | open | measured | `src/c.ts:2` | — |'
} > "$D/ledger.md"
check "R7: 공백 줄 인용 → 위반" 1 "R7 \[API-01\].*공백 줄" "$D"
{ hdr 0 "조건부 출하 가능"; thead
  echo '| API-01 | HIGH | 02 | 실근거 줄 인용 | open | measured | `src/c.ts:3` | — |'
} > "$D/ledger.md"
check "R7: 내용 있는 줄 인용 → 통과" 0 "대장 무결" "$D"
D="$TMP/r7ws"; mkdir -p "$D/evidence"; printf '\n\n  \n' > "$D/evidence/ws.log"   # 공백뿐
{ hdr 0 "조건부 출하 가능"; thead
  echo '| SEC-02 | HIGH | 06 | 공백뿐 증거 | open | measured | `evidence/ws.log` | — |'
} > "$D/ledger.md"
check "R7: 공백뿐 파일(echo 우회) → 위반" 1 "R7 \[SEC-02\].*비어" "$D"
D="$TMP/r7mix"; mkdir -p "$D/evidence"; touch "$D/evidence/empty.log"
echo "measured output" > "$D/evidence/ok.log"          # 정상+0바이트 혼합 인용
{ hdr 0 "조건부 출하 가능"; thead
  echo '| SEC-03 | HIGH | 06 | 혼합 인용 | open | measured | `evidence/ok.log` `evidence/empty.log` | — |'
} > "$D/ledger.md"
check "R7: 정상+빈 파일 혼합 인용도 위반(빈 인용 자체가 적신호)" 1 "R7 \[SEC-03\]" "$D"

# ── 8. 사용법·대상 없음 ───────────────────────────────────────
check "인자 없음 → exit 2" 2 "사용법" ""
check "없는 경로 → exit 2" 2 "없습니다" "$TMP/nope"
# 데이터 행 0 은 오류가 아니다 — 청정 감사·뼈대일 수 있고, 판정급 규칙(R8 등)이 가른다.
# 예전 계약(빈 대장 = exit 2 조기 종료)이 「GO+0행」 우회(자기감사 VPR-01)를 만들었다.
D="$TMP/empty"; mkdir -p "$D"; { hdr 0 "조건부 출하 가능"; } > "$D/ledger.md"
check "데이터 행 없음(위반 0) → 통과 + 0행 노트" 0 "대장 0행" "$D"

# ══ ensure-tools.sh ══════════════════════════════════════════
ET="$(cd "$(dirname "$0")/.." && pwd)/bin/ensure-tools.sh"

# PATH 를 **통째로 교체**해 실행한다(호스트 PATH 상속 금지) — 호스트에 gitleaks 가
# 설치돼 있으면 "누락" 픽스처가 뒤집히는 환경 의존을 막는다(축 ⑨ 결정성).
# ensure-tools.sh 는 셸 builtin 만 쓰므로 격리 PATH 에는 bash 만 있으면 된다.
NOBIN="$TMP/nobin"; mkdir -p "$NOBIN"; ln -s "$(command -v bash)" "$NOBIN/bash"

check_et() { # <이름> <기대 exit> <패턴> <ET_SKILLS_DIR> <교체할 PATH 값> <인자>
  # 플러그인 루트는 기본 빈 디렉터리로 격리(ET_PDIR 로 재지정) — 호스트 플러그인 무관.
  local name="$1" want="$2" pat="$3" sdir="$4" pval="$5" arg="$6" out rc
  out=$(ET_SKILLS_DIR="$sdir" ET_PLUGINS_DIR="${ET_PDIR:-$TMP/noplugins}" ET_DRYRUN=1 PATH="$pval" bash "$ET" $arg 2>&1); rc=$?
  if [ "$rc" = "$want" ] && { [ -z "$pat" ] || printf '%s' "$out" | grep -q "$pat"; }; then
    PASS=$((PASS + 1)); echo "PASS  $name"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL  $name (exit=$rc want=$want, pat='$pat')"
    printf '%s\n' "$out" | sed 's/^/      /'
  fi
}

# 전부 있는 환경: 디렉터리로 확인하는 스킬 8개 + gitleaks 스텁. noplugins 는 기본 격리 플러그인 루트라
# check_et 첫 호출 전에 만들어 둔다(글로브 미매치에 우연히 기대지 않는다).
mkdir -p "$TMP/noplugins"
SD="$TMP/skills-all"; for s in qa qa-only browse benchmark cso design-review codex canary; do
  mkdir -p "$SD/$s"; touch "$SD/$s/SKILL.md"
done
BIN="$TMP/fakebin"; mkdir -p "$BIN"; printf '#!/bin/sh\nexit 0\n' > "$BIN/gitleaks"; chmod +x "$BIN/gitleaks"
check_et "전부 있음 → exit 0" 0 "전부 사용 가능" "$SD" "$BIN:$NOBIN" ""

# 스킬 일부 누락
SD2="$TMP/skills-some"; for s in qa browse; do mkdir -p "$SD2/$s"; touch "$SD2/$s/SKILL.md"; done
check_et "스킬 누락 감지 → exit 1" 1 "✗ /cso" "$SD2" "$BIN:$NOBIN" ""
check_et "누락 스킬에 설치 지시 출력" 1 "SearchSkills" "$SD2" "$BIN:$NOBIN" ""

# CLI 도구 누락 — gitleaks 없는 격리 PATH 로 감지 (호스트 설치 여부와 무관)
SD3="$SD"   # 스킬은 전부 있음
check_et "CLI 도구 누락 감지 → exit 1" 1 "✗ gitleaks" "$SD3" "$NOBIN" ""

# --install + DRYRUN → 설치 명령 출력, 실행은 안 함
check_et "--install DRYRUN → 설치 명령 출력" 0 "DRYRUN: brew install gitleaks" "$SD3" "$NOBIN" "--install"

# 플러그인 배치 스킬 탐지 — 사용자 스킬 디렉터리에 없어도 플러그인 경로에서 찾는다
SD4="$TMP/skills-few"; for s in qa-only browse benchmark cso design-review codex canary; do
  mkdir -p "$SD4/$s"; touch "$SD4/$s/SKILL.md"
done                                          # qa 만 빠진 사용자 스킬 디렉터리
PD1="$TMP/plugins-mp"; mkdir -p "$PD1/marketplaces/mp1/skills/qa"
touch "$PD1/marketplaces/mp1/skills/qa/SKILL.md"
ET_PDIR="$PD1" check_et "플러그인(marketplaces) 스킬 탐지 → exit 0" 0 "✓ /qa (plugin)" "$SD4" "$BIN:$NOBIN" ""
PD2="$TMP/plugins-cache"; mkdir -p "$PD2/cache/mp1/plug/1.0.0/skills/qa"
touch "$PD2/cache/mp1/plug/1.0.0/skills/qa/SKILL.md"
ET_PDIR="$PD2" check_et "플러그인(cache) 스킬 탐지 → exit 0" 0 "✓ /qa (plugin)" "$SD4" "$BIN:$NOBIN" ""
check_et "플러그인에도 없으면 누락 유지 → exit 1" 1 "✗ /qa" "$SD4" "$BIN:$NOBIN" ""

# 세션 제공 스킬(내장·플러그인 네임스페이스)은 디렉터리에 없어도 **누락이 아니다.**
# 예전에는 이걸 「없음」으로 세어, 멀쩡히 쓸 수 있는 /security-review 를 설치하라고 안내했다.
check_et "세션 제공 스킬은 별도 표기" 0 "세션 제공 스킬" "$SD" "$BIN:$NOBIN" ""
check_et "세션 제공 스킬은 누락으로 세지 않는다" 0 "● /security-review" "$SD" "$BIN:$NOBIN" ""
# 스킬 자동 설치 — DRYRUN 은 명령만 출력하고 설치된 것으로 친다.
check_et "--install 이 스킬 설치를 시도한다" 0 "DRYRUN: claude plugin install cso" "$SD2" "$NOBIN" "--install"
# 설치가 안 됐을 때의 안내는 「축을 빼라」가 아니라 「직접 수행하라」여야 한다.
check_et "설치 불가여도 축을 빼지 말라고 안내" 1 "도구가 없다는 이유로 축을 빼지 마라" "$SD2" "$BIN:$NOBIN" ""

# ══ 2026-08-27 자기감사(VPR-01~03) 회귀 ═══════════════════════
# VPR-01(BLOCKER): 대장 0행 조기 종료(exit 2)가 R8·R10·R11·R13 을 통째로 건너뛰어
# 「GO + 빈 대장」이 lint 와 렌더 게이트(당시 exit 1 만 차단)를 지나 게시됐다.
# 판정 전 이탈 금지 — 0행이어도 판정급 규칙까지 내려가야 한다. 이 케이스의 부재가
# 결함이 156건 전건 통과를 뚫고 살아남은 원인이었다(감사 리포트 §5-5).
D="$TMP/vpr01"; mkdir -p "$D"
{ hdr 0 "출하 가능"; thead; } > "$D/ledger.md"
check "VPR-01: GO + 대장 0행 → R8 위반(조기 종료 금지)" 1 "R8" "$D"
# 반대 방향(과차단 금지, 자기감사 O1): 결함 0건 + 게이트 실측 인용의 청정 감사는 정상 결과다
D="$TMP/vpr01-clean"; mkdir -p "$D/evidence"; echo "156 passed, 0 failed" > "$D/evidence/test.log"
{ printf '# 청정 감사\n\n**갱신** 2026-08-27 · **판정** 출하 가능 · **open BLOCKER** 0 · **open 전체** 0\n\n## 게이트 (착수 전 확정)\n| 게이트 | 목표 | 실측 |\n|---|---|---|\n| G1 테스트 | fail 0 | 156/0 — `evidence/test.log:1` |\n\n## 결함 대장\n'
  thead
} > "$D/readiness.md"
check "VPR-01: 청정 감사(GO·0행·게이트 실측) → 통과(과차단 금지)" 0 "대장 무결" "$D/readiness.md"
# VPR-03: 갓 만든 뼈대를 바로 lint 하는 자연스러운 첫 동작(new → lint)은 통과해야 한다 —
# 예전에는 exit 2 + 「표 형식 확인」으로 도구가 자기가 만든 표를 사용자 탓했다.
VPRBIN="$(cd "$(dirname "$0")/.." && pwd)/bin/vpr"
D="$TMP/vpr03"
bash "$VPRBIN" new "$D" >/dev/null 2>&1
check "VPR-03: vpr new 뼈대 → lint 통과(사용자 탓 금지)" 0 "대장 무결" "$D/readiness.md"

# ══ report-html.py ═══════════════════════════════════════════
RH="$(cd "$(dirname "$0")/.." && pwd)/bin/report-html.py"
if command -v python3 >/dev/null 2>&1; then
  check_rh() { # <이름> <기대 exit> <출력 html 에 있어야 할 패턴> <인자...>
    local name="$1" want="$2" pat="$3" htmlf="$4"; shift 4
    local out rc
    out=$(python3 "$RH" "$@" 2>&1); rc=$?
    if [ "$rc" = "$want" ] && { [ -z "$pat" ] || grep -q "$pat" "$htmlf" 2>/dev/null; }; then
      PASS=$((PASS + 1)); echo "PASS  $name"
    else
      FAIL=$((FAIL + 1)); echo "FAIL  $name (exit=$rc want=$want, pat='$pat')"
      printf '%s\n' "$out" | sed 's/^/      /'
    fi
  }
  # 정식 모드: summary + ledger + evidence 이미지(1x1 png) 임베드
  D="$TMP/rh"; mkdir -p "$D/evidence"
  python3 -c "import base64,sys;open('$D/evidence/shot.png','wb').write(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='))"
  printf '# 예제앱 출하 검증 — 종합 리포트\n\n**판정** 조건부 출하 가능\n' > "$D/00-summary.md"
  { hdr 0 "조건부 출하 가능"; thead
    echo '| API-01 | HIGH | 02 | 권한 우회 | verified | measured | `evidence/shot.png` | `evidence/shot.png` |'
  } > "$D/ledger.md"
  check_rh "report-html: 디렉터리 렌더 → report.html" 0 "data:image/png;base64" "$D/report.html" "$D"
  check_rh "report-html: 대장 행·배지 렌더" 0 'badge b-verified' "$D/report.html" "$D"
  # 경량 모드: 단일 파일 입력
  D2="$TMP/rh-lite"; mkdir -p "$D2"
  { hdr 0 "조건부 출하 가능"; thead
    echo '| USE-01 | LOW | 04 | 마찰 | open | code | `x.md` | — |'
  } > "$D2/readiness.md"
  check_rh "report-html: 경량 readiness.md 렌더" 0 "USE-01" "$D2/report.html" "$D2/readiness.md"
  check_rh "report-html: 없는 대상 → exit 2" 2 "" "/dev/null" "$TMP/rh-nope"
  # -o 경로 지정(없는 상위 디렉터리 포함) + 인자 누락
  check_rh "report-html: -o 커스텀 경로(+mkdir)" 0 "USE-01" "$TMP/rh-out/sub/x.html" "$D2/readiness.md" -o "$TMP/rh-out/sub/x.html"
  check_rh "report-html: -o 인자 누락 → exit 2" 2 "" "/dev/null" "$D2/readiness.md" -o
  # lint 게이트: 위반 대장은 렌더 거부(exit 1)
  D3="$TMP/rh-bad"; mkdir -p "$D3"
  { hdr 0 "출하 가능"; thead
    echo '| SEC-01 | HIGH | 06 | 무근거 measured | open | measured | 서술뿐 | — |'
  } > "$D3/readiness.md"
  check_rh "report-html: lint 위반 대장 → 렌더 거부 exit 1" 1 "" "/dev/null" "$D3/readiness.md"
  # 제목: 코드펜스 안 h1 은 무시
  D4="$TMP/rh-title"; mkdir -p "$D4"
  # fail-closed 렌더 게이트(자기감사 VPR-01) 이후, 렌더 픽스처도 lint 를 통과하는
  # 최소 유효 대장이어야 한다 — 판정 불가 헤더 한 줄이면 충분하다(실측 부담 없음).
  printf '```markdown\n# 골격 예시 제목\n```\n\n# 진짜 제목\n\n**갱신** 2026-08-27 · **판정** 판정 불가 · **open BLOCKER** 0 · **open 전체** 0\n\n본문\n' > "$D4/readiness.md"
  check_rh "report-html: 펜스 안 h1 은 제목이 아니다" 0 "<title>진짜 제목</title>" "$D4/report.html" "$D4/readiness.md"
  # evidence 하위 디렉터리(x.png/) 무시 + 문서 골격 태그 부재(Artifact 래핑 계약)
  D5="$TMP/rh-trap"; mkdir -p "$D5/evidence/trap.png"
  printf '# 골격 계약\n\n**갱신** 2026-08-27 · **판정** 판정 불가 · **open BLOCKER** 0 · **open 전체** 0\n\n본문\n' > "$D5/readiness.md"
  check_rh "report-html: evidence 하위 디렉터리 무시" 0 "골격 계약" "$D5/report.html" "$D5/readiness.md"
  if grep -qiE '<!doctype|<html|<body' "$D5/report.html"; then
    FAIL=$((FAIL+1)); echo "FAIL  report-html: 문서 골격 태그 없음 (doctype/html/body 검출됨)"
  else
    PASS=$((PASS+1)); echo "PASS  report-html: 문서 골격 태그 없음"
  fi
  # 렌더할 파일 없는 디렉터리 → exit 2
  D6="$TMP/rh-empty"; mkdir -p "$D6"
  check_rh "report-html: 렌더할 파일 없는 디렉터리 → exit 2" 2 "" "/dev/null" "$D6"
  # 이스케이프 고정: 셀의 <script> 는 &lt; 로 무력화돼야 한다 (순서 회귀 시 XSS)
  D7="$TMP/rh-xss"; mkdir -p "$D7"
  printf '# 이스케이프\n\n**갱신** 2026-08-27 · **판정** 판정 불가 · **open BLOCKER** 0 · **open 전체** 0\n\n| A |\n|---|\n| <script>alert(1)</script> |\n' > "$D7/readiness.md"
  check_rh "report-html: 셀 <script> 이스케이프" 0 '&lt;script&gt;' "$D7/report.html" "$D7/readiness.md"
  if grep -q '<script>' "$D7/report.html"; then
    FAIL=$((FAIL+1)); echo "FAIL  report-html: 원시 <script> 잔존 (XSS)"
  else
    PASS=$((PASS+1)); echo "PASS  report-html: 원시 <script> 없음"
  fi
  # ── 2026-08-27 자기감사 회귀 (VPR-01 렌더층 · VPR-02) ──
  # VPR-01 렌더층: lint 미통과(0 아닌 모든 종료코드)는 렌더를 막는다 — fail-closed.
  D8="$TMP/rh-bypass"; mkdir -p "$D8"
  { hdr 0 "출하 가능"; thead; } > "$D8/readiness.md"
  check_rh "report-html: GO+0행 대장 → 렌더 거부(fail-closed)" 1 "" "/dev/null" "$D8/readiness.md"
  # VPR-02: 경량 모드 산출물만 있는 **디렉터리** 렌더 — readiness.md 를 후보로 해석해야
  # 한다(문서의 「전형적인 흐름」이 디렉터리 인자다. 예전엔 100% 실패).
  check_rh "report-html: 경량 디렉터리 렌더(readiness.md만)" 0 "USE-01" "$D2/report.html" "$D2"
  # ── VPR-05(2R 자기감사): 게이트는 「검사할 수 없으면 거부」 ──
  # 재현 A: 대장 파일 부재(요약만) — 예전엔 lint 가 호출조차 안 돼 「출하 가능」이 무검사 게시됐다
  D9="$TMP/rh-noledger"; mkdir -p "$D9"
  printf '# 요약\n\n**갱신** 2026-08-27 · **판정** 출하 가능 · **open BLOCKER** 0 · **open 전체** 0\n' > "$D9/00-summary.md"
  check_rh "report-html: 대장 없는 디렉터리 → 렌더 거부(VPR-05 A)" 1 "" "/dev/null" "$D9"
  if [ -f "$D9/report.html" ]; then
    FAIL=$((FAIL+1)); echo "FAIL  report-html: 거부했는데 산출물이 생겼다(VPR-05 A)"
  else
    PASS=$((PASS+1)); echo "PASS  report-html: 거부 시 산출물 미생성(VPR-05 A)"
  fi
  # 재현 B: ledger-lint.sh 없는 단독 배치 — 검증 도구 부재도 「미실시 ≠ 통과」로 거부
  DL="$TMP/rh-nolint"; mkdir -p "$DL/fixture"
  cp "$RH" "$DL/report-html.py"; cp "$D2/readiness.md" "$DL/fixture/readiness.md"
  out=$(python3 "$DL/report-html.py" "$DL/fixture/readiness.md" 2>&1); rc=$?
  if [ "$rc" = 1 ] && [ ! -f "$DL/fixture/report.html" ]; then
    PASS=$((PASS+1)); echo "PASS  report-html: lint 스크립트 부재 → 렌더 거부(VPR-05 B)"
  else
    FAIL=$((FAIL+1)); echo "FAIL  report-html: lint 부재인데 거부 안 함(VPR-05 B, exit=$rc)"
    printf '%s\n' "$out" | sed 's/^/      /'
  fi
else
  echo "SKIP  report-html.py (python3 없음)"
fi

# ══ R8 · R9 · 결정성 — 2026-08-23 감정 수정분 ═══════════════════════
# 왜 이 블록이 있나: 이 세 가지가 오래 비어 있었다. R8(간판 규칙)은 문서에만 있었고,
# R9(게이트 실측 칸)는 무검사였으며, 인용 해석이 CWD 에 의존해 같은 대장이 실행 위치에
# 따라 통과/위반으로 갈렸다. 회귀하면 스킬의 존재 이유가 다시 사라지므로 테스트로 못 박는다.

gate_hdr() { printf '## 게이트\n| 게이트 | 목표 | 실측 |\n|---|---|---|\n'; }

# R8-1 근거가 전부 claimed 인데 「출하 가능」 → 위반 (감정에서 실측된 BLOCKER 시나리오)
D="$TMP/r8a"; mkdir -p "$D"
{ hdr 0 "출하 가능"; thead
  echo '| SEC-01 | HIGH | 06 | 토큰 로깅 | verified | claimed | 담당자가 고쳤다고 함 | 담당자 확인 |'
} > "$D/ledger.md"
check "R8: claimed 만으로 GO → 위반" 1 "R8 판정" "$D"

# R8-2 같은 대장을 「판정 불가」로 강등하면 통과 — 안내가 실제로 열리는 길인지 확인
D="$TMP/r8b"; mkdir -p "$D"
{ hdr 0 "판정 불가"; thead
  echo '| SEC-01 | HIGH | 06 | 토큰 로깅 | verified | claimed | 담당자가 고쳤다고 함 | 담당자 확인 |'
} > "$D/ledger.md"
check "R8: 판정 불가로 강등 → 통과" 0 "대장 무결" "$D"

# R8-3 「조건부 출하 가능」은 R8 비적용 — SKILL.md 가 실측 불가 시 권하는 탈출구다(과차단 방지)
D="$TMP/r8c"; mkdir -p "$D"
{ hdr 0 "조건부 출하 가능"; thead
  echo '| SEC-01 | HIGH | 06 | 토큰 로깅 | open | claimed | 진술만 있음 | — |'
} > "$D/ledger.md"
check "R8: 조건부는 실측 0이어도 통과(탈출구 보존)" 0 "대장 무결" "$D"

# R8-4 실측이 게이트 표에만 있어도 GO 가 선다 — 경량 모드의 실제 형태
D="$TMP/r8d"; mkdir -p "$D/evidence"; echo "440 passed / 0 failed" > "$D/evidence/tests.log"
{ hdr 0 "출하 가능"; gate_hdr
  echo '| G1 테스트 | fail 0 | 0 — `evidence/tests.log:1` |'
  printf '\n## 결함 대장\n'; thead
  echo '| SUP-01 | LOW | 07 | 의존성 0 | verified | code | Package.swift | 확인 |'
} > "$D/readiness.md"
check "R8: 게이트 표 실측만으로도 GO 성립" 0 "대장 무결" "$D/readiness.md"

# R9-1 게이트 실측 칸이 서술뿐 → 위반
D="$TMP/r9a"; mkdir -p "$D/evidence"; echo x > "$D/evidence/e.log"
{ hdr 0 "출하 불가"; gate_hdr
  echo '| G1 테스트 | fail 0 | 팀이 다 통과했다고 함 |'
  printf '\n## 결함 대장\n'; thead
  echo '| SEC-01 | BLOCKER | 06 | 유출 | open | measured | `evidence/e.log` | — |'
} > "$D/readiness.md"
check "R9: 실측 칸이 서술뿐 → 위반" 1 "R9 \[게이트 G1" "$D/readiness.md"

# R9-2 실측 칸이 비었으면 위반 — 숨기지 말고 '미실시' 라고 적으라는 안내
D="$TMP/r9b"; mkdir -p "$D/evidence"; echo x > "$D/evidence/e.log"
{ hdr 0 "출하 불가"; gate_hdr
  echo '| G1 테스트 | fail 0 | — |'
  printf '\n## 결함 대장\n'; thead
  echo '| SEC-01 | BLOCKER | 06 | 유출 | open | measured | `evidence/e.log` | — |'
} > "$D/readiness.md"
check "R9: 실측 칸이 비었음 → 위반" 1 "R9 \[게이트 G1" "$D/readiness.md"

# R9-3 '미실시' 는 위반이 아니지만 실측 근거로 세지 않는다 → GO 면 R8 이 잡는다
D="$TMP/r9c"; mkdir -p "$D"
{ hdr 0 "출하 가능"; gate_hdr
  echo '| G1 테스트 | fail 0 | 미실시 |'
  printf '\n## 결함 대장\n'; thead
  echo '| SUP-01 | LOW | 07 | 의존성 0 | verified | code | Package.swift | 확인 |'
} > "$D/readiness.md"
check "R9: 미실시는 R9 통과·R8 근거 아님" 1 "R8 판정" "$D/readiness.md"

# R9-4 과차단 방지 — 대장 데이터 행의 'measured' 글자와 본문의 '---' 가 게이트 표를 열면 안 된다
D="$TMP/r9d"; mkdir -p "$D/evidence"; echo x > "$D/evidence/e.log"
{ hdr 0 "출하 가능"; thead
  echo '| SEC-01 | HIGH | 06 | 범위 --- 경계 서술 | verified | measured | `evidence/e.log` | `evidence/e.log` |'
  echo '| API-02 | MED | 02 | 다른 건 | verified | measured | `evidence/e.log` | `evidence/e.log` |'
} > "$D/ledger.md"
check "R9: 대장 자신을 게이트 표로 오인하지 않는다" 0 "대장 무결" "$D"

# R1-자기인용: 대장이 자기 자신을 증거로 인용하면 유효 인용으로 세지 않는다
D="$TMP/selfcite"; mkdir -p "$D"
{ hdr 0 "출하 가능"; thead
  echo '| A-01 | MED | 05 | 지연 | verified | measured | `ledger.md:1` | `ledger.md:1` |'
} > "$D/ledger.md"
check "자기 인용: R1 은 통과시키되 R8 이 GO 를 막는다" 1 "R8 판정" "$D"

# 자기 인용 + 외부 증거가 함께 있으면 GO 가 선다(과차단 방지 — 실물 리포트에서 확인한 형태)
D="$TMP/selfcite2"; mkdir -p "$D/evidence"; echo "run output" > "$D/evidence/x.log"
{ hdr 0 "출하 가능"; thead
  echo '| A-01 | MED | 05 | 대장 자신이 증거인 결함 | verified | measured | `ledger.md:1` | `evidence/x.log` |'
} > "$D/ledger.md"
check "자기 인용 + 외부 증거 → 통과" 0 "대장 무결" "$D"


# 자기 인용 판정은 호출 형태(상대/절대 경로)에 좌우되면 안 된다
D="$TMP/selfcite3"; mkdir -p "$D"
{ hdr 0 "출하 가능"; thead
  echo '| A-01 | MED | 05 | 자기 참조 | verified | measured | `readiness.md:1` | `readiness.md:1` |'
} > "$D/readiness.md"
R_ABS=$(cd "$D" && bash "$LINT" "$D/readiness.md" >/dev/null 2>&1; echo $?)
R_REL=$(cd "$D" && bash "$LINT" readiness.md >/dev/null 2>&1; echo $?)
if [ "$R_ABS" = 1 ] && [ "$R_REL" = 1 ]; then
  PASS=$((PASS + 1)); echo "PASS  자기 인용: 상대·절대 경로 호출 모두 동일 판정"
else
  FAIL=$((FAIL + 1)); echo "FAIL  자기 인용: 호출 형태에 따라 판정이 갈린다(abs=$R_ABS rel=$R_REL)"
fi


# 셀 안의 마크다운 이스케이프 파이프(\|)가 열을 밀지 않는다 — 정상 대장에 거짓 위반 금지
D="$TMP/pipecell"; mkdir -p "$D/evidence"; echo "out" > "$D/evidence/x.log"
{ hdr 0 "출하 가능"; thead
  printf '| A-01 | MED | 05 | 조건 a \\| b 를 함께 본다 | verified | measured | `evidence/x.log` | `evidence/x.log` |\n'
} > "$D/ledger.md"
check "셀 안의 \\| 이스케이프 → 열이 밀리지 않는다" 0 "대장 무결" "$D"


# ── R10 · R11 · --strict ─────────────────────────────────────────
# R10: 통과 계열 판정인데 게이트 표가 어디에도 없다 → 위반
D="$TMP/r10a"; mkdir -p "$D/evidence"; echo "out" > "$D/evidence/x.log"
{ printf '# T\n\n**갱신** 2026-08-23 · **판정** 출하 가능 · **open BLOCKER** 0\n\n'; thead
  echo '| A-01 | MED | 05 | x | verified | measured | `evidence/x.log` | `evidence/x.log` |'
} > "$D/ledger.md"
check "R10: 게이트 표 없는 통과 판정 → 위반" 1 "R10 판정" "$D"

# R10: 게이트가 형제 파일(정식 모드)에 있으면 통과 — 파일명을 강제하지 않는다
printf '# 게이트\n| 게이트 | 목표 | 세는 방법 |\n|---|---|---|\n| G1 | fail 0 | vitest |\n' > "$D/00-summary.md"
check "R10: 게이트가 형제 파일에 있으면 통과" 0 "대장 무결" "$D"

# R11: 조건부인데 조건이 없다 → 위반 (조건부는 R8 의 탈출구라 여기서 막지 않으면 우회로가 된다)
D="$TMP/r11"; mkdir -p "$D"
{ printf '# T\n\n**갱신** 2026-08-23 · **판정** 조건부 출하 가능 · **open BLOCKER** 0\n\n## 게이트\n| 게이트 | 목표 |\n|---|---|\n| G1 | fail 0 |\n\n'; thead
  echo '| A-01 | MED | 05 | x | open | claimed | 진술 | — |'
} > "$D/ledger.md"
check "R11: 조건 없는 조건부 → 위반" 1 "R11 판정" "$D"

# --strict: 리포트·저장소 밖 절대경로 인용을 막는다. 기본 모드에서는 막지 않는다(과차단 방지)
D="$TMP/strict"; mkdir -p "$D"
{ hdr 0 "출하 가능"; thead
  echo '| A-01 | MED | 05 | x | verified | measured | `/etc/hosts:1` | `/etc/hosts:1` |'
} > "$D/ledger.md"
check "기본: 범위 밖 절대경로 인용 허용" 0 "대장 무결" "$D"
out=$(bash "$LINT" --strict "$D" 2>&1); rc=$?
if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q "strict"; then
  PASS=$((PASS + 1)); echo "PASS  --strict: 범위 밖 인용 → 위반"
else
  FAIL=$((FAIL + 1)); echo "FAIL  --strict: 범위 밖 인용을 못 잡았다 (exit=$rc)"
fi
# VPR-06(2R 자기감사): `..` 세그먼트 상대경로는 BASE 해석이 리포트 밖으로 탈출해
# --strict 범위 규정이 안 걸렸다 — 절대경로와 같은 「범위 밖 인용」으로 막아야 한다.
D="$TMP/strict-esc"; mkdir -p "$D/r"; echo "escaped evidence" > "$D/out.log"
{ hdr 0 "출하 가능"; thead
  echo '| E-01 | MED | 05 | 탈출 인용 | verified | measured | `../out.log:1` | `../out.log:1` |'
} > "$D/r/ledger.md"
check "기본: .. 상대경로 인용 허용(과차단 방지)" 0 "대장 무결" "$D/r"
out=$(bash "$LINT" --strict "$D/r" 2>&1); rc=$?
if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q "strict"; then
  PASS=$((PASS + 1)); echo "PASS  --strict: .. 상대경로 탈출 인용 → 위반 (VPR-06)"
else
  FAIL=$((FAIL + 1)); echo "FAIL  --strict: .. 상대경로 탈출을 못 잡았다 (exit=$rc)"
fi

# ══ 3R 자기감사(VPR-07~10) 회귀 ═══════════════════════════════
# VPR-08(BLOCKER): H1 제목 「# 조건부 …」가 R11 조건 절로 오인돼, 조건 0줄·실측 0건
# 조건부 판정이 lint·strict·render 를 전부 통과해 게시됐다. H1 은 조건 절이 아니다.
D="$TMP/vpr08"; mkdir -p "$D"
{ printf '# 조건부 출하 판정 — 대상 X\n\n**갱신** 2026-08-27 · **판정** 조건부 출하 가능 · **open BLOCKER** 0 · **open 전체** 0\n\n## 게이트 (착수 전 확정)\n| 게이트 | 목표 |\n|---|---|\n| G1 | fail 0 |\n\n## 결함 대장\n'
  thead
} > "$D/readiness.md"
check "VPR-08: 제목 「조건부…」 + 조건 0줄 → R11 위반" 1 "R11" "$D/readiness.md"
# VPR-07(HIGH): 이 스킬 자신의 템플릿이 권하는 조건 표기와 자연스러운 헤딩이 거부되던 과차단
mk_cond() { # <dir> <조건 블록>
  mkdir -p "$1"
  { printf '# 검증 리포트\n\n**갱신** 2026-08-27 · **판정** 조건부 출하 가능 · **open BLOCKER** 0 · **open 전체** 0\n\n## 게이트 (착수 전 확정)\n| 게이트 | 목표 |\n|---|---|\n| G1 | fail 0 |\n\n'
    printf '%s\n' "$2"
    printf '\n## 결함 대장\n'; thead
  } > "$1/readiness.md"
}
mk_cond "$TMP/vpr07a" '**남은 조건**(조건부일 때만): ① 담당자가 스모크 3동작을 확인한다'
check "VPR-07: 템플릿 권장형(**남은 조건**: ①…) → 통과" 0 "대장 무결" "$TMP/vpr07a/readiness.md"
mk_cond "$TMP/vpr07b" '## 출하 전 조건

1. 담당자가 스모크 3동작을 확인한다'
check "VPR-07: 「## 출하 전 조건」+번호 목록 → 통과" 0 "대장 무결" "$TMP/vpr07b/readiness.md"
mk_cond "$TMP/vpr07c" '## 남은 조건

- 담당자가 롤백 버튼을 실제로 눌러 확인한다'
check "VPR-07: 「## 남은 조건」+목록 → 통과" 0 "대장 무결" "$TMP/vpr07c/readiness.md"
# VPR-09(MED): --strict 는 인용의 물리 경로가 리포트·저장소 안이어야 한다(심볼릭 링크 탈출 차단)
D="$TMP/vpr09"; mkdir -p "$D/evidence"
ln -s /etc/hosts "$D/evidence/pw.log"
{ hdr 0 "조건부 출하 가능"; thead
  echo '| S-01 | MED | 06 | 링크 탈출 | verified | measured | `evidence/pw.log:1` | `evidence/pw.log:1` |'
} > "$D/ledger.md"
check "기본: 심볼릭 링크 인용 허용(과차단 방지)" 0 "대장 무결" "$D"
out=$(bash "$LINT" --strict "$D" 2>&1); rc=$?
if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q "strict"; then
  PASS=$((PASS + 1)); echo "PASS  --strict: 심볼릭 링크 탈출 인용 → 위반 (VPR-09)"
else
  FAIL=$((FAIL + 1)); echo "FAIL  --strict: 심볼릭 링크 탈출을 못 잡았다 (exit=$rc)"
fi
# VPR-10(MED): 비-git 대상의 정식 기본 배치(docs/release-readiness/<날짜>)에서도
# 저장소 루트(=대상 루트) 기준 상대경로 인용이 --strict 로 통과해야 한다
D="$TMP/vpr10/proj"; R="$D/docs/release-readiness/2026-08-27"
mkdir -p "$D/src" "$R"; seq 5 > "$D/src/app.ts"
{ hdr 0 "조건부 출하 가능"; thead
  echo '| C-01 | MED | 08 | 소스 인용 | verified | measured | `src/app.ts:2` | `src/app.ts:2` |'
} > "$R/ledger.md"
check "VPR-10: 비-git 정식 배치, 대상 루트 기준 인용 → 통과" 0 "대장 무결" "$R"
out=$(bash "$LINT" --strict "$R" 2>&1); rc=$?
if [ "$rc" = 0 ]; then
  PASS=$((PASS + 1)); echo "PASS  VPR-10: --strict 에서도 대상 루트 인용 통과"
else
  FAIL=$((FAIL + 1)); echo "FAIL  VPR-10: --strict 가 대상 루트 인용을 막았다 (exit=$rc)"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# ══ 4R 자기감사(VPR-12~17) 회귀 ═══════════════════════════════
# VPR-12(HIGH): 조건이 형제 리포트(00-summary.md — 템플릿이 지정한 위치)에 있어도 인정.
# R11 이 대장만 봐서 정식 모드 조건부가 구조적으로 lint 불통이었다.
D="$TMP/vpr12"; mkdir -p "$D"
{ printf '# 검증 리포트\n\n**갱신** 2026-08-27 · **판정** 조건부 출하 가능 · **open BLOCKER** 0 · **open 전체** 0\n\n## 게이트 (착수 전 확정)\n| 게이트 | 목표 |\n|---|---|\n| G1 | fail 0 |\n\n## 결함 대장\n'
  thead
} > "$D/ledger.md"
printf '# 요약\n\n**판정** 조건부 출하 가능\n\n**남은 조건**(조건부일 때만): ① 배포 담당이 롤백을 스테이징에서 1회 실행해 확인\n' > "$D/00-summary.md"
check "VPR-12: 조건이 00-summary.md 에만 있어도 통과" 0 "대장 무결" "$D"
# VPR-13: 표 형식 조건도 조건 명시다(다른 규격은 전부 표인데 조건만 목록 강제였다)
mk_cond "$TMP/vpr13" '## 출하 전 조건

| 조건 | 누가 | 확인 방법 |
|---|---|---|
| 롤백 1회 실행 | 배포 담당 | 스테이징 로그 확인 |'
check "VPR-13: 표 형식 조건 → 통과" 0 "대장 무결" "$TMP/vpr13/readiness.md"
# VPR-14: 템플릿이 가르치는 ①② 기호를 헤딩 아래에 써도 인정(인라인형과 일관)
mk_cond "$TMP/vpr14" '## 남은 조건

① 배포 담당이 롤백을 스테이징에서 확인한다'
check "VPR-14: 헤딩 아래 ①② 조건 → 통과" 0 "대장 무결" "$TMP/vpr14/readiness.md"
# VPR-15: 인용부호(>) 골격의 조건 절도 인정(템플릿 요약 골격이 인용부호를 쓴다)
mk_cond "$TMP/vpr15" '> ## 남은 조건
> - 담당자가 스모크 3동작을 확인한다'
check "VPR-15: 인용부호 조건 절 → 통과" 0 "대장 무결" "$TMP/vpr15/readiness.md"
# VPR-17: 「조건」을 부분 문자열로만 포함하는 무관한 헤딩(무조건)은 조건 절이 아니다
mk_cond "$TMP/vpr17" '## 무조건 확인할 것

- 이것은 출하 조건이 아니라 일반 메모다'
check "VPR-17: 「## 무조건」 헤딩은 조건 절이 아니다 → R11 위반" 1 "R11" "$TMP/vpr17/readiness.md"
# VPR-18(5R): 「조건 0건」 자기모순 검사는 판정을 지는 파일(대장·00-summary.md)만 —
# 축 파일의 무관 문구(「임계값 미충족 조건 0건」)가 정당한 조건부 리포트를 차단하면 안 된다
D="$TMP/vpr18"; mkdir -p "$D"
{ printf '# 검증 리포트\n\n**갱신** 2026-08-27 · **판정** 조건부 출하 가능 · **open BLOCKER** 0 · **open 전체** 0\n\n## 게이트 (착수 전 확정)\n| 게이트 | 목표 |\n|---|---|\n| G1 | fail 0 |\n\n## 남은 조건\n\n- 담당자가 스모크 3동작을 확인한다\n\n## 결함 대장\n'
  thead
} > "$D/ledger.md"
printf '# 03 UI 축\n\n대비 검사 결과 임계값 미충족 조건 0건 — 이 축은 깨끗하다.\n' > "$D/03-ui.md"
check "VPR-18: 축 파일의 「조건 0건」 문구는 자기모순이 아니다 → 통과" 0 "대장 무결" "$D"
# 반대 방향: 판정을 지는 파일(요약)의 「조건 0건」은 여전히 자기모순 — 위치가 메시지에 실린다
printf '# 요약\n\n**판정** 조건부 출하 가능\n\n남은 조건 0건 — 전부 닫았다.\n' > "$D/00-summary.md"
out=$(bash "$LINT" "$D" 2>&1); rc=$?
if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q '00-summary.md:'; then
  PASS=$((PASS + 1)); echo "PASS  VPR-18: 요약의 조건 0건 → 자기모순 + 위치 표기"
else
  FAIL=$((FAIL + 1)); echo "FAIL  VPR-18: 요약 자기모순 미검출 또는 위치 없음 (exit=$rc)"
  printf '%s\n' "$out" | sed 's/^/      /'
fi
# VPR-26(7R): 모순 검사 범위 = 게시 md 범위 — ledger.md 와 readiness.md 가 공존하면
# readiness.md 의 「조건 0건」도 잡아야 한다(예전엔 검사는 비켜 가고 렌더에는 실렸다)
D="$TMP/vpr26"; mkdir -p "$D"
{ printf '# 검증 리포트\n\n**갱신** 2026-08-27 · **판정** 조건부 출하 가능 · **open BLOCKER** 0 · **open 전체** 0\n\n## 게이트 (착수 전 확정)\n| 게이트 | 목표 |\n|---|---|\n| G1 | fail 0 |\n\n## 남은 조건\n\n- 담당자가 스모크를 확인한다\n\n## 결함 대장\n'
  thead
} > "$D/ledger.md"
printf '# 경량 잔재\n\n**갱신** 2026-08-27 · **판정** 조건부 출하 가능 · **open BLOCKER** 0 · **open 전체** 0\n\n남은 조건 0건 — 출하 전 충족해야 할 조건은 없다.\n' > "$D/readiness.md"
out=$(bash "$LINT" "$D" 2>&1); rc=$?
if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'readiness.md:'; then
  PASS=$((PASS + 1)); echo "PASS  VPR-26: 공존 readiness.md 의 조건 0건 → 모순 검출 + 위치"
else
  FAIL=$((FAIL + 1)); echo "FAIL  VPR-26: 공존 파일 모순 미검출 (exit=$rc)"
  printf '%s\n' "$out" | sed 's/^/      /'
fi
# VPR-27(8R): 모순 스캔은 표 행·이력 절·합성어에 오발화하면 안 된다(과차단 방지)
mk27() { # <dir> <추가 본문>
  mkdir -p "$1"
  { printf '# 검증 리포트\n\n**갱신** 2026-08-27 · **판정** 조건부 출하 가능 · **open BLOCKER** 0 · **open 전체** 0\n\n## 게이트 (착수 전 확정)\n| 게이트 | 목표 |\n|---|---|\n| G1 | fail 0 |\n\n## 남은 조건\n\n- 담당자가 스모크를 확인한다\n\n'
    printf '%s\n' "$2"
    printf '\n## 결함 대장\n'; thead
  } > "$1/readiness.md"
}
mk27 "$TMP/vpr27a" '| 항목 | 비고 |
|---|---|
| 참고 | 재현 조건: 없음 (항상 재현) |'
check "VPR-27: 표 셀의 「재현 조건: 없음」 → 모순 아님" 0 "대장 무결" "$TMP/vpr27a/readiness.md"
mk27 "$TMP/vpr27b" '## 이력

- 7R: 남은 조건 0건 이었다(그 뒤 새 결함이 나왔다)'
check "VPR-27: 이력 절의 「남은 조건 0건 이었다」 → 모순 아님" 0 "대장 무결" "$TMP/vpr27b/readiness.md"
mk27 "$TMP/vpr27c" '선행 전제조건 0건으로 착수했다.'
check "VPR-27: 합성어 「전제조건 0건」 → 모순 아님" 0 "대장 무결" "$TMP/vpr27c/readiness.md"
D="$TMP/vpr27d"; mkdir -p "$D"
{ printf '# 검증 리포트\n\n**갱신** 2026-08-27 · **판정** 조건부 출하 가능 · **open BLOCKER** 0 · **open 전체** 0\n\n## 게이트 (착수 전 확정)\n| 게이트 | 목표 |\n|---|---|\n| G1 | fail 0 |\n\n## 남은 조건\n\n- 담당자가 스모크를 확인한다\n\n## 결함 대장\n'
  thead
  echo '| B-1 | LOW | 04 | 재현 조건: 없음 — 항상 재현 | open | code | `x.md` | — |'
} > "$D/readiness.md"
check "VPR-27: 대장 행 「한 줄」칸의 조건 문구 → 모순 아님" 0 "대장 무결" "$D/readiness.md"
# VPR-28(9R): 낱말 경계는 합성어만 배제한다 — 강조·인용·괄호·탭 접두의 진짜 모순
# (「**조건 0건**」 등)을 놓치면 조건 0건짜리 조건부 GO 가 게시까지 도달한다(9R 실측 회귀).
_i=0
for _p in '**조건 0건**' '「조건 0건」' '`조건 0건`' '(조건 0건)' '_조건 0건_' '**0 conditions**' "$(printf '\t')조건 0건"; do
  _i=$((_i+1)); D="$TMP/vpr28-$_i"
  mk27 "$D" "$_p"
  check "VPR-28: 기호 접두 모순 $_i ($_p) → 위반" 1 "R11" "$D/readiness.md"
done
# VPR-29(10R): 「조건: 없음」 모순 분기는 조건~콜론 사이의 강조·괄호도 허용해야 한다 —
# 템플릿 권장 표기 「**남은 조건**(조건부일 때만): 없음」이 이 틈으로 게시까지 도달했다.
_i=0
for _p in '**남은 조건**(조건부일 때만): 없음' '**남은 조건**: 없음' '**남은 조건**: 해당 없음'; do
  _i=$((_i+1)); D="$TMP/vpr29-$_i"
  mk27 "$D" "$_p"
  check "VPR-29: 템플릿형 조건 없음 $_i → R11 모순" 1 "R11" "$D/readiness.md"
done
# 반대 방향: 같은 템플릿형에 진짜 조건이 붙으면 통과(vpr07a 와 동일 계열 재확인)
D="$TMP/vpr29-ok"; mk27 "$D" '**남은 조건**(조건부일 때만): ① 담당자가 롤백을 확인한다'
check "VPR-29: 템플릿형 + 진짜 조건 → 통과" 0 "대장 무결" "$D/readiness.md"
# VPR-22(6R): --strict 는 인자 순서와 무관하게 적용돼야 한다 — 예전엔 경로 뒤 --strict 가
# 조용히 무시돼 범위 통제가 사용자 모르게 꺼졌다(vpr 도움말이 가르치는 순서가 그 형태였다).
D="$TMP/vpr22"; mkdir -p "$D/r"; echo "escaped" > "$D/out.log"
{ hdr 0 "조건부 출하 가능"; thead
  echo '| Z-01 | MED | 06 | 탈출 인용 | open | measured | `../out.log:1` | — |'
} > "$D/r/ledger.md"
out=$(bash "$LINT" "$D/r" --strict 2>&1); rc=$?
if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'strict'; then
  PASS=$((PASS + 1)); echo "PASS  VPR-22: 경로 뒤 --strict 도 적용된다"
else
  FAIL=$((FAIL + 1)); echo "FAIL  VPR-22: 경로 뒤 --strict 무시 (exit=$rc)"
fi
out=$(bash "$LINT" "$D/r/ledger.md" --strcit 2>&1); rc=$?
if [ "$rc" = 2 ] && printf '%s' "$out" | grep -q '알 수 없는 옵션'; then
  PASS=$((PASS + 1)); echo "PASS  VPR-22: 미지 옵션(--strcit) → exit 2"
else
  FAIL=$((FAIL + 1)); echo "FAIL  VPR-22: 미지 옵션 무경고 수용 (exit=$rc)"
fi
out=$(bash "$LINT" "$D/r/ledger.md" 잉여인자 2>&1); rc=$?
if [ "$rc" = 2 ] && printf '%s' "$out" | grep -q '대상은 하나만'; then
  PASS=$((PASS + 1)); echo "PASS  VPR-22: 잉여 인자 → exit 2"
else
  FAIL=$((FAIL + 1)); echo "FAIL  VPR-22: 잉여 인자 무경고 수용 (exit=$rc)"
fi
# VPR-16: strict 범위 밖 인용에 「파일 부재」 오발화 금지(실존 파일이다 — strict 메시지가 정본)
D="$TMP/vpr16"; mkdir -p "$D/r"; echo "escaped" > "$D/out.log"
{ hdr 0 "조건부 출하 가능"; thead
  echo '| X-01 | MED | 06 | 탈출 인용 | open | measured | `../out.log:1` | — |'
} > "$D/r/ledger.md"
out=$(bash "$LINT" --strict "$D/r" 2>&1); rc=$?
if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'strict' && ! printf '%s' "$out" | grep -q '파일 부재'; then
  PASS=$((PASS + 1)); echo "PASS  VPR-16: strict 범위 밖 인용에 '파일 부재' 오발화 없음"
else
  FAIL=$((FAIL + 1)); echo "FAIL  VPR-16: 오발화 잔존 또는 미차단 (exit=$rc)"
  printf '%s\n' "$out" | sed 's/^/      /'
fi


# R10 강화: 빈 게이트 표(머리말+구분선만)로는 규칙을 만족시킬 수 없다 — 적대적 실측에서 나온 우회
D="$TMP/r10empty"; mkdir -p "$D/evidence"; echo "out" > "$D/evidence/x.log"
{ printf '# T\n\n**갱신** 2026-08-23 · **판정** 출하 가능 · **open BLOCKER** 0\n\n## 게이트\n| 게이트 | 목표 |\n|---|---|\n\n'; thead
  echo '| A-01 | MED | 05 | x | verified | measured | `evidence/x.log` | `evidence/x.log` |'
} > "$D/ledger.md"
check "R10: 빈 게이트 표는 게이트 표가 아니다" 1 "R10 판정" "$D"

# R11 강화: 「조건 0건」은 조건 명시가 아니라 자기모순이다
D="$TMP/r11zero"; mkdir -p "$D"
{ printf '# T\n\n**갱신** 2026-08-23 · **판정** 조건부 출하 가능 · **open BLOCKER** 0\n\n## 게이트\n| 게이트 | 목표 |\n|---|---|\n| G1 | fail 0 |\n\n남은 조건 0건\n\n'; thead
  echo '| A-01 | MED | 05 | x | open | claimed | 진술 | — |'
} > "$D/ledger.md"
check "R11: 「조건 0건」 → 문법 모순으로 위반" 1 "R11 판정" "$D"

# R11: 「## 조건」 아래 목록만으로도 충족된다(문구 형태를 하나로 강제하지 않는다)
D="$TMP/r11list"; mkdir -p "$D"
{ printf '# T\n\n**갱신** 2026-08-23 · **판정** 조건부 출하 가능 · **open BLOCKER** 0\n\n## 게이트\n| 게이트 | 목표 |\n|---|---|\n| G1 | fail 0 |\n\n## 조건\n- 담당자가 스모크 3동작을 확인한다\n\n'; thead
  echo '| A-01 | MED | 05 | x | open | claimed | 진술 | — |'
} > "$D/ledger.md"
check "R11: 조건 목록 형태도 인정" 0 "대장 무결" "$D"


# ── 코드펜스 · 판정 줄 중복 (적대적 라운드 6) ──────────────────────
# report-template.md 가 골격을 ```markdown 펜스로 보여 준다. 그 골격을 인용한 리포트가
# 곧 「게이트 표가 있다」·「조건이 적혀 있다」·「이 행이 대장 행이다」로 계산됐다.
D="$TMP/fence"; mkdir -p "$D/evidence"; echo "out" > "$D/evidence/x.log"
{ printf '# T\n\n**갱신** 2026-08-23 · **판정** 출하 가능 · **open BLOCKER** 0\n\n예시:\n```markdown\n| 게이트 | 목표 |\n|---|---|\n| G1 | fail 0 |\n```\n\n'; thead
  echo '| A-01 | MED | 05 | x | verified | measured | `evidence/x.log` | `evidence/x.log` |'
} > "$D/ledger.md"
check "펜스 안 게이트 표는 게이트 표가 아니다" 1 "R10 판정" "$D"

D="$TMP/fence2"; mkdir -p "$D/evidence"; echo "out" > "$D/evidence/x.log"
{ printf '# T\n\n**갱신** 2026-08-23 · **판정** 조건부 출하 가능 · **open BLOCKER** 0\n\n## 게이트\n| 게이트 | 목표 |\n|---|---|\n| G1 | fail 0 |\n\n템플릿:\n```markdown\n출하 전 충족 조건 2건: ...\n```\n\n'; thead
  echo '| A-01 | MED | 05 | x | open | claimed | 진술 | — |'
} > "$D/ledger.md"
check "펜스 안 조건 문구는 조건 명시가 아니다" 1 "R11 판정" "$D"

# 펜스 안 예시 대장 행은 데이터 행으로 세지 않는다(행 수로 확인)
D="$TMP/fence3"; mkdir -p "$D/evidence"; echo "out" > "$D/evidence/x.log"
{ printf '# T\n\n**갱신** 2026-08-23 · **판정** 출하 가능 · **open BLOCKER** 0\n\n## 게이트\n| 게이트 | 목표 |\n|---|---|\n| G1 | fail 0 |\n\n예시:\n```markdown\n'; thead
  printf '| EX-99 | BLOCKER | 06 | 예시 행 | open | claimed | 예시 | — |\n```\n\n'; thead
  echo '| A-01 | MED | 05 | x | verified | measured | `evidence/x.log` | `evidence/x.log` |'
} > "$D/ledger.md"
check "펜스 안 예시 행은 대장 행이 아니다" 0 "1 행" "$D"

# 판정 줄이 여럿이면 고르지 말고 거부한다 — 무해한 판정을 앞에 두고 진짜를 아래 숨기는 우회
D="$TMP/dupverdict"; mkdir -p "$D/evidence"; echo "out" > "$D/evidence/x.log"
{ printf '# T\n\n**판정** 판정 불가 · **open BLOCKER** 0\n\n**판정** 출하 가능 · **open BLOCKER** 0\n\n## 게이트\n| 게이트 | 목표 |\n|---|---|\n| G1 | fail 0 |\n\n'; thead
  echo '| A-01 | MED | 05 | x | verified | claimed | 진술 | 확인 |'
} > "$D/ledger.md"
check "판정 줄 2개 → 위반(고르지 않는다)" 1 "판정 줄이 2 개" "$D"


# 디렉터리 모드는 경량 리포트(readiness.md)도 찾아야 한다 — 퀵스타트가 안내하는 경로다
D="$TMP/dirmode"; mkdir -p "$D/evidence"; echo "out" > "$D/evidence/x.log"
{ hdr 0 "출하 가능"; thead
  echo '| A-01 | MED | 05 | x | verified | measured | `evidence/x.log` | `evidence/x.log` |'
} > "$D/readiness.md"
check "디렉터리 모드: readiness.md 도 찾는다" 0 "대장 무결" "$D"

# 심볼릭 링크로 준 대장은 실체 위치를 기준으로 인용을 푼다
if ln -sf "$D/readiness.md" "$TMP/linked.md" 2>/dev/null; then
  check "심볼릭 링크 대장: 실체 기준으로 인용 해석" 0 "대장 무결" "$TMP/linked.md"
fi


# ── ID 형식 (적대적 라운드 10) ─────────────────────────────────────
# 글자접미 ID(SEC-A·UX-A1)가 「-뒤에 숫자」 패턴에 안 맞아 통째로 검사에서 빠졌다.
# 실물 대장에서 39행(19%)이 안 세어지고 있었다 — 그 행의 BLOCKER 도 안 세어진다.
D="$TMP/idsuffix"; mkdir -p "$D/evidence"; echo "out" > "$D/evidence/x.log"
{ hdr 0 "출하 가능"; thead
  echo '| SEC-A | MED | 06 | 글자접미 | verified | measured | `evidence/x.log` | `evidence/x.log` |'
  echo '| UX-A1 | LOW | 03 | 글자+숫자 접미 | verified | code | `evidence/x.log` | 확인 |'
} > "$D/ledger.md"
check "글자접미 ID 도 데이터 행으로 센다" 0 "2 행" "$D"

# 데이터 행처럼 생겼는데 ID 만 어긋나면 조용히 넘기지 않는다
D="$TMP/idbad"; mkdir -p "$D/evidence"; echo "out" > "$D/evidence/x.log"
{ hdr 0 "출하 가능"; thead
  echo '|  | BLOCKER | 06 | ID 가 비었다 | open | measured | `evidence/x.log` | — |'
  echo '| A-01 | MED | 05 | 정상 행 | verified | measured | `evidence/x.log` | `evidence/x.log` |'
} > "$D/ledger.md"
check "ID 형식 어긋난 행 → 조용히 빠지지 않는다" 1 "R3 ID 형식" "$D"


# ID 위반 메시지는 **사람이 실제로 쓴 값**을 보여 줘야 한다(빈 문자열을 보여 주면 못 고친다)
D="$TMP/idmsg"; mkdir -p "$D/evidence"; echo "out" > "$D/evidence/x.log"
{ hdr 0 "출하 가능"; thead
  echo '| SEC_01 | BLOCKER | 06 | 밑줄 ID | open | measured | `evidence/x.log` | — |'
} > "$D/ledger.md"
check "ID 위반 메시지에 원문이 보인다" 1 "SEC_01" "$D"


# ── 라운드 12 ─────────────────────────────────────────────────────
# --strict 는 **실존하는** 리포트 밖 파일만 막는다. 산문의 맨 '/'(「A / B」)까지 절대경로로
# 보고 거짓 위반을 쏟던 것을 고쳤다(실물 대장에서 10건).
D="$TMP/strictprose"; mkdir -p "$D/evidence"; echo "out" > "$D/evidence/x.log"
{ hdr 0 "출하 가능"; thead
  echo '| A-01 | MED | 05 | 입력 / 출력 경계를 본다 | verified | measured | `evidence/x.log` | `evidence/x.log` |'
} > "$D/ledger.md"
out=$(bash "$LINT" --strict "$D" 2>&1); rc=$?
if [ "$rc" = 0 ]; then
  PASS=$((PASS + 1)); echo "PASS  --strict: 산문의 '/' 는 인용이 아니다"
else
  FAIL=$((FAIL + 1)); echo "FAIL  --strict: 산문의 '/' 를 위반으로 잡는다"
fi

# 판정값을 굵게 쓴 형태도 인식한다 — 사람이 흔히 쓰는 형식이다
D="$TMP/boldverdict"; mkdir -p "$D/evidence"; echo "out" > "$D/evidence/x.log"
{ printf '# T\n\n**갱신** 2026-08-23 · **판정** **출하 가능** · **open BLOCKER** 0\n\n## 게이트\n| 게이트 | 목표 |\n|---|---|\n| G1 | fail 0 |\n\n'; thead
  echo '| A-01 | MED | 05 | x | verified | measured | `evidence/x.log` | `evidence/x.log` |'
} > "$D/ledger.md"
check "판정값이 굵게 적혀도 인식한다" 0 "대장 무결" "$D"

# new-report: 날짜 형식·대상 종류 검사 (디렉터리 이름이 되므로 형식을 안 보면 밖에 쓴다)
NEWREP_EARLY="$(cd "$(dirname "$0")/.." && pwd)/bin/new-report.sh"
bash "$NEWREP_EARLY" "$TMP/nr-date" --full --date '../../etc' >/dev/null 2>&1
[ $? = 2 ] && { PASS=$((PASS+1)); echo "PASS  new-report: 날짜 형식 검사"; } \
           || { FAIL=$((FAIL+1)); echo "FAIL  new-report: 이상한 --date 를 통과시켰다"; }
: > "$TMP/nr-file"
bash "$NEWREP_EARLY" "$TMP/nr-file" >/dev/null 2>&1
[ $? = 2 ] && { PASS=$((PASS+1)); echo "PASS  new-report: 대상이 파일이면 안내하고 멈춘다"; } \
           || { FAIL=$((FAIL+1)); echo "FAIL  new-report: 파일 대상 처리"; }


# 도구가 깨졌을 때 **사용자의 표를 탓하지 않는다** — awk 없는 PATH 에서 원인을 제 이름으로 댄다
D="$TMP/nodeps"; mkdir -p "$D/evidence"; echo "out" > "$D/evidence/x.log"
{ hdr 0 "출하 가능"; thead
  echo '| A-01 | MED | 05 | x | verified | measured | `evidence/x.log` | `evidence/x.log` |'
} > "$D/ledger.md"
MINBIN="$TMP/minbin"; mkdir -p "$MINBIN"
for c in bash grep sed mktemp readlink dirname basename cat rm; do
  src=$(command -v "$c" 2>/dev/null) && ln -sf "$src" "$MINBIN/$c" 2>/dev/null
done
out=$(PATH="$MINBIN" "$(command -v bash)" "$LINT" "$D" 2>&1); rc=$?
if [ "$rc" != 0 ] && printf '%s' "$out" | grep -q "필수 도구가 없다"; then
  PASS=$((PASS + 1)); echo "PASS  의존성 부재: 원인을 제 이름으로 댄다"
elif [ "$rc" = 0 ]; then
  FAIL=$((FAIL + 1)); echo "FAIL  의존성 부재인데 통과시켰다(fail-open)"
else
  PASS=$((PASS + 1)); echo "PASS  의존성 부재: 실패로 끝난다(메시지 확인 불가 환경)"
fi


# 결정성 — 같은 대장을 서로 다른 CWD 에서 검사하면 결과가 같아야 한다.
# 축 ⑨(결정성)를 코어로 잠근 스킬이 자기 검증기에서 비결정이면 그 잣대가 무너진다.
D="$TMP/det"; mkdir -p "$D/evidence"; echo "measured output" > "$D/evidence/e.log"
{ hdr 0 "출하 가능"; thead
  echo '| SEC-01 | HIGH | 06 | 유출 | verified | measured | `evidence/e.log` | `evidence/e.log` |'
} > "$D/ledger.md"
DET_OK=1; FIRST=""
for cwd in / /tmp "$HOME" "$D"; do
  out=$(cd "$cwd" && bash "$LINT" "$D/ledger.md" 2>&1); rc=$?
  [ -z "$FIRST" ] && FIRST="$rc"
  [ "$rc" = "$FIRST" ] || DET_OK=0
done
if [ "$DET_OK" = 1 ] && [ "$FIRST" = 0 ]; then
  PASS=$((PASS + 1)); echo "PASS  결정성: CWD 4곳에서 동일 판정"
else
  FAIL=$((FAIL + 1)); echo "FAIL  결정성: CWD 에 따라 판정이 갈린다(first=$FIRST)"
fi

# 저장소 루트 기준 인용 — 실제 대장의 지배적 형태(`core/src/x.ts:12`)가 해석돼야 한다
if command -v git >/dev/null 2>&1; then
  D="$TMP/repo"; mkdir -p "$D/docs/rr" "$D/src"
  ( cd "$D" && git init -q . 2>/dev/null )
  seq 30 > "$D/src/a.ts"
  { hdr 0 "출하 가능"; thead
    echo '| SEC-01 | HIGH | 06 | 유출 | verified | measured | `src/a.ts:12` | `src/a.ts:12` |'
  } > "$D/docs/rr/ledger.md"
  check "저장소 루트 기준 인용도 해석된다" 0 "대장 무결" "$D/docs/rr"
fi

# ══ new-report.sh — 뼈대 생성기 ═══════════════════════════════════
# 이 스캐폴더의 존재 이유는 「형식 오류 0」이다. 그러니 **생성물이 lint 를 통과하는지**가
# 유일하게 중요한 테스트다. 생성물 형식과 lint 가 갈리면 스킬이 만든 리포트를 스킬이
# 거부하는 최악의 조합이 된다.
NEWREP="$(cd "$(dirname "$0")/.." && pwd)/bin/new-report.sh"

D="$TMP/scaffold"; mkdir -p "$D"
out=$(bash "$NEWREP" "$D" 2>&1); rc=$?
if [ "$rc" = 0 ] && [ -f "$D/readiness.md" ] && [ -d "$D/evidence" ]; then
  PASS=$((PASS + 1)); echo "PASS  new-report: 경량 뼈대 생성"
else
  FAIL=$((FAIL + 1)); echo "FAIL  new-report: 경량 뼈대 생성 (exit=$rc)"
fi

# 갓 만든 뼈대는 행이 없으므로 lint 는 exit 2(검사 대상 없음) — 위반이 아니다
check "new-report: 빈 뼈대도 lint 통과(0행 노트)" 0 "대장 0행" "$D/readiness.md"

# 행 하나와 게이트 실측을 채우면 그대로 lint 를 통과해야 한다
echo "run output" > "$D/evidence/t.log"
python3 - "$D/readiness.md" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
s = s.replace("|---|---|---|---|---|---|---|---|\n",
              "|---|---|---|---|---|---|---|---|\n| TEST-01 | MED | 09 | 3회 반복 동일 | verified | measured | `evidence/t.log:1` | `evidence/t.log:1` |\n")
s = s.replace("| G1 테스트 | <스위트> 전건 pass · **fail 0** | 미실시 |",
              "| G1 테스트 | 전건 pass · fail 0 | 0 — `evidence/t.log:1` |")
s = s.replace("**판정** 판정 불가", "**판정** 출하 가능")
open(p, 'w', encoding='utf-8').write(s)
PYEOF
check "new-report: 채운 뼈대는 lint 통과" 0 "대장 무결" "$D/readiness.md"

# 이미 있으면 덮어쓰지 않는다 — 진행 중인 리포트를 날리는 것이 최악의 사고다
before=$(md5 -q "$D/readiness.md" 2>/dev/null || md5sum "$D/readiness.md" | cut -d' ' -f1)
bash "$NEWREP" "$D" >/dev/null 2>&1; rc=$?
after=$(md5 -q "$D/readiness.md" 2>/dev/null || md5sum "$D/readiness.md" | cut -d' ' -f1)
if [ "$rc" = 1 ] && [ "$before" = "$after" ]; then
  PASS=$((PASS + 1)); echo "PASS  new-report: 기존 리포트를 덮어쓰지 않는다"
else
  FAIL=$((FAIL + 1)); echo "FAIL  new-report: 덮어쓰기 방지 (exit=$rc, 내용변경=$([ "$before" = "$after" ] && echo no || echo YES))"
fi

# 정식 모드 — 축 파일 11개 + 대장 + 요약
D2="$TMP/scaffold-full"; mkdir -p "$D2"
bash "$NEWREP" "$D2" --full --date 2026-08-23 >/dev/null 2>&1
FD="$D2/docs/release-readiness/2026-08-23"
axes_n=$(ls "$FD" 2>/dev/null | grep -cE '^(0[1-9]|1[01])-')   # 00-summary.md 는 축이 아니다
if [ -f "$FD/ledger.md" ] && [ -f "$FD/00-summary.md" ] && [ "$axes_n" = 11 ]; then
  PASS=$((PASS + 1)); echo "PASS  new-report: 정식 골격(축 11 + 대장 + 요약)"
else
  FAIL=$((FAIL + 1)); echo "FAIL  new-report: 정식 골격 (축 파일 $axes_n 개)"
fi

# --help 는 exit 0 (사용법을 물어본 사람에게 실패를 돌려주지 않는다)
bash "$NEWREP" --help >/dev/null 2>&1 && { PASS=$((PASS+1)); echo "PASS  new-report: --help → exit 0"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL  new-report: --help"; }
bash "$LINT" --help >/dev/null 2>&1 && { PASS=$((PASS+1)); echo "PASS  ledger-lint: --help → exit 0"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL  ledger-lint: --help"; }

# ══ package.sh — 배포 조립 ════════════════════════════════════════
# 조립본이 「구조만 맞고 안 도는」 물건이면 배포 형태가 있다고 할 수 없다.
# 그래서 구조뿐 아니라 **조립본에서 lint 가 실제로 도는지**까지 본다.
PKG="$(cd "$(dirname "$0")/.." && pwd)/bin/package.sh"
SKILLNAME=$(basename "$(cd "$(dirname "$0")/.." && pwd)")
POUT="$TMP/pkg"

bash "$PKG" "$POUT" >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ] && [ -f "$POUT/.claude-plugin/plugin.json" ] \
   && [ -f "$POUT/.claude-plugin/marketplace.json" ] \
   && [ -f "$POUT/skills/$SKILLNAME/SKILL.md" ]; then
  PASS=$((PASS + 1)); echo "PASS  package: 플러그인 레이아웃 조립"
else
  FAIL=$((FAIL + 1)); echo "FAIL  package: 플러그인 레이아웃 (exit=$rc)"
fi

# 매니페스트가 유효 JSON 이고 버전이 README 이력과 같아야 한다(버전을 두 곳에 적으면 갈린다)
if command -v python3 >/dev/null 2>&1; then
  readme_ver=$(grep -m1 -oE '^- 버전: \*\*[0-9]+\.[0-9]+\.[0-9]+\*\*' "$(dirname "$0")/../README.md" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  hist_ver=$(grep -m1 -oE '^\- \*\*[0-9]+\.[0-9]+\.[0-9]+\*\*' "$(dirname "$0")/../README.md" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  if [ "$readme_ver" = "$hist_ver" ]; then
    PASS=$((PASS + 1)); echo "PASS  package: 버전 정본(헤더)과 이력 맨 위가 일치"
  else
    FAIL=$((FAIL + 1)); echo "FAIL  package: 헤더($readme_ver) ≠ 이력 맨 위($hist_ver) — 배포본이 옛 버전을 달게 된다"
  fi
  pj_ver=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['version'])" "$POUT/.claude-plugin/plugin.json" 2>/dev/null)
  if [ -n "$pj_ver" ] && [ "$pj_ver" = "$readme_ver" ]; then
    PASS=$((PASS + 1)); echo "PASS  package: 매니페스트 유효 JSON · 버전 일치($pj_ver)"
  else
    FAIL=$((FAIL + 1)); echo "FAIL  package: 버전 불일치 (plugin.json=$pj_ver README=$readme_ver)"
  fi
fi

# 조립본의 lint 가 실제로 돈다 — 조립본 자신의 픽스처로 검사한다
PD="$TMP/pkgcheck"; mkdir -p "$PD/evidence"; echo "out" > "$PD/evidence/x.log"
{ hdr 0 "출하 가능"; thead
  echo '| A-01 | MED | 05 | x | verified | measured | `evidence/x.log` | `evidence/x.log` |'
} > "$PD/ledger.md"
if bash "$POUT/skills/$SKILLNAME/bin/ledger-lint.sh" "$PD" >/dev/null 2>&1; then
  PASS=$((PASS + 1)); echo "PASS  package: 조립본 lint 동작"
else
  FAIL=$((FAIL + 1)); echo "FAIL  package: 조립본 lint 가 안 돈다"
fi

# 개발 부산물을 싣지 않는다
if [ ! -d "$POUT/skills/$SKILLNAME/bin/__pycache__" ] && [ ! -d "$POUT/skills/$SKILLNAME/docs" ]; then
  PASS=$((PASS + 1)); echo "PASS  package: 개발 부산물 제외"
else
  FAIL=$((FAIL + 1)); echo "FAIL  package: 개발 부산물이 실렸다"
fi

# 이미 있는 경로는 덮어쓰지 않는다
bash "$PKG" "$POUT" >/dev/null 2>&1
[ $? = 1 ] && { PASS=$((PASS+1)); echo "PASS  package: 기존 출력 경로 덮어쓰기 거부"; } \
           || { FAIL=$((FAIL+1)); echo "FAIL  package: 덮어쓰기 거부 안 함"; }
# 버전 형식이 아니면 조립을 거부한다 — 말이 안 되는 버전의 배포본이 나가지 않게
bash "$PKG" "$TMP/pkgbadver" --version "x.y.z; rm -rf /" >/dev/null 2>&1
[ $? = 2 ] && { PASS=$((PASS+1)); echo "PASS  package: 이상한 버전 문자열 거부"; } \
           || { FAIL=$((FAIL+1)); echo "FAIL  package: 이상한 버전을 그대로 실었다"; }
bash "$PKG" --help >/dev/null 2>&1 && { PASS=$((PASS+1)); echo "PASS  package: --help → exit 0"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL  package: --help"; }

# ══ vpr — 단일 진입점 ═════════════════════════════════════════════
# 진입점이 기능을 두 벌로 만들면(자체 구현) 원본과 갈린다. 그래서 「위임이 실제로
# 도는가」만 본다 — lint 결과가 원본과 같은지, 모르는 동작을 조용히 넘기지 않는지.
VPR="$(cd "$(dirname "$0")/.." && pwd)/bin/vpr"
D="$TMP/vpr"; mkdir -p "$D/evidence"; echo "out" > "$D/evidence/x.log"
{ hdr 0 "출하 가능"; thead
  echo '| A-01 | MED | 05 | x | verified | measured | `evidence/x.log` | `evidence/x.log` |'
} > "$D/ledger.md"
direct=$(bash "$LINT" "$D" 2>&1); drc=$?
viav=$(bash "$VPR" lint "$D" 2>&1); vrc=$?
if [ "$drc" = "$vrc" ] && [ "$direct" = "$viav" ]; then
  PASS=$((PASS + 1)); echo "PASS  vpr: lint 위임이 원본과 같은 결과"
else
  FAIL=$((FAIL + 1)); echo "FAIL  vpr: lint 위임 결과가 다르다 (direct=$drc vpr=$vrc)"
fi
bash "$VPR" >/dev/null 2>&1 && { PASS=$((PASS+1)); echo "PASS  vpr: 인자 없으면 사용법 · exit 0"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL  vpr: 인자 없음 처리"; }
bash "$VPR" bogus >/dev/null 2>&1; [ $? = 2 ] \
  && { PASS=$((PASS+1)); echo "PASS  vpr: 모르는 동작 → exit 2"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL  vpr: 모르는 동작을 조용히 넘겼다"; }
if bash "$VPR" new "$TMP/vpr-new" >/dev/null 2>&1 && [ -f "$TMP/vpr-new/readiness.md" ]; then
  PASS=$((PASS + 1)); echo "PASS  vpr: new 위임"
else
  FAIL=$((FAIL + 1)); echo "FAIL  vpr: new 위임"
fi

# ══ R12 — 형제 리포트 파일의 판정 (감정 F1) ══════════════════
# 정식 모드는 사람이 읽는 판정이 00-summary.md 에 살고 lint 는 대장만 봤다. 그래서 요약만
# 「출하 가능」으로 바꾸면 R6·R8·R10·R11 을 통째로 비켜 exit 0 으로 게시까지 갔다.
mkfull() {  # <디렉터리> <요약 판정> <대장 판정> <대장 open BLOCKER 행 유무>
  local d="$1"; mkdir -p "$d/evidence"; echo "measured out" > "$d/evidence/e.log"
  printf '# 종합 리포트\n\n**갱신** 2026-08-20 · **판정** %s · **open BLOCKER** 0 · **open 전체** 0\n\n## 게이트\n| 게이트 | 목표 | 실측 |\n|---|---|---|\n| G1 | fail 0 | `evidence/e.log:1` |\n' "$2" > "$d/00-summary.md"
  { printf '# 결함 대장 — 테스트\n\n**갱신** 2026-08-20 · **판정** %s · **open BLOCKER** %s · **open 전체** %s\n\n' "$3" "$4" "$4"
    thead
    [ "$4" = 1 ] && echo '| SEC-01 | BLOCKER | 06 | 토큰 평문 노출 | open | claimed | — | — |'
    echo '| OK-02 | LOW | 09 | 사소 | verified | measured | `evidence/e.log` | `evidence/e.log` |'
  } > "$d/ledger.md"
}
D="$TMP/r12-diverge"; mkfull "$D" "출하 가능" "판정 불가" 1
check "R12 요약만 GO · 대장은 판정 불가 → 위반" 1 "R12" "$D"
check "R12 위반은 대장 파일 직접 지정에서도 잡힌다" 1 "R12" "$D/ledger.md"
D="$TMP/r12-agree"; mkfull "$D" "판정 불가" "판정 불가" 0
check "R12 요약·대장 판정 일치 → 통과" 0 "대장 무결" "$D"
D="$TMP/r12-hdr"; mkfull "$D" "판정 불가" "판정 불가" 1
sed -i.bak 's/\*\*open BLOCKER\*\* 1/**open BLOCKER** 1/' "$D/ledger.md"; rm -f "$D"/*.bak
check "R12 요약 헤더 수치가 대장과 다르면 위반" 1 "헤더 open BLOCKER" "$D"
# 과차단 방어 ①: 리포트 가족 밖 문서의 판정 줄은 보지 않는다.
D="$TMP/r12-outsider"; mkfull "$D" "판정 불가" "판정 불가" 0
printf '# README\n\n**판정** 출하 불가 · **open BLOCKER** 7\n' > "$D/README.md"
printf '# 진행상황\n\n**판정** 조건부 출하 가능 · **open BLOCKER** 3\n' > "$D/progress.md"
check "R12 README·progress 의 판정 줄은 무시(과차단 방어)" 0 "대장 무결" "$D"
# 과차단 방어 ②: 형제 파일의 코드펜스 안 예시는 판정이 아니다.
D="$TMP/r12-fence"; mkfull "$D" "판정 불가" "판정 불가" 0
printf '\n```markdown\n**판정** 출하 가능 · **open BLOCKER** 0\n```\n' >> "$D/01-features.md"
check "R12 형제 파일 펜스 안 예시는 판정이 아니다" 0 "대장 무결" "$D"
# 형제 파일에 판정 줄이 여럿이면 정본을 고를 수 없다 — R6 과 같은 이유로 거부.
D="$TMP/r12-dup"; mkfull "$D" "판정 불가" "판정 불가" 0
printf '\n**판정** 출하 가능\n' >> "$D/00-summary.md"
check "R12 형제 파일 판정 줄 중복 → 위반" 1 "R12" "$D"
# 렌더 거부까지 이어지는지 — 게시가 최종 관문이다.
if command -v python3 >/dev/null 2>&1; then
  D="$TMP/r12-render"; mkfull "$D" "출하 가능" "판정 불가" 1
  python3 "$(cd "$(dirname "$0")/.." && pwd)/bin/report-html.py" "$D" >/dev/null 2>&1
  if [ $? = 1 ] && [ ! -f "$D/report.html" ]; then
    PASS=$((PASS + 1)); echo "PASS  R12: 판정이 갈린 리포트는 렌더·게시 거부"
  else
    FAIL=$((FAIL + 1)); echo "FAIL  R12: 판정이 갈린 리포트가 렌더됐다"
  fi
fi

# R12 라운드 17 — 마커 없는 판정·부류 비교. **이 스킬이 권하는 요약 골격**
# (`# 판정` 아래 `> ## 출하 가능`)에 **판정** 마커가 없어 R12 가 통째로 비켜 갔다.
mksum() { mkfull "$1" "판정 불가" "$2" "$3"; printf '%s' "$4" > "$1/00-summary.md"; }
D="$TMP/r12-unmarked"; mksum "$D" "판정 불가" 1 '# 종합 리포트

# 판정
> ## 출하 가능
> 차단 결함 0
'
check "R12 마커 없는 요약 판정(템플릿 골격)도 잡는다" 1 "R12" "$D"
D="$TMP/r12-tablerow"; mksum "$D" "판정 불가" 1 '# 종합 리포트

| 항목 | 값 |
|---|---|
| **판정** | 출하 가능 |
'
check "R12 표 행 안의 판정도 잡는다" 1 "R12" "$D"
D="$TMP/r12-placeholder"; mksum "$D" "판정 불가" 0 '# 종합 리포트

# 판정
> ## <출하 가능 | 조건부 출하 가능 | 출하 불가>
'
check "R12 안 채운 골격 자리표시자는 판정이 아니다" 0 "대장 무결" "$D"
D="$TMP/r12-prose"; mksum "$D" "판정 불가" 0 '# 종합 리포트

# 판정

착수 시점 판정에서 무엇이 어떻게 바뀌었는지 한 문단으로 적는다.
'
check "R12 판정 절 아래 산문은 판정이 아니다(과차단 방어)" 0 "대장 무결" "$D"
# 부류 비교 — 「GO」와 「출하 가능」은 같은 판정이다.
D="$TMP/r12-en"; mkfull "$D" "GO" "출하 가능" 0
check "R12 영문 GO ↔ 한글 출하 가능 (과차단 방어)" 0 "대장 무결" "$D"
D="$TMP/r12-en2"; mkfull "$D" "UNVERIFIABLE" "판정 불가" 0
check "R12 UNVERIFIABLE ↔ 판정 불가 (과차단 방어)" 0 "대장 무결" "$D"
D="$TMP/r12-en3"; mkfull "$D" "NO-GO" "출하 가능" 0
check "R12 부류가 다르면 영문이어도 위반" 1 "R12" "$D"

# ══ R10 게이트 표 판별 — 어휘 의존 제거 (감정 F2) ═════════════
# 「| 기준 | 임계값 | 실측 |」을 R8·R9 는 게이트 표로 세는데 R10 만 「없다」고 했다.
gatehdr() {  # <머리말 첫 칸>
  local d="$1"; mkdir -p "$d/evidence"; echo "out" > "$d/evidence/t.log"
  { printf '# 리포트\n\n**갱신** 2026-08-20 · **판정** 출하 가능 · **open BLOCKER** 0 · **open 전체** 0\n\n| %s | 임계값 | 실측 |\n|---|---|---|\n| G1 | fail 0 | `evidence/t.log:1` |\n\n' "$2"
    thead; echo '| A-01 | LOW | 09 | x | open | claimed | — | — |'
  } > "$d/readiness.md"
}
for h in 항목 기준 게이트 Gate; do
  D="$TMP/gate-$h"; gatehdr "$D" "$h"
  check "R10 게이트 표 머리말 '$h' → 인정(과차단 방어)" 0 "대장 무결" "$D/readiness.md"
done
# 약화되지 않았는지 — 대장 표만 있는 리포트는 여전히 게이트 표 없음이다.
D="$TMP/gate-none"; mkdir -p "$D/evidence"; echo "out" > "$D/evidence/t.log"
{ printf '# 리포트\n\n**갱신** 2026-08-20 · **판정** 출하 가능 · **open BLOCKER** 0 · **open 전체** 0\n\n'
  thead; echo '| A-01 | LOW | 09 | x | verified | measured | `evidence/t.log` | `evidence/t.log` |'
} > "$D/readiness.md"
check "R10 대장 표는 게이트 표가 아니다(약화 방어)" 1 "R10" "$D/readiness.md"
# 빈 게이트 표(데이터 행 0)도 여전히 게이트 표가 아니다.
D="$TMP/gate-empty"; mkdir -p "$D/evidence"; echo "out" > "$D/evidence/t.log"
{ printf '# 리포트\n\n**갱신** 2026-08-20 · **판정** 출하 가능 · **open BLOCKER** 0 · **open 전체** 0\n\n| 항목 | 임계값 | 실측 |\n|---|---|---|\n\n'
  thead; echo '| A-01 | LOW | 09 | x | verified | measured | `evidence/t.log` | `evidence/t.log` |'
} > "$D/readiness.md"
check "R10 빈 게이트 표는 게이트 표가 아니다" 1 "R10" "$D/readiness.md"

# ══ R13 + --axes — 축 선택을 구조로 ══════════════════════════
# 「어떤 축을 볼지」가 산문 규약으로만 있어서, 고른 결과가 리포트 어디에도 기계가 읽는
# 형태로 남지 않았다. 이제 `vpr new --axes` 가 박고 R13 이 정합성을 본다.
axdoc() {  # <디렉터리> <판정> <축 선언 줄> <의도적 제외 줄>
  local d="$1"; mkdir -p "$d/evidence"; echo out > "$d/evidence/e.log"
  { printf '# X 출하 검증\n\n**갱신** 2026-08-20 · **판정** %s · **open BLOCKER** 0 · **open 전체** 0\n%s\n\n## 게이트\n| 게이트 | 목표 | 실측 |\n|---|---|---|\n| G1 | fail 0 | `evidence/e.log:1` |\n\n' "$2" "$3"
    thead; echo '| A-01 | LOW | 04 | x | open | claimed | — | — |'
    printf '\n## 보지 않은 것\n%s\n' "$4"
  } > "$d/readiness.md"
}
D="$TMP/ax-ok"; axdoc "$D" "출하 가능" '대상 `c` · 축: ③④⑤⑥⑦⑧⑨ · 뺀 축: ①②⑩⑪ — 변경이 안 닿는다(감사자 판단)' '가. 의도적 제외: ①②⑩⑪ — 위와 같음'
check "R13 뺀 축에 사유가 있으면 통과" 0 "대장 무결" "$D/readiness.md"
D="$TMP/ax-noreason"; axdoc "$D" "출하 가능" '대상 `c` · 축: ③④⑤⑥⑦⑧⑨ · 뺀 축: ①②⑩⑪' '가. 의도적 제외: <누가·왜>'
check "R13 통과 판정인데 뺀 축 사유 없음 → 위반" 1 "R13" "$D/readiness.md"
D="$TMP/ax-nogo"; axdoc "$D" "출하 불가" '대상 `c` · 축: ③④⑤⑥⑦⑧⑨ · 뺀 축: ①②⑩⑪' '가. 의도적 제외: <누가·왜>'
check "R13 NO-GO 는 사유 부담을 지지 않는다" 0 "대장 무결" "$D/readiness.md"
D="$TMP/ax-core"; axdoc "$D" "출하 가능" '대상 `c` · 축: ③⑤⑦ · 뺀 축: ①②④⑥⑧⑨⑩⑪ — 시간 부족' '가. 의도적 제외: 위'
check "R13 코어 축을 뺀 축에 넣으면 위반" 1 "코어 축" "$D/readiness.md"
D="$TMP/ax-ph"; axdoc "$D" "출하 가능" '대상 `c` · 축: ④⑥⑧⑨ + <변경이 닿는 축> · 뺀 축: <목록 — 사유>' '가. 의도적 제외: <누가·왜>'
check "R13 안 채운 자리표시자는 위반이 아니다" 0 "대장 무결" "$D/readiness.md"
D="$TMP/ax-none"; axdoc "$D" "출하 가능" '' '가. 의도적 제외: <누가·왜>'
check "R13 축 선언 없는 옛 리포트는 검사하지 않는다" 0 "대장 무결" "$D/readiness.md"

# R13 라운드 18 — 신설 규칙을 겨냥한 재사격에서 나온 것들.
D="$TMP/ax-digit"; axdoc "$D" "출하 가능" '축: 3,5,7 · 뺀 축: 1,2,4,6,8,9,10,11 — 시간 부족' '가. 의도적 제외: 위'
check "R13 코어를 숫자로 빼도 잡는다" 1 "코어 축" "$D/readiness.md"
D="$TMP/ax-syn"; axdoc "$D" "출하 가능" '축: ③⑤⑦ · 제외 축: ①②④ — 사유' '가. 의도적 제외: 위'
check "R13 「제외 축」 같은 낱말도 선언으로 본다" 1 "코어 축" "$D/readiness.md"
D="$TMP/ax-hyphen"; axdoc "$D" "출하 가능" '축: ③④⑤⑥⑦⑧⑨ · 뺀 축: ①②⑩⑪ - 변경이 안 닿는다' '가. 의도적 제외: <누가·왜>'
check "R13 붙임표 사유도 사유다(과차단 방어)" 0 "대장 무결" "$D/readiness.md"
D="$TMP/ax-paren"; axdoc "$D" "출하 가능" '축: ③④⑤⑥⑦⑧⑨ · 뺀 축: ①②⑩⑪(변경이 안 닿음)' '가. 의도적 제외: <누가·왜>'
check "R13 괄호 사유도 사유다(과차단 방어)" 0 "대장 무결" "$D/readiness.md"
# 도구가 깨진 채로 「통과」가 나오지 않는지 — sed/awk 오류가 stderr 로 새면서 검사만
# 조용히 비는 상태를 실제로 만들었다(라운드 18). 통과 출력에 도구 오류가 섞이면 실패다.
D="$TMP/ax-clean"; axdoc "$D" "출하 가능" '축: ③④⑤⑥⑦⑧⑨ · 뺀 축: ①②⑩⑪ — 사유 있음' '가. 의도적 제외: 위'
cleanout=$(bash "$LINT" "$D/readiness.md" 2>&1)
if printf '%s' "$cleanout" | grep -qE '^(sed|awk|grep|bash):|RE error|syntax error'; then
  FAIL=$((FAIL+1)); echo "FAIL  lint 출력에 도구 오류가 섞였다"; printf '%s\n' "$cleanout" | sed 's/^/      /'
else PASS=$((PASS+1)); echo "PASS  lint 출력에 도구 오류가 없다"; fi

NR="$(cd "$(dirname "$0")/.." && pwd)/bin/new-report.sh"
D="$TMP/axgen"; bash "$NR" "$D" --axes 3,5,7 >/dev/null 2>&1
if grep -q '축: ③④⑤⑥⑦⑧⑨ · 뺀 축: ①②⑩⑪' "$D/readiness.md" 2>/dev/null; then
  PASS=$((PASS+1)); echo "PASS  --axes: 코어 자동 포함 · 뺀 축 선언 생성"
else FAIL=$((FAIL+1)); echo "FAIL  --axes: 축 선언 생성"; fi
if grep -q '가. 의도적 제외: ①②⑩⑪' "$D/readiness.md" 2>/dev/null; then
  PASS=$((PASS+1)); echo "PASS  --axes: 「의도적 제외」에도 뺀 축이 박힌다"
else FAIL=$((FAIL+1)); echo "FAIL  --axes: 의도적 제외 미기재"; fi
D="$TMP/axfull"; bash "$NR" "$D" --full --axes 5,7 >/dev/null 2>&1
FD=$(ls -d "$D"/docs/release-readiness/*/ 2>/dev/null | head -1)
n=$(ls "$FD" 2>/dev/null | grep -cE '^(0[1-9]|1[01])-')
if [ "$n" = 6 ] && [ ! -f "$FD/01-features.md" ] && [ -f "$FD/05-perf.md" ]; then
  PASS=$((PASS+1)); echo "PASS  --axes: 정식 모드는 고른 축의 파일만 만든다"
else FAIL=$((FAIL+1)); echo "FAIL  --axes: 정식 모드 축 파일 수가 $n"; fi
if grep -q '\*\*감사 모델\*\*' "$FD/05-perf.md" 2>/dev/null && grep -q '\*\*위임 도구\*\*' "$FD/05-perf.md" 2>/dev/null; then
  PASS=$((PASS+1)); echo "PASS  축 파일 뼈대가 감사 모델·위임 도구를 요구한다"
else FAIL=$((FAIL+1)); echo "FAIL  축 파일 뼈대에 감사 모델·위임 도구 자리가 없다"; fi
bash "$NR" "$TMP/axbad" --axes 12 >/dev/null 2>&1; [ $? = 2 ] \
  && { PASS=$((PASS+1)); echo "PASS  --axes: 범위 밖 번호 → exit 2"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL  --axes: 범위 밖 번호를 받았다"; }
bash "$NR" "$TMP/axbad2" --axes "" >/dev/null 2>&1; [ $? = 2 ] \
  && { PASS=$((PASS+1)); echo "PASS  --axes: 빈 목록 → exit 2"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL  --axes: 빈 목록을 받았다"; }
# 생성물이 곧바로 lint 를 통과하는지 — 스캐폴더와 규칙이 갈리면 최악이다.
D="$TMP/axlint"; bash "$NR" "$D" --axes 5 >/dev/null 2>&1
printf '| A-01 | LOW | 05 | x | open | claimed | — | — |\n' >> "$D/readiness.md"
check "--axes 생성물이 lint 를 통과한다" 0 "대장 무결" "$D/readiness.md"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
