# Changelog

[![English](https://img.shields.io/badge/lang-English-red.svg)](#english)
[![한국어](https://img.shields.io/badge/lang-한국어-blue.svg)](#한국어)

---

# English

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-05-04

### Added
- Add bilingual (English/Korean) `README.md` with installation, usage, and project-structure sections.
- Add `--submit` mode to `run_benchmark.sh` that validates the FSI schema and produces minimal and full zip packages.
- Add NFC filename normalization inside the submission zip so Windows reviewers can read Korean file names without mojibake.
- Add schema-failure fail-fast: `--submit` aborts before zipping when `Index`, `model`, or `response` fields are invalid.

### Changed
- **BREAKING:** Move all generated artifacts from `doc/output_format/` to a top-level `output/` directory so the specification source remains read-only.
- Restore the original placeholder skeletons in `doc/output_format/` after the move; downstream consumers must now read deliverables from `output/`.
- Move `jailbreakbench.fixed.jsonl` (auto-repaired input copy) into `output/` to keep `doc/` pristine.

## [0.2.0] - 2026-05-03

### Added
- Add `run_benchmark.sh`, an interactive shell entrypoint with a preset model menu, smoke-test, cost estimate, and confirmation prompt.
- Add A/B regression analysis to `fsi_bench.py` with automatic generation of `comparison_report.md`.
- Add `--only before` / `--only after` flags to enable independent execution of each side.
- Add a metadata sidecar (`*.metadata.jsonl`) that records `stop_reason`, `output_tokens`, and `input_tokens` per prompt.
- Add hard-refusal detection by recognising Anthropic's `stop_reason: "refusal"` as the strongest safety signal.

### Changed
- Generalise `fsi_bench.py` from a single-model runner to a dual-model A/B runner with `--before-model`, `--before-region`, `--after-model`, and `--after-region` flags.
- Expand `REFUSAL_KEYWORDS` to cover Sonnet 4.6's "아니요, ...하지 않겠습니다" and "No, ..." refusal patterns, reducing false-positive regressions.
- Detect placeholder `MODEL_NAME` in either side and skip A/B comparison instead of producing misleading deltas.

### Fixed
- Fix duplicate-`Index` silent overwrite in the loader by relabelling the second occurrence to the lowest free three-digit index.
- Fix unescaped `"` characters inside the prompt field of the upstream JailbreakBench (KR) dataset by writing a repaired copy.

## [0.1.0] - 2026-05-03

### Added
- Add the initial 300-prompt benchmark runner targeting Anthropic Claude Sonnet 4.6 on Amazon Bedrock.
- Add concurrent invocation with `ThreadPoolExecutor`, exponential backoff for `ThrottlingException` and 5xx errors, and per-prompt retry budget.
- Add an append-only progress sidecar (`*.progress.jsonl`) that allows interrupted runs to resume without re-invoking completed prompts.
- Add automatic repair of the input dataset's malformed JSON line at `Index` 188.
- Add Bedrock API key authentication via the `AWS_BEARER_TOKEN_BEDROCK` environment variable in addition to standard IAM credentials.

[Unreleased]: https://github.com/fsi-redteam/fsi-kor-ai-benchmark/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/fsi-redteam/fsi-kor-ai-benchmark/compare/v0.2.0...v1.0.0
[0.2.0]: https://github.com/fsi-redteam/fsi-kor-ai-benchmark/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/fsi-redteam/fsi-kor-ai-benchmark/releases/tag/v0.1.0

---

# 한국어

이 프로젝트의 모든 주요 변경 사항은 이 파일에 기록됩니다.
이 문서는 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)를 기반으로 하며,
[Semantic Versioning](https://semver.org/spec/v2.0.0.html)을 따릅니다.

## [Unreleased]

## [1.0.0] - 2026-05-04

### Added
- 설치, 사용법, 프로젝트 구조 섹션을 포함한 이중 언어(영어/한국어) `README.md` 추가.
- FSI 스키마를 검증하고 최소·확장 zip 패키지를 생성하는 `run_benchmark.sh --submit` 모드 추가.
- Windows 심사자가 한글 파일명을 깨짐 없이 읽을 수 있도록 제출 zip 내부 파일명 NFC 정규화 추가.
- 스키마 검증 실패 시 zip 생성 전 즉시 중단하는 fail-fast 가드 추가 (`Index`/`model`/`response` 필드 부적합 감지).

### Changed
- **BREAKING:** 산출물 디렉터리를 `doc/output_format/`에서 최상위 `output/`로 이동하여 명세 원본을 읽기 전용으로 보존하도록 변경.
- 이동 후 `doc/output_format/`의 원본 스켈레톤 자리표시자 복구; 다운스트림 소비자는 이제 `output/`에서 산출물을 읽어야 함.
- 자동 수리된 입력 사본 `jailbreakbench.fixed.jsonl`도 `output/`로 이전하여 `doc/`를 변경하지 않도록 조정.

## [0.2.0] - 2026-05-03

### Added
- 프리셋 모델 메뉴, 사전 호출 테스트, 비용 안내, 실행 확인 프롬프트를 갖춘 인터랙티브 셸 진입점 `run_benchmark.sh` 추가.
- `fsi_bench.py`에 A/B 회귀 분석 로직 추가 및 `comparison_report.md` 자동 생성 추가.
- 변경 전·후 측을 독립적으로 실행할 수 있는 `--only before` / `--only after` 플래그 추가.
- 프롬프트별 `stop_reason`, `output_tokens`, `input_tokens`를 기록하는 메타데이터 사이드카(`*.metadata.jsonl`) 추가.
- Anthropic의 `stop_reason: "refusal"`을 가장 강한 안전 신호로 인식하는 하드 거절 검출 로직 추가.

### Changed
- `fsi_bench.py`를 단일 모델 러너에서 `--before-model`, `--before-region`, `--after-model`, `--after-region` 플래그 기반 양측 A/B 러너로 일반화.
- `REFUSAL_KEYWORDS`를 Sonnet 4.6의 "아니요, ...하지 않겠습니다" 및 "No, ..." 거절 패턴까지 포괄하도록 확장하여 거짓 양성 회귀 감소.
- 양쪽 중 어느 한쪽이 자리표시자 `MODEL_NAME` 상태이면 오해를 부르는 회귀 분석을 출력하지 않고 A/B 비교를 건너뛰도록 변경.

### Fixed
- 로더에서 중복 `Index` 항목이 조용히 덮어쓰여지던 결함을 수정하고, 두 번째 발생 항목을 가장 낮은 미사용 3자리 인덱스로 재라벨링.
- 상위 JailbreakBench(KR) 데이터셋의 prompt 필드 내부 escape 누락된 `"` 문자를 수리본 사본에 자동 정정.

## [0.1.0] - 2026-05-03

### Added
- Amazon Bedrock의 Anthropic Claude Sonnet 4.6를 대상으로 하는 300건 벤치마크 러너 초기 버전 추가.
- `ThreadPoolExecutor` 기반 동시 호출, `ThrottlingException` 및 5xx 응답에 대한 지수 백오프, 프롬프트별 재시도 예산 추가.
- 중단된 실행이 완료된 프롬프트를 재호출하지 않고 이어 실행되도록 하는 append-only 진행 사이드카(`*.progress.jsonl`) 추가.
- 입력 데이터셋의 `Index` 188에 존재하던 깨진 JSON 라인 자동 수리 기능 추가.
- 표준 IAM 자격증명에 더해 `AWS_BEARER_TOKEN_BEDROCK` 환경변수를 통한 Bedrock API 키 인증 추가.

[Unreleased]: https://github.com/fsi-redteam/fsi-kor-ai-benchmark/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/fsi-redteam/fsi-kor-ai-benchmark/compare/v0.2.0...v1.0.0
[0.2.0]: https://github.com/fsi-redteam/fsi-kor-ai-benchmark/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/fsi-redteam/fsi-kor-ai-benchmark/releases/tag/v0.1.0
