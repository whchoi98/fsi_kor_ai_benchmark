#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# FSI 한국어 AI 안전성 벤치마크 — 인터랙티브 실행기
# ──────────────────────────────────────────────────────────────────────────────
# 사용:
#   ./run_benchmark.sh              인터랙티브 메뉴
#   ./run_benchmark.sh --help       도움말
#   ./run_benchmark.sh --report     기존 결과로 리포트만 재생성
#   ./run_benchmark.sh --resume     중단된 실행 이어가기 (--reset 없이)
#   ./run_benchmark.sh --quick      최소 5건만 dry-run (모델 호환 확인용)
#   ./run_benchmark.sh --submit     제출용 zip 패키지 생성 (필수 2개 파일만)
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── ANSI 색상 ────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
    BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; BOLD=""; DIM=""; RESET=""
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── 모델 프리셋 (id | region | 표시명) ──────────────────────────────────────
PRESETS=(
    "global.anthropic.claude-sonnet-4-5-20250929-v1:0|ap-northeast-2|Sonnet 4.5 (global CRIS, 서울)"
    "global.anthropic.claude-sonnet-4-6|ap-northeast-2|Sonnet 4.6 (global CRIS, 서울)"
    "apac.anthropic.claude-3-5-sonnet-20241022-v2:0|ap-northeast-2|Sonnet 3.5 v2 (apac, 서울)"
    "apac.anthropic.claude-sonnet-4-20250514-v1:0|ap-northeast-2|Sonnet 4.0 (apac, 서울 — 계정에 따라 차단됨)"
    "eu.anthropic.claude-sonnet-4-20250514-v1:0|eu-west-1|Sonnet 4.0 (eu, Ireland — fallback)"
)

# ── 출력 헬퍼 ────────────────────────────────────────────────────────────────
say()    { printf "%s\n" "$*"; }
info()   { printf "%s[i]%s %s\n"  "$BLUE"   "$RESET" "$*"; }
ok()     { printf "%s[✓]%s %s\n"  "$GREEN"  "$RESET" "$*"; }
warn()   { printf "%s[!]%s %s\n"  "$YELLOW" "$RESET" "$*"; }
err()    { printf "%s[✗]%s %s\n"  "$RED"    "$RESET" "$*" >&2; }
banner() {
    printf "%s%s\n" "$BOLD" "$BLUE"
    printf "============================================================\n"
    printf "  FSI 한국어 AI 안전성 벤치마크\n"
    printf "  JailbreakBench(KR) 300건 기반 모델 변경 A/B 검증\n"
    printf "============================================================%s\n\n" "$RESET"
}

usage() {
    cat <<EOF
${BOLD}사용법${RESET}
  $0                    인터랙티브 모드 (기본)
  $0 --help|-h          이 도움말
  $0 --report           호출 없이 기존 출력으로 리포트만 재생성
  $0 --resume           중단된 실행 이어가기 (progress 보존)
  $0 --quick            5건만 dry-run (모델 동작 확인용)
  $0 --only-before      변경 전 모델만 실행
  $0 --only-after       변경 후 모델만 실행
  $0 --submit           제출용 zip 패키지 생성 (필수 2개 파일만)

${BOLD}인터랙티브 모드 흐름${RESET}
  1) Bedrock API 키 확인 (또는 입력)
  2) 변경 전 / 변경 후 모델 선택 (프리셋 또는 직접 입력)
  3) 사전 호출 테스트 (각 모델에 1건씩)
  4) 실행 계획 확인 후 600 호출 풀런
  5) 검증 + comparison_report.md 자동 생성

${BOLD}환경 변수${RESET}
  AWS_BEARER_TOKEN_BEDROCK    Bedrock API 키 (없으면 인터랙티브로 입력 받음)
  AWS_PROFILE / AWS_*         IAM 자격증명 (대안)

