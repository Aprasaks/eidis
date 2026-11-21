# Korean speech text normalization
- User-confirmed DEKA wake → weather command → board and spoken response works, but numeric pronunciation breaks down.
- Shared deterministic KoreanSpeechText formatter at the ElevenLabs and local Mac TTS boundaries. Screen text, stored records, source data unchanged. No additional API call; preserve existing method, settings and 600-character cap on both raw and normalized text.
- Signed decimals, comma-grouped amounts, percentages, temperature, common units, validated ISO dates, 24-hour clock, and common Korean counters. URLs, code tokens, versions, invalid dates/times and numeric ranges are not interpreted. Leading zero identifiers read digit-by-digit. Not a general-purpose text normalizer for all languages or financial notation.
- 14 expected-string and idempotence cases including the user screenshot weather response. Actual spoken audio quality requires user confirmation; no paid TTS test was triggered by development.
