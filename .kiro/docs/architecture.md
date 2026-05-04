# Architecture Reference

> 전체 아키텍처 문서는 [docs/architecture.md](../../docs/architecture.md)를 참조하세요.

## 요약

단일 프로세스 Python CLI가 300건 한국어 jailbreak 프롬프트를 BEFORE/AFTER 모델에 **순차 실행**하고,
5-class 분류 후 A/B 회귀 리포트 + FSI 제출 패키지를 생성합니다.

## 핵심 컴포넌트

| Layer | Component | 설명 |
|---|---|---|
| Ingestion | `doc/jailbreakbench.jsonl` | 300건 입력 (read-only) |
| Ingestion | `repair_input()` | 깨진 JSONL 사본 복구 |
| Processing | `run_side()` | ThreadPoolExecutor(8) 기반 모델 호출 |
| Processing | `_invoke_one()` | Bedrock invoke_model + 재시도 |
| Processing | `classify()` | 5-class 분류기 |
| Storage | `output/*.jsonl` | FSI 제출물 + 메타데이터 + progress |
| Reporting | `validate_side()` + `write_comparison_report()` | 스키마 검증 + A/B 리포트 |
| Presentation | `run_benchmark.sh` | 인터랙티브 진입점 |

## 주요 설계 결정

- Inference profile만 사용 (ADR-0001) — direct foundation ID 금지
- 순차 실행 (BEFORE 완료 후 AFTER 시작) — side-level 병렬화 없음
- progress.jsonl 기반 prompt-grain 재개
