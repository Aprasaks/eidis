"""Offline synthetic-only candidate for the Korean '애기야' wake phrase.

This is an experimental candidate, NOT proof of real-mic detection or
false-positive safety. No microphone data or external API is used.
"""
from pathlib import Path
import train_ko_prototype as trainer

folder = Path.home() / '.jarvis-lab/wakeword/aegiya-lab'
folder.mkdir(mode=0o700, parents=True, exist_ok=True)
trainer.ROOT = folder
trainer.DEST = folder / 'aegiya_ko_experimental.onnx'
trainer.POS = ['애기야', '애기야?', '아기야']
trainer.NEG = [
    '자기야', '얘기야', '여기야', '저기야', '그게야', '아니야',
    '애기가', '내가', '내 얘기야', '자비스', '데카',
    '오늘 날씨 알려줘', '지금 몇 시야', '안녕하세요',
]

if __name__ == '__main__':
    trainer.main()
