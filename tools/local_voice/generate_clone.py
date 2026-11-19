#!/usr/bin/env python3
"""Offline, opt-in Qwen3-TTS voice clone; reference stays on this Mac."""
import argparse
import os
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from mlx_audio.tts.utils import load_model

MODEL = 'mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16'


def synthesize(reference: Path, ref_text: str, phrase: str, output: Path, pitch: float):
    if not reference.is_file():
        raise FileNotFoundError(f'참조 음성 파일 없음: {reference}')
    if not ref_text.strip() or not phrase.strip():
        raise ValueError('참조 음성의 정확한 녹음 문장과 테스트 문장 모두 필요합니다.')
    if not 0.88 <= pitch <= 1.00:
        raise ValueError('피치 범위는 0.88부터 1.00까지입니다.')
    if reference.stat().st_size > 55_000_000:
        raise ValueError('참조 파일이 너무 큽니다. 5~20초 음성만 사용해 주세요.')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='jarvis-ref-', dir=output.parent) as staging:
        normalized = Path(staging)/'reference-24000.wav'
        subprocess.run(['/opt/homebrew/bin/ffmpeg', '-y', '-hide_banner', '-loglevel', 'error',
                        '-i', str(reference), '-ac', '1', '-ar', '24000', '-c:a', 'pcm_s16le',
                        str(normalized)], check=True, timeout=45)
        from scipy.io import wavfile as wavreader
        rate, wave = wavreader.read(normalized)
        duration = len(wave)/rate
        if duration < 3 or duration > 35:
            raise ValueError(f'참조 녹음은 3~35초여야 합니다. 현재 {duration:.1f}초')
        print('STEP 1/3 로컬 Qwen3-TTS 모델 로딩', flush=True)
        model = load_model(MODEL)
        print('STEP 2/3 오디오 로컬 생성 중 (음성 파일 외부 전송 없음)', flush=True)
        chunks = []
        sample_rate = 24000
        for result in model.generate(text=phrase, ref_audio=str(normalized), ref_text=ref_text,
                                     lang_code='Korean', verbose=False, max_tokens=512):
            sample_rate = int(getattr(result, 'sample_rate', 24000))
            chunks.append(np.array(result.audio, dtype=np.float32).reshape(-1))
    if not chunks:
        raise RuntimeError('모델이 오디오를 생성하지 않았습니다.')
    audio = np.concatenate(chunks)
    if audio.size < 2000 or not np.isfinite(audio).all():
        raise RuntimeError('생성 음성이 비어 있거나 손상되었습니다.')
    audio = np.clip(audio * 0.95, -1, 1)
    # Suffixes avoid replacing the original user's recording.
    original = output.with_name(output.stem + '_original.wav')
    wavfile.write(original, sample_rate, (audio * 32767).astype(np.int16))
    if pitch < 0.999:
        # Lower pitch slightly without changing the duration much.
        # atempo compensates for asetrate playback-speed changes.
        filt = f'asetrate={sample_rate}*{pitch:.4f},aresample={sample_rate},atempo={1/pitch:.4f}'
        cmd = ['/opt/homebrew/bin/ffmpeg', '-y', '-hide_banner', '-loglevel', 'error',
               '-i', str(original), '-af', filt, '-ac', '1', '-ar', str(sample_rate), str(output)]
        subprocess.run(cmd, check=True, timeout=45)
    else:
        output.write_bytes(original.read_bytes())
    print(f'STEP 3/3 완료: {output}', flush=True)
    print(f'ORIGINAL: {original}', flush=True)
    print(f'DURATION_SEC: {len(audio) / sample_rate:.2f}', flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--reference-text', required=True)
    parser.add_argument('--text', default='네, 자비스입니다. 무엇을 도와드릴까요?')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--pitch', type=float, default=0.95)
    args = parser.parse_args()
    synthesize(args.reference.expanduser().resolve(), args.reference_text,
               args.text, args.output.expanduser().resolve(), args.pitch)


if __name__ == '__main__':
    main()
