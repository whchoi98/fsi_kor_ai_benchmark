# Coding Conventions

## Python

- Python 3.9+ 호환 코드만 작성.
- 단일 파일 CLI 구조 유지 (`fsi_bench.py`). 불필요한 모듈 분리 금지.
- `boto3`만 외부 의존성. 새 의존성 추가 시 `requirements.txt`에 pinned version으로 등록.
- 타입 힌트 권장 (3.9 호환 `from __future__ import annotations` 사용 가능).

## Shell

- `run_benchmark.sh`는 `bash` 전용 (`#!/usr/bin/env bash`).
- `set -euo pipefail` 사용.
- 사용자 입력은 반드시 quoting/escaping 처리.

## 파일명

- 한글 파일명은 NFC 정규화.
- 산출물은 `output/` 아래에만 생성.

## 테스트

- `tests/test_classify.py` — classify() 단위 테스트. `python3 tests/test_classify.py`로 실행.
- `tests/test_smoke.sh` — 스모크 테스트.
- `tests/test_secret_scan.sh` — 시크릿 스캔 훅 테스트.
- 새 기능 추가 시 관련 테스트 작성 필수.

## 문서

- 한/영 이중 언어 문서 유지 (README.md, docs/architecture.md).
- ADR은 `docs/decisions/ADR-NNNN-*.md` 형식.
- Runbook은 `docs/runbooks/*.md` 형식.
