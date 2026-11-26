"""Synthetic offline evaluation only; no microphone recording."""
import json,os,pathlib,tempfile
from openwakeword.model import Model
from benchmark import audio,score
from train_ko_prototype import synth,trim
root=pathlib.Path.home()/'.jarvis-lab/wakeword/english-lab'
model=Model(wakeword_models=[str(root/'hey_jarvis_v0.1.onnx')],inference_framework='onnx')
tests=[('Samantha','Jarvis',155),('Samantha','Hey Jarvis',155),('Samantha','service',155),('Samantha','Jarvis',205),('Daniel','Jarvis',155),('Daniel','Hey Jarvis',155),('Daniel','service',155),('Daniel','Jarvis',205)]
rows=[]
with tempfile.TemporaryDirectory() as t:
 for voice,phrase,rate in tests:
  pcm=synth(voice,phrase,rate,pathlib.Path(t)/'clip')
  peak,elapsed,duration=score(model,trim(pcm))
  row=dict(voice=voice,phrase=phrase,rate=rate,peak=round(peak,4),elapsed=round(elapsed,3))
  rows.append(row);print(row,flush=True)
(root/'hey_jarvis_synthetic_quickcheck.json').write_text(json.dumps(rows,indent=2))
