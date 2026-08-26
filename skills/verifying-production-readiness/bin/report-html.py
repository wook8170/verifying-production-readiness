#!/usr/bin/env python3
"""report-html — 출하 검증 리포트를 자체완결 HTML 로 렌더한다.

사용: report-html.py <리포트 디렉터리 | readiness.md> [-o 출력.html]
  디렉터리: 00-summary.md + ledger.md + evidence/ 를 합쳐 렌더 (정식 모드)
  파일:     그 파일 하나를 렌더 (경량 모드). evidence/ 는 같은 디렉터리에서 찾는다.
  출력 기본값: <입력 디렉터리>/report.html

생성물은 Artifact 도구로 게시하기 위한 것이다 — <title>+<style>+본문만 담고
문서 골격(<html> 등)은 게시 시점에 래핑된다. 외부 요청 없음(이미지는 data URI).
이미지 개별 1.5MB·총 7.5MB(base64 팽창 후 약 10MB) 초과분은 임베드하지 않고
이름만 남긴다(16MB 게시 한도 대비 여유 확보).

렌더 전에 같은 디렉터리의 ledger-lint.sh 로 대장을 자동 검사한다 — lint 위반(exit 1)
대장은 렌더를 거부한다(판정 무효 리포트의 게시를 기계로 차단).
종료코드: 0=성공 · 1=lint 위반으로 렌더 거부 · 2=입력/인자 오류
"""
import base64, html, re, subprocess, sys
from pathlib import Path

IMG_EXT = {".png": "png", ".jpg": "jpeg", ".jpeg": "jpeg", ".gif": "gif", ".webp": "webp"}
IMG_EACH_MAX = 1_500_000
IMG_TOTAL_MAX = 7_500_000   # base64 팽창(4/3) 후 약 10MB — 16MB 게시 한도 대비 여유

BADGES = {"BLOCKER", "HIGH", "MED", "LOW", "open", "fixing", "fixed",
          "verified", "rejected", "deferred", "claimed", "code", "measured"}

def read(p):
    # 비 UTF-8 입력에서 죽지 않는다 — 깨진 바이트는 U+FFFD 로 대체하고 렌더는 계속한다.
    return p.read_text(encoding="utf-8", errors="replace")

