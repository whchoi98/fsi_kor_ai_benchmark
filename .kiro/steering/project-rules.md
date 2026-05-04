# Project Rules — fsi-kor-ai-benchmark

## 읽기 전용 디렉토리

- `doc/` 디렉토리는 **절대 수정 금지**. 입력 데이터와 스펙 원본이 들어 있다.
- 복구가 필요하면 `repair_input()`이 `output/` 아래에 사본을 만들어 처리한다.

## 출력 파일 규칙

- 산출물 파일명은 한글(`모델변경전.jsonl`, `모델변경후.jsonl`)이며 NFC 정규화를 사용한다.
- 파일 경로를 하드코딩하지 말 것 — `find_or_create_target()`이 검색을 처리한다.
- `stop_reason`은 메타데이터 사이드카(`*.metadata.jsonl`)에만 기록. 산출물 JSONL에 FSI 스키마 외 필드 추가 금지.

## 재개(Resume) 우선

- 중간 실패 시 `*.progress.jsonl`을 읽어 이어가도록 설계됨.
- 재시도 로직을 추가할 때는 progress 쓰기 순서를 깨지 말 것.

## 보안

- **Bedrock 키는 환경변수로만**. `AWS_BEARER_TOKEN_BEDROCK`을 코드/설정 파일에 절대 박지 말 것.
- `output/submission_*.zip`은 모델 응답(잠재적 jailbreak 응답 포함)을 담고 있음. FSI 제출 채널 외 유출 금지.
- `.claude/settings.local.json`은 절대 커밋하지 말 것 — 과거에 bearer token 평문 노출 이력 있음.
- `.env`, `*.pem`, `*.key` 파일은 커밋 금지.

## Bedrock 모델 호출

- **Inference profile ID만 사용** (ADR-0001). Direct foundation model ID(`anthropic.claude-…`) 사용 금지.
- 허용 prefix: `eu.`, `us.`, `global.`, `apac.`
- 금지 형태: prefix 없는 `anthropic.claude-…`

## 커밋 관례

- Conventional Commits 형식 사용: `feat:`, `fix:`, `docs:`, `chore:`, `test:`
- `main` 브랜치에 직접 push 금지 — feature branch + PR 사용.
