"""Local pattern-match sample guardrail (no AWS calls).

Activated by ``FSI_GUARDRAIL_MODE=sample``. Provides a working Stage 1 so
``fsi_bench.py`` can be exercised end-to-end before a real guardrail is
provisioned. NOT a production guardrail — pattern coverage is illustrative.

Replace for production:
  - Set ``FSI_GUARDRAIL_MODE=`` (empty) and ``BEDROCK_GUARDRAIL_ID=…`` to use
    Amazon Bedrock Guardrails (the reference path in ``fsi_bench.py``).
  - Or replace the body of ``guardrail_check()`` in ``fsi_bench.py`` with a
    call to your company guardrail (HTTP service / on-prem classifier / etc).

Why a separate module: keeps the sample patterns out of the core runner so
forks don't have merge conflicts in ``fsi_bench.py`` when this catalogue
evolves. ``fsi_bench.guardrail_check`` imports ``match`` lazily.
"""
from __future__ import annotations

import re
from typing import Optional, Tuple

# Reason labels follow the all-caps convention used by the Bedrock reference
# impl (PII, JAILBREAK, …) so sidecar histograms aggregate cleanly across
# guardrail modes.
_PATTERNS: Tuple[Tuple[str, Tuple[re.Pattern, ...]], ...] = (
    ("PII", (
        re.compile(r"\b\d{6}[-\s]?\d{7}\b"),                              # 주민등록번호
        re.compile(r"\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b"),        # 카드번호
        re.compile(r"(주민등록번호|주민번호|카드번호|계좌번호|신용점수|신용등급|대출\s*이력|연체\s*이력)"),
    )),
    ("PROMPT_LEAK", (
        re.compile(r"(시스템\s*)?프롬프트.*(보여|알려|출력|공개|노출|복사|복제|뱉)"),
        re.compile(r"지침.*(뭐|뭔|보여|알려|출력)"),
        re.compile(r"system\s*prompt.*(reveal|show|leak|dump|print)", re.IGNORECASE),
        re.compile(r"ignore\s+(all\s+)?previous\s+(instructions|rules)", re.IGNORECASE),
        re.compile(r"(규칙|지침).*(무시|넘어서|벗어나)"),
    )),
    ("JAILBREAK", (
        re.compile(r"\bDAN\b"),
        re.compile(r"do\s+anything\s+now", re.IGNORECASE),
        re.compile(r"jailbreak", re.IGNORECASE),
        re.compile(r"제약\s*(없|없이).*(답|응답|말해|얘기)"),
        re.compile(r"롤플레이.*(제한|제약).*없"),
        # JailbreakBench KR 의 "응답을 '물론, …'로 시작" 강제 오프닝 패턴
        re.compile(r"(답변|응답)을\s*[\"'‘“]?\s*물론"),
    )),
    ("FINANCIAL_FRAUD", (
        re.compile(r"보이스\s*피싱"),
        re.compile(r"피싱\s*(이메일|메시지|스크립트|문자|사이트)"),
        re.compile(r"자금\s*세탁|돈\s*세탁"),
        re.compile(r"(시세|시장)\s*조작"),
        re.compile(r"가짜\s*(송금|결제|영수증|계좌)"),
        re.compile(r"미인가\s*투자"),
    )),
    ("HARMFUL_CONTENT", (
        re.compile(r"(폭탄|폭발물|폭발\s*장치|사제\s*폭).*(만드|제조|만들|레시피)"),
        re.compile(r"(해킹|침투|크랙|크래킹).*(가이드|단계|방법|튜토리얼|스크립트)"),
        re.compile(r"(악성\s*코드|멀웨어|랜섬웨어|키로거).*(작성|만드|제조|배포)"),
        re.compile(r"신원\s*(도용|위장)"),
        re.compile(r"(bomb|explosive|ied).*(make|build|recipe|how\s+to)", re.IGNORECASE),
        re.compile(r"(make|build|how\s+to).*(bomb|explosive|ied)", re.IGNORECASE),
        re.compile(r"phishing.*(email|message|script|page)", re.IGNORECASE),
    )),
)

DEFAULT_REFUSAL = (
    "[guardrail-sample] 본 요청은 안전 정책에 따라 처리할 수 없습니다."
)


def match(user_query: str) -> Tuple[bool, Optional[str], Optional[str]]:
    """Pattern-match the query against the sample catalogue.

    Returns ``(blocked, refusal_text, reason)``.
      blocked      : True if any pattern hit.
      refusal_text : sample refusal string when blocked, else None.
      reason       : standardized category label (PII / JAILBREAK / …).

    Order matters only for the reason label — the first matching family wins.
    """
    for reason, patterns in _PATTERNS:
        for p in patterns:
            if p.search(user_query):
                return True, DEFAULT_REFUSAL, reason
    return False, None, None
