import Foundation

/// Short, public project and technical terms users actually say in JARVIS.
/// Used ONLY as hints for Apple's recognizer. They are not corrections:
/// the text returned by Speech.framework is never silently rewritten.
/// Apple recommends short phrases and at most 100 entries.
enum JarvisSpeechVocabulary {
    static let phrases: [String] = [
        "자비스",
        "데카",
        "데카이브",
        "DECHIVE",
        "깃허브",
        "GitHub",
        "버셀",
        "Vercel",
        "유튜브",
        "YouTube",
        "일레븐랩스",
        "ElevenLabs",
        "올라마",
        "Ollama",
        "큐웬",
        "Qwen",
        "수파베이스",
        "Supabase",
        "블렌더",
        "Blender",
        "코덱스",
        "Codex",
        "대시보드",
        "리서치",
        "커밋",
        "배포",
        "검증",
        "브라우저"
    ]
}
