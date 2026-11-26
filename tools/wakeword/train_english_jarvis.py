"""Offline synthetic-only English `Jarvis` classifier. No user recordings.
Validation compares unseen macOS voices; not an accuracy guarantee.
"""
from pathlib import Path
import train_ko_prototype as trainer

root=Path.home()/'.jarvis-lab/wakeword/english-lab'
root.mkdir(mode=0o700,parents=True,exist_ok=True)
trainer.ROOT=root
trainer.DEST=root/'english_jarvis_solo.onnx'
trainer.TRAIN=['Samantha','Daniel','Karen','Rishi','Flo (영어(미국))','Reed (영어(영국))']
trainer.HOLDOUT=['Sandy (영어(영국))','Shelley (영어(미국))','Moira']
trainer.POS=['Jarvis','Jarvis?','Jarvis!']
trainer.NEG=['service','Javis','harvest','Jarvising','jar','harbor','justice',
             'garage','Charlie','Alexa','hey there','today is Tuesday','weather','today','Jarvis system']
if __name__=='__main__':
    trainer.main()