${BOLD}생성 파일${RESET}
  output/모델변경전.jsonl
  output/모델변경후.jsonl
  output/comparison_report.md
  output/*.metadata.jsonl   (stop_reason 사이드카)
EOF
}

# ── 사전 점검 ────────────────────────────────────────────────────────────────
preflight_env() {
    if ! command -v python3 >/dev/null; then
        err "python3가 PATH에 없습니다."; exit 1
    fi
    if ! python3 -c "import boto3" 2>/dev/null; then
        err "boto3 미설치. 다음 명령으로 설치하세요:"
        echo "    pip install boto3"
        exit 1
    fi
    if [[ ! -f fsi_bench.py ]]; then
        err "fsi_bench.py가 같은 디렉터리에 없습니다."; exit 1
    fi
    if [[ ! -f doc/jailbreakbench.jsonl ]]; then
        err "doc/jailbreakbench.jsonl 입력 데이터셋이 없습니다."; exit 1
    fi
}

ensure_credentials() {
    if [[ -n "${AWS_BEARER_TOKEN_BEDROCK:-}" ]]; then
        ok "AWS_BEARER_TOKEN_BEDROCK 환경변수 인식 (Bedrock API key)"
        return
    fi
    if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] || [[ -f "$HOME/.aws/credentials" ]] \
       || [[ -n "${AWS_PROFILE:-}" ]] || curl -sf -m 1 http://169.254.169.254/latest/meta-data/iam/info >/dev/null 2>&1; then
        ok "AWS IAM 자격증명 사용 가능 (env / profile / IMDS role)"
        return
    fi
    warn "Bedrock 자격증명을 찾지 못했습니다."
    say
    say "  1) Bedrock API 키 입력 (이 세션에서만 사용, 화면에 표시되지 않음)"
    say "  2) 종료 (자격증명 설정 후 다시 실행)"
    read -rp "선택 [1-2, 기본 1]: " ch; ch="${ch:-1}"
    if [[ "$ch" == "1" ]]; then
        read -rsp "Bedrock API 키: " key; say
        if [[ -z "$key" ]]; then err "빈 키. 중단."; exit 1; fi
        export AWS_BEARER_TOKEN_BEDROCK="$key"
        ok "키 적용됨 (현재 셸 세션 한정)"
    else
        exit 0
    fi
}

# ── 메뉴 ─────────────────────────────────────────────────────────────────────
show_presets() {
    local i=1
    for p in "${PRESETS[@]}"; do
        IFS='|' read -r mid region desc <<< "$p"
        printf "  %s%d)%s %s\n" "$BOLD" "$i" "$RESET" "$desc"
        printf "      %s%s%s @ %s\n" "$DIM" "$mid" "$RESET" "$region"
        ((i++))
    done
    printf "  %s%d)%s 직접 입력 (custom)\n" "$BOLD" "$i" "$RESET"
}

# Reads from stdin, writes choice "mid|region" to stdout
choose_model() {
    local label="$1" default_idx="$2"
    {
        printf "\n%s%s%s\n" "$BOLD" "$label" "$RESET"
        show_presets
    } >&2
    local n="${#PRESETS[@]}"
    local custom_idx=$((n + 1))
    read -rp "선택 [기본 $default_idx]: " choice >&2
    choice="${choice:-$default_idx}"
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt "$custom_idx" ]]; then
        err "잘못된 선택: $choice"; return 1
    fi
    if [[ "$choice" -eq "$custom_idx" ]]; then
        local mid region
        read -rp "  모델 ID (예: global.anthropic.claude-sonnet-4-6): " mid >&2
        read -rp "  리전 [ap-northeast-2]: " region >&2
        region="${region:-ap-northeast-2}"
        if [[ -z "$mid" ]]; then err "빈 모델 ID"; return 1; fi
        printf "%s|%s\n" "$mid" "$region"
    else
        local idx=$((choice - 1))
        IFS='|' read -r mid region _ <<< "${PRESETS[$idx]}"
        printf "%s|%s\n" "$mid" "$region"
    fi
}

# ── 사전 호출 테스트 (1건) ───────────────────────────────────────────────────
smoke_test() {
    local mid="$1" region="$2"
    printf "  %s%s%s @ %s ... " "$DIM" "$mid" "$RESET" "$region"
    local out rc
    out=$(python3 - <<PY 2>&1
import boto3, json, sys, time
rt = boto3.client('bedrock-runtime', region_name='$region')
body = json.dumps({'anthropic_version':'bedrock-2023-05-31','max_tokens':16,
                   'messages':[{'role':'user','content':'한 단어로 답: 안녕'}]})
t0=time.time()
try:
    r = rt.invoke_model(modelId='$mid', body=body)
    o = json.loads(r['body'].read())
    txt = ''.join(c.get('text','') for c in o.get('content',[]))
    print(f"OK {time.time()-t0:.2f}s text={txt!r}")
except Exception as e:
    print(f"FAIL {type(e).__name__}: {str(e)[:160]}")
    sys.exit(1)
PY
) || rc=$? || true
    if [[ "${rc:-0}" -eq 0 ]]; then
        printf "%s✓%s %s\n" "$GREEN" "$RESET" "$out"
        return 0
    else
        printf "%s✗%s\n    %s%s%s\n" "$RED" "$RESET" "$RED" "$out" "$RESET"
        return 1
    fi
}

# ── 확인 ─────────────────────────────────────────────────────────────────────
confirm_plan() {
    local b_mid="$1" b_region="$2" a_mid="$3" a_region="$4" only="${5:-both}" limit="${6:-300}"
    local total=$((limit * 2))
    [[ "$only" == "before" || "$only" == "after" ]] && total=$limit
    say
    printf "%s%s실행 계획%s\n" "$BOLD" "$CYAN" "$RESET"
    printf "  변경 전 (before): %s%s%s @ %s\n" "$YELLOW" "$b_mid" "$RESET" "$b_region"
    printf "  변경 후 (after):  %s%s%s @ %s\n" "$YELLOW" "$a_mid" "$RESET" "$a_region"
    printf "  실행 범위: %s%s%s\n" "$BOLD" "$only" "$RESET"
    printf "  프롬프트 수: %d / 모델, 총 %d 호출\n" "$limit" "$total"
    printf "  예상 시간: 약 %d분 (8 동시 호출)\n" $(( (limit + 60) / 60 ))
    printf "  결과 위치: %soutput/%s\n" "$DIM" "$RESET"
    say
    read -rp "${BOLD}진행할까요? [y/N]: ${RESET}" yn
    [[ "$yn" =~ ^[Yy]$ ]]
}

# ── 실행 ─────────────────────────────────────────────────────────────────────
run_full() {
    local b_mid="$1" b_region="$2" a_mid="$3" a_region="$4"
    local only="${5:-both}" limit="${6:-}" reset="${7:-1}"
    local args=(
        --before-model "$b_mid" --before-region "$b_region"
        --after-model "$a_mid"  --after-region "$a_region"
        --only "$only"
    )
    [[ "$reset" == "1" ]] && args+=(--reset)
    [[ -n "$limit" ]] && args+=(--limit "$limit")
    say
    info "실행 명령:  python3 fsi_bench.py ${args[*]}"
    say
    python3 -u fsi_bench.py "${args[@]}"
}

# ── 제출 패키징 (필수 2개 파일만 zip) ──────────────────────────────────────
make_submission() {
    local stamp pkg_full pkg_min
    stamp="$(date +%Y%m%d_%H%M%S)"
    mkdir -p output
    pkg_min="output/submission_${stamp}.zip"
    pkg_full="output/submission_full_${stamp}.zip"

    # Python으로 검증·패키징 (NFD 파일명 안전 처리, NFC로 정규화해 zip에 저장)
    python3 - "$pkg_min" "$pkg_full" <<'PY'
import json, os, sys, unicodedata, zipfile
pkg_min, pkg_full = sys.argv[1], sys.argv[2]
out_dir = "output"

REQUIRED = ["모델변경전.jsonl", "모델변경후.jsonl"]
EXTRAS   = ["모델변경전.jsonl.metadata.jsonl",
            "모델변경후.jsonl.metadata.jsonl",
            "comparison_report.md"]

# 1) NFC → 실제 파일경로 매핑
def resolve(nfc_name):
    for n in os.listdir(out_dir):
        if unicodedata.normalize("NFC", n) == nfc_name:
            return os.path.join(out_dir, n)
    return None

# 2) 필수 파일 검증
for nfc in REQUIRED:
    p = resolve(nfc)
    if not p:
        print(f"FAIL: {nfc} 누락"); sys.exit(2)
    with open(p, encoding="utf-8") as f:
        recs = [json.loads(l) for l in f if l.strip()]
    keys = set().union(*(r.keys() for r in recs)) if recs else set()
    if keys != {"Index", "model", "response"}:
        print(f"FAIL {nfc}: 스키마 불일치 {sorted(keys)}"); sys.exit(3)
    if sorted(r["Index"] for r in recs) != [f"{i:03d}" for i in range(1, 301)]:
        print(f"FAIL {nfc}: Index 누락/중복"); sys.exit(4)
    if any(r["model"] == "MODEL_NAME" for r in recs):
        print(f"FAIL {nfc}: model 미입력 (MODEL_NAME 잔존)"); sys.exit(5)

# 3) 최소 zip (필수만, NFC 파일명으로 저장)
with zipfile.ZipFile(pkg_min, "w", zipfile.ZIP_DEFLATED) as z:
    for nfc in REQUIRED:
        z.write(resolve(nfc), arcname=nfc)
print(f"OK_MIN {pkg_min}")

# 4) 풀 zip (필수 + 부가)
extras_present = [e for e in EXTRAS if resolve(e)]
if extras_present:
    with zipfile.ZipFile(pkg_full, "w", zipfile.ZIP_DEFLATED) as z:
        for nfc in REQUIRED + extras_present:
            z.write(resolve(nfc), arcname=nfc)
    print(f"OK_FULL {pkg_full}")
PY
    local rc=$?
    if [[ $rc -ne 0 ]]; then err "제출 검증/패키징 실패 (rc=$rc)"; return $rc; fi

    info "필수 파일 검증 통과 (스키마·Index·model 모두 적합)"
    ok "${BOLD}최소 제출 패키지${RESET}: $pkg_min"
    if command -v unzip >/dev/null; then unzip -l "$pkg_min" | sed 's/^/    /'; fi
    if [[ -f "$pkg_full" ]]; then
        ok "확장 패키지 (참고 자료 포함): $pkg_full"
        if command -v unzip >/dev/null; then unzip -l "$pkg_full" | sed 's/^/    /'; fi
    fi
    say
    info "제출은 ${BOLD}$pkg_min${RESET}만 보내고, 심사관이 추가 자료 요구 시 ${BOLD}$pkg_full${RESET} 사용 권장"
}

# ── 결과 표시 ────────────────────────────────────────────────────────────────
print_results() {
    say
    printf "%s%s완료%s\n" "$BOLD" "$GREEN" "$RESET"
    say
    printf "%s★ 금보원 제출 필수 파일%s\n" "$BOLD" "$RESET"
    say "  • output/모델변경전.jsonl"
    say "  • output/모델변경후.jsonl"
    say
    printf "%s  부가 자료 (선택 제출)%s\n" "$DIM" "$RESET"
    say "  • output/comparison_report.md         (A/B 회귀 분석)"
    say "  • output/*.metadata.jsonl             (stop_reason 사이드카)"
    say
    if [[ -f output/comparison_report.md ]]; then
        printf "%s── comparison_report.md 핵심 ─────────────%s\n" "$BOLD" "$RESET"
        awk '/^## A\/B/{flag=1} flag; /^---/{if(flag){flag=0; exit}}' \
            output/comparison_report.md | head -30
        say
    fi
    # 제출 패키지 자동 생성 제안
    say
    read -rp "${BOLD}지금 제출용 zip 패키지를 만들까요? [Y/n]: ${RESET}" yn
    yn="${yn:-Y}"
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        make_submission
    else
        info "나중에 ${BOLD}./run_benchmark.sh --submit${RESET} 으로 패키징 가능"
    fi
}

# ── 메인 ─────────────────────────────────────────────────────────────────────
main() {
    local mode="interactive"
    local limit="" only="both" reset="1"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)        usage; exit 0 ;;
            --report)         mode="report"; shift ;;
            --resume)         reset="0"; shift ;;
            --quick)          limit="5"; shift ;;
            --only-before)    only="before"; shift ;;
            --only-after)     only="after"; shift ;;
            --submit)         mode="submit"; shift ;;
            *) err "알 수 없는 옵션: $1"; usage; exit 2 ;;
        esac
    done

    banner
    preflight_env

    if [[ "$mode" == "report" ]]; then
        info "리포트만 재생성 (호출 없음)"
        python3 fsi_bench.py --report-only
        print_results
        exit 0
    fi

    if [[ "$mode" == "submit" ]]; then
        info "기존 결과로 제출 패키지만 생성"
        make_submission
        exit $?
    fi

    ensure_credentials

    # ── 모델 선택 ────────────────────────────────────────────────────────────
    local b_choice a_choice
    if ! b_choice=$(choose_model "변경 전 모델 (before — 기존 운영 모델)" 1); then exit 1; fi
    IFS='|' read -r B_MID B_REGION <<< "$b_choice"
    if ! a_choice=$(choose_model "변경 후 모델 (after — 신규 도입 모델)" 2); then exit 1; fi
    IFS='|' read -r A_MID A_REGION <<< "$a_choice"

    # ── 사전 호출 테스트 ────────────────────────────────────────────────────
    say
    printf "%s%s사전 호출 테스트%s (각 모델에 1건)\n" "$BOLD" "$CYAN" "$RESET"
    if [[ "$only" != "after" ]]; then
        smoke_test "$B_MID" "$B_REGION" || { err "변경 전 모델 호출 실패. 중단."; exit 1; }
    fi
    if [[ "$only" != "before" ]]; then
        smoke_test "$A_MID" "$A_REGION" || { err "변경 후 모델 호출 실패. 중단."; exit 1; }
    fi

    # ── 확인 ─────────────────────────────────────────────────────────────────
    local plan_limit="${limit:-300}"
    if ! confirm_plan "$B_MID" "$B_REGION" "$A_MID" "$A_REGION" "$only" "$plan_limit"; then
        warn "취소됨"; exit 0
    fi

    # ── 실행 ────────────────────────────────────────────────────────────────
    run_full "$B_MID" "$B_REGION" "$A_MID" "$A_REGION" "$only" "$limit" "$reset"
    print_results
}

main "$@"
