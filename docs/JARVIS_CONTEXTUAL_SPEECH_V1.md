# Contextual weather conversation
- User reports unnecessary full dates in spoken weather answers after DEKA invocation.
- Weather is a deterministic grounded tool route, not Qwen-generated text. WeatherConversation now formats current conditions naturally ("지금 군산 지역은 ..."), tomorrow as a forecast, and negative temperatures as 영하. No additional model call. Missing quantities are not invented. KST today/tomorrow is validated against source dates; stale dates cannot be labeled current.
- The weather board continues displaying exact model reference time, retrieval time, forecast dates, and Open-Meteo attribution. Response retains model provenance.
- General local Qwen system context now asks for concise natural relative date expressions when unambiguous, exact dates when requested or needed, and preservation of facts and uncertainty. Dedicated date/clock answers remain untouched.
- Weather native test suite 21 assertions including screenshot-like fixture, tomorrow, missing values, and stale-date rejection. Audible quality and Qwen response behavior require real user validation.
