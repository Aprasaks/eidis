"""Synthetic-only Korean 자비스 wake candidate; real-user mic test still required."""
from pathlib import Path
import train_ko_prototype as trainer

folder = Path.home() / '.jarvis-lab/wakeword/jarvis-lab'
folder.mkdir(mode=0o700, parents=True, exist_ok=True)
trainer.ROOT = folder
trainer.DEST = folder / 'jarvis_ko_candidate.onnx'
trainer.POS = ['자비스', '자비스?', '자비스야', '자비스!']
trainer.NEG = [
    '서비스', '자비', '자비심', '잡지', '비스킷', '자전거',
    '자바스크립트', '자비스라는 이름', '자비를 베풀어', '나비스',
    '데카', '애기야', '아기야', '오늘 날씨 알려줘', '안녕하세요',
    '자동차', '잠깐만', '시작해', '지금 몇 시야', '우리 프로젝트 열어줘',
]
if __name__ == '__main__':
    trainer.main()