def inline(s):
    # 코드 스팬을 먼저 분리해 안쪽에는 볼드 치환이 닿지 않게 한다.
    out = []
    for part in re.split(r"(`[^`]+`)", s):
        if len(part) > 1 and part.startswith("`") and part.endswith("`"):
            out.append(f"<code>{html.escape(part[1:-1], quote=False)}</code>")
        else:
            p = html.escape(part, quote=False)
            out.append(re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", p))
    return "".join(out)

def cell(s):
    # 셀 전체가 고정 어휘와 일치하면 배지로. 설명 셀이 우연히 한 단어 어휘와 같은 극단
    # 케이스는 배지로 렌더되는 트레이드오프를 수용한다(열 위치 무관 렌더러를 유지).
    t = s.strip()
    if t in BADGES:
        return f'<span class="badge b-{t}">{t}</span>'
    return inline(t)

def split_row(r):
    # 앞뒤 파이프만 한 겹 벗긴다 — strip("|") 은 끝의 빈 셀(`| A ||`)을 삼킨다.
    r = r.strip()
    if r.startswith("|"):
        r = r[1:]
    if r.endswith("|"):
        r = r[:-1]
    return r.split("|")

def md_to_html(text):
    out, table = [], []
    code_buf = None
    def flush_table():
        if not table:
            return
        rows = [r for r in table if not re.match(r"^\|[\s|:-]+\|$", r)]
        out.append('<div class="tbl"><table>')
        for i, r in enumerate(rows):
            tag = "th" if i == 0 else "td"
            out.append("<tr>" + "".join(f"<{tag}>{cell(c)}</{tag}>" for c in split_row(r)) + "</tr>")
        out.append("</table></div>")
        table.clear()
    def flush_code():
        # 한 문자열로 내보낸다 — <code> 뒤에 개행이 끼면 첫 줄이 빈 줄로 렌더된다.
        out.append("<pre><code>" + "\n".join(code_buf) + "</code></pre>")
    for line in text.splitlines():
        if line.startswith("```"):
            flush_table()
            if code_buf is None:
                code_buf = []
            else:
                flush_code()
                code_buf = None
            continue
        if code_buf is not None:
            code_buf.append(html.escape(line))
            continue
        if line.startswith("|"):
            table.append(line)
            continue
        flush_table()
        m = re.match(r"^(#{1,6})\s+(.*)", line)
        if m:
            n = min(len(m.group(1)) + 1, 6)   # 문서 h1 은 페이지 h1 아래로
            out.append(f"<h{n}>{inline(m.group(2))}</h{n}>")
        elif line.startswith(">"):
            q = re.sub(r"^>\s?", "", line)
            q = re.sub(r"^#{1,6}\s+", "", q)   # 인용 안 헤딩은 강조 텍스트로
            out.append(f"<div class='quote'>{inline(q)}</div>")
        elif line.startswith("- "):
            out.append(f"<div class='li'>• {inline(line[2:])}</div>")
        elif line.strip():
            out.append(f"<p>{inline(line)}</p>")
    flush_table()
    if code_buf is not None:
        flush_code()
    return "\n".join(out)

def first_heading(text):
    # 제목 후보는 코드펜스 밖의 첫 h1 만 — 템플릿 예시 골격 안의 `#` 을 집지 않는다.
    in_code = False
    for line in text.splitlines():
        if line.startswith("```"):
            in_code = not in_code
            continue
        if in_code:
            continue
        m = re.match(r"^#\s+(.+)$", line)
        if m:
            return re.sub(r"[*`]", "", m.group(1)).strip()
    return None

def embed_evidence(ev_dir):
    if not ev_dir.is_dir():
        return ""
    out, total = [], 0
    for f in sorted(ev_dir.iterdir()):
        mime = IMG_EXT.get(f.suffix.lower())
        if not mime or not f.is_file():
            continue
        size = f.stat().st_size
        if size > IMG_EACH_MAX or total + size > IMG_TOTAL_MAX:
            out.append(f"<p><code>{html.escape(f.name)}</code> — {size:,}B, 한도 초과로 미임베드</p>")
            continue
        total += size
        b64 = base64.b64encode(f.read_bytes()).decode()
        out.append(f"<figure><img src='data:image/{mime};base64,{b64}' alt='{html.escape(f.name)}'>"
                   f"<figcaption>{html.escape(f.name)}</figcaption></figure>")
    return f"<h2>Evidence</h2>\n{''.join(out)}" if out else ""

CSS = """<style>
:root{--bg:#fff;--fg:#1a1a1a;--mut:#6b7280;--line:#e5e7eb;--card:#f8fafc;
  --red:#b91c1c;--amber:#b45309;--green:#15803d;--gray:#6b7280;--redbg:#fef2f2;
  --amberbg:#fffbeb;--greenbg:#f0fdf4;--graybg:#f3f4f6}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#111418;--fg:#e5e7eb;
  --mut:#9ca3af;--line:#2a2f36;--card:#1a1f26;--red:#f87171;--amber:#fbbf24;--green:#4ade80;
  --gray:#9ca3af;--redbg:#3b1213;--amberbg:#3a2b0a;--greenbg:#122b18;--graybg:#252a31}}
:root[data-theme="dark"]{--bg:#111418;--fg:#e5e7eb;--mut:#9ca3af;--line:#2a2f36;--card:#1a1f26;
  --red:#f87171;--amber:#fbbf24;--green:#4ade80;--gray:#9ca3af;--redbg:#3b1213;--amberbg:#3a2b0a;
  --greenbg:#122b18;--graybg:#252a31}
body{background:var(--bg);color:var(--fg);font:15px/1.65 -apple-system,'Apple SD Gothic Neo',
  'Noto Sans KR',sans-serif;max-width:960px;margin:0 auto;padding:2rem 1.25rem}
h1,h2,h3,h4{line-height:1.3}h2{margin-top:2rem;border-bottom:1px solid var(--line);padding-bottom:.3rem}
code{background:var(--card);border:1px solid var(--line);border-radius:4px;padding:.1em .35em;font-size:.9em}
pre{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:.8rem;overflow-x:auto}
pre code{border:0;background:none;padding:0}
.tbl{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:.92em}
th,td{border:1px solid var(--line);padding:.35rem .55rem;text-align:left;vertical-align:top}
th{background:var(--card)}
.badge{display:inline-block;border-radius:999px;padding:.05em .6em;font-size:.85em;font-weight:600}
.b-BLOCKER,.b-open{color:var(--red);background:var(--redbg)}
.b-HIGH,.b-fixing,.b-fixed,.b-claimed{color:var(--amber);background:var(--amberbg)}
.b-verified,.b-measured{color:var(--green);background:var(--greenbg)}
.b-MED,.b-LOW,.b-rejected,.b-deferred,.b-code{color:var(--gray);background:var(--graybg)}
figure{margin:1rem 0}figure img{max-width:100%;border:1px solid var(--line);border-radius:8px}
figcaption{color:var(--mut);font-size:.85em}p{margin:.4rem 0}.li{margin:.15rem 0 .15rem .5rem}
.quote{border-left:3px solid var(--green);background:var(--card);padding:.5rem .9rem;margin:.3rem 0;font-weight:600}
.quote+.quote{margin-top:-.3rem;font-weight:400}
</style>"""

def main():
    args = sys.argv[1:]
    out_path = None
    if "-o" in args:
        i = args.index("-o")
        if i + 1 >= len(args):
            print("-o 에는 출력 경로가 필요하다"); print(__doc__.strip()); return 2
        out_path = Path(args[i + 1])
        del args[i:i + 2]
    if len(args) != 1:
        print(__doc__.strip()); return 2
    target = Path(args[0])
    if target.is_dir():
        parts = [p for p in (target / "00-summary.md", target / "ledger.md") if p.is_file()]
        if not parts:
            print(f"렌더할 파일이 없습니다(00-summary.md·ledger.md): {target}"); return 2
        base, out = target, out_path or target / "report.html"
        ledger = target / "ledger.md"
    elif target.is_file():
        parts, base, out = [target], target.parent, out_path or target.parent / "report.html"
        ledger = target
    else:
        print(f"대상이 없습니다: {target}"); return 2
    # lint 게이트 — 「lint 미통과 대장은 게시하지 않는다」를 자기보고가 아니라 기계로 강제.
    # exit 2(대장 아님·데이터 행 없음)는 렌더를 막지 않는다 — 위반(exit 1)만 거부한다.
    lint = Path(__file__).resolve().parent / "ledger-lint.sh"
    if ledger.is_file() and lint.is_file():
        r = subprocess.run(["bash", str(lint), str(ledger)], capture_output=True, text=True)
        if r.returncode == 1:
            sys.stdout.write(r.stdout + r.stderr)
            print("✗ lint 위반 대장 — 렌더·게시 거부(판정 무효 리포트는 공유 금지)")
            return 1
    title = "출하 검증 리포트"
    for p in parts:
        h = first_heading(read(p))
        if h:
            title = h; break
    body = "\n<hr>\n".join(md_to_html(read(p)) for p in parts)
    doc = (f"<title>{html.escape(title)}</title>\n{CSS}\n<h1>{html.escape(title)}</h1>\n"
           f"{body}\n{embed_evidence(base / 'evidence')}")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(doc, encoding="utf-8")
    print(f"✓ {out} ({out.stat().st_size:,}B) — Artifact 도구로 게시하라(갱신은 같은 경로 재게시)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
