# FSI AI Benchmark

본 데이터셋은 오픈소스 AI 안전성 평가 프레임워크인 [JailbreakBench](https://github.com/JailbreakBench/jailbreakbench)의 프롬프트 데이터셋을 한국어로 번역 및 전처리한 버전입니다. 한국어 LLM의 탈옥(Jailbreak) 취약점 분석 및 레드팀(Red-Teaming) 벤치마크 수행을 위해 활용할 수 있습니다.

## 원본 데이터셋 출처
* **원본 프로젝트:** JailbreakBench
* **GitHub 저장소:** [JailbreakBench GitHub Repository](https://github.com/JailbreakBench/jailbreakbench)
* **HuggingFace Dataset:** [JailbreakBench HuggingFace Dataset](https://huggingface.co/datasets/JailbreakBench/JBB-Behaviors)
* **논문/출처:** Chao, P. et al. "JailbreakBench: An Open Robustness Benchmark for Jailbreaking Large Language Models." NeurIPS Datasets and Benchmarks Track, 2024.
```bibtex
@inproceedings{chao2024jailbreakbench,
  title={JailbreakBench: An Open Robustness Benchmark for Jailbreaking Large Language Models},
  author={Patrick Chao and Edoardo Debenedetti and Alexander Robey and Maksym Andriushchenko and Francesco Croce and Vikash Sehwag and Edgar Dobriban and Nicolas Flammarion and George J. Pappas and Florian Tramèr and Hamed Hassani and Eric Wong},
  booktitle={NeurIPS Datasets and Benchmarks Track},
  year={2024}
}
```

## 수정 및 가공 내용 (Modification Logs)
본 데이터셋은 원본 JailbreakBench 프롬프트를 기반으로 프로젝트 환경에 맞게 다음과 같이 2차 가공되었습니다:

1. **프롬프트 한국어 번역 (Translation)**
   * `judge_comparison` subset, `test` split, `prompt` 필드의 내용을 최신 언어 모델을 활용하여 한국어로 전면 번역하였습니다.
2. **Index 필드 규격화 (Formatting)**
   * 타 벤치마크 데이터와의 병합성을 높이기 위해 `Index` 필드를 `001`, `002` 형태의 3자리 문자열(String) 포맷으로 일괄 변환하였습니다.
3. **Source 식별자 추가 (Metadata Appended)**
   * 통합 데이터셋에서 출처가 혼동되지 않도록 각각의 데이터 레코드에 `"source": "JailbreakBench"` 필드를 새롭게 추가했습니다.

## 데이터 포맷 (Data Format)
파일은 JSON Lines (`.jsonl`) 형식으로 배포됩니다.
```json
{
  "Index": "001",
  "prompt": "[한국어로 번역된 탈옥 프롬프트]",
  "source": "JailbreakBench"
}
```

## 윤리적 사용 안내 (Ethical Use)

본 데이터셋은 **AI 안전성 연구, 레드팀 평가, 가드레일 성능 검증** 등 방어적 목적에 한하여 활용되어야 합니다.

* 본 데이터셋에 포함된 프롬프트는 LLM의 취약점을 분석하고 방어 체계를 개선하기 위한 목적으로 수집 및 번역된 것입니다.
* 실제 시스템에 대한 공격, 유해 콘텐츠 생성, 또는 기타 악의적 목적으로의 사용을 엄격히 금합니다.
* 본 데이터셋을 활용한 연구 결과물 공개 시, 관련 윤리 지침 및 소속 기관의 정책을 준수하시기 바랍니다.

본 배포 주체(FSI AI Red Team)는 데이터셋의 오남용으로 인해 발생하는 결과에 대해 책임을 지지 않습니다.

## 라이선스 (License)
본 저장소에 포함된 한국어 번역 및 가공된 데이터 파일과 가공 스크립트는 [MIT License](./LICENSE)의 적용을 받습니다.

**주의 사항 (Disclaimer)**:  
이 저장소는 원본 데이터(JailbreakBench)를 기반으로 작성된 2차적 저작물이므로 일차적으로는 원본 저장소의 저작권 및 라이선스 정책을 함께 존중하고 준수해야 합니다. 데이터의 상업적 이용 여부 등은 원본 데이터의 사용 허들을 꼭 확인해주시기 바랍니다.