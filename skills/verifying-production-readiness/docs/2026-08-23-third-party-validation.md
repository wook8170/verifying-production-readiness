# Gaea-Homepage (Angular) 출하 검증 — 경량 모드

**갱신** 2026-08-23 · **판정** 출하 불가 · **open BLOCKER** 1 · **open 전체** 3
대상 `master@132커밋` · 축: ⑥⑦⑧⑨ + 닿는 축 없음 · 뺀 축: ①②③⑤⑩⑪ — 스킬 검증용 시간상자(30분) 감사라 범위를 좁혔다. **④ E2E 는 코어 축이지만 실측 불가**(아래 「보지 않은 것」).

이 리포트는 **스킬(verifying-production-readiness) 실효성 검증**을 위해, 이 스킬이 한 번도 본 적 없는 제3의 코드베이스(Angular SPA, 838파일)에 경량 모드를 적용해 만든 것이다. 뼈대는 `bin/new-report.sh` 가 생성했다.

## 게이트 (착수 전 확정 — Iron Rule 1)
| 게이트 | 목표 (측정 전 확정) | 실측 |
|---|---|---|
| G1 공급망 | 프로덕션 도달 high/critical **0** | **3 high** — `third-party-validation-evidence/audit.log:3` |
| G2 이력 비밀 | 전 이력 leak **0** | 0 (110커밋 스캔) — `third-party-validation-evidence/secrets.log:3` |
| G3 재현성 | 런타임 버전 고정(engines) 존재 | 없음 — `third-party-validation-evidence/audit-detail.log:5` |
| G4 빌드·테스트 | 빌드 성공 · 테스트 fail 0 | 미실시 |
| G5 E2E | 시나리오 실패 0 | 미실시 |

## 결함 대장
| ID | 심각도 | 축 | 한 줄 | 상태 | 근거등급 | 근거 | 닫은 증거 |
|---|---|---|---|---|---|---|---|
| SUP-01 | BLOCKER | ⑦ | Angular 12.2(2021) 고정 — `@angular/core`·`common`·`compiler` 에 **프로덕션 도달 high 3건**(i18n XSS · SVG 속성 XSS · XSRF 토큰 유출 · formatDate DoS). 공개 홈페이지라 XSS 는 그대로 사용자 임팩트다 | open | measured | `third-party-validation-evidence/audit-detail.log:1` | — |
| OPS-02 | MED | ⑨ | `package.json` 에 `engines` 가 없어 Node/npm 버전이 고정되지 않는다 — Angular 12 는 Node 16 대를 전제하므로 최신 Node 에서 빌드가 갈릴 수 있다(재현성 위험) | open | code | `third-party-validation-evidence/audit-detail.log:5` | — |
| QA-03 | LOW | ④ | 스펙 파일 20개 / TS 소스 64개 — 커버리지 자체는 측정하지 않았고, 이 비율만으로 부족을 단정하지 않는다. 확인 필요 항목으로 남긴다 | open | code | `third-party-validation-evidence/audit-detail.log:7` | — |
| SEC-04 | — | ⑥ | 추적되는 `.env` 파일 0개 · gitleaks 전 이력 leak 0 (문제없음) | verified | measured | `third-party-validation-evidence/secrets.log:3` | `third-party-validation-evidence/secrets.log:3` |

## 보지 않은 것
가. 의도적 제외: ①기능 ②백엔드 ③UI·접근성 ⑤성능 ⑩배포 ⑪관측성 — 스킬 검증 목적의 시간상자 감사(감사자 판단).
나. 확인 불가: **④ E2E·빌드·테스트** — `node_modules` 가 없고, 남의 프로젝트에 의존성을 설치하는 것은 이 감사의 권한 밖이다. 소유자가 `npm ci` 된 작업본(또는 CI 아티팩트)을 주면 G4·G5 를 잰다.

## 조건
해당 없음 — 판정이 「출하 불가」다. SUP-01 을 닫으면(Angular 최신 패치 라인으로 상향) 재판정 대상이 된다.
