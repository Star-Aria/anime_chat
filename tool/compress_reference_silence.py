"""Create non-destructive TTS reference copies with long silence shortened.

Run with the Python bundled with GPT-SoVITS so librosa and soundfile are
available. Source files are never modified.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import librosa
import numpy as np
import soundfile as sf


def compress_long_silence(
    audio: np.ndarray,
    sample_rate: int,
    *,
    minimum_silence_seconds: float = 0.45,
    retained_silence_seconds: float = 0.28,
) -> np.ndarray:
    """Shorten only sustained near-silence while retaining quiet breaths."""
    if audio.size == 0:
        return audio

    frame_length = max(1, round(sample_rate * 0.02))
    hop_length = max(1, round(sample_rate * 0.01))
    rms = librosa.feature.rms(
        y=audio,
        frame_length=frame_length,
        hop_length=hop_length,
        center=True,
    )[0]
    rms_db = librosa.amplitude_to_db(rms, ref=1.0)
    # A low absolute threshold avoids treating characteristic quiet breathing
    # as silence. Only long runs below it are shortened.
    silent_frames = rms_db < -48.0
    minimum_frames = max(1, round(minimum_silence_seconds / 0.01))
    retained_samples = max(1, round(retained_silence_seconds * sample_rate))

    ranges: list[tuple[int, int]] = []
    start: int | None = None
    for index, is_silent in enumerate(silent_frames):
        if is_silent and start is None:
            start = index
        elif not is_silent and start is not None:
            if index - start >= minimum_frames:
                ranges.append((start * hop_length, index * hop_length))
            start = None
    if start is not None and len(silent_frames) - start >= minimum_frames:
        ranges.append((start * hop_length, len(audio)))

    if not ranges:
        return audio.copy()

    pieces: list[np.ndarray] = []
    cursor = 0
    for silence_start, silence_end in ranges:
        silence_start = max(cursor, min(silence_start, len(audio)))
        silence_end = max(silence_start, min(silence_end, len(audio)))
        pieces.append(audio[cursor:silence_start])
        silence = audio[silence_start:silence_end]
        if len(silence) > retained_samples:
            left = retained_samples // 2
            right = retained_samples - left
            pieces.append(np.concatenate((silence[:left], silence[-right:])))
        else:
            pieces.append(silence)
        cursor = silence_end
    pieces.append(audio[cursor:])
    return np.concatenate(pieces)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()

    args.destination.mkdir(parents=True, exist_ok=True)
    for source_path in sorted(args.source.glob("*")):
        if source_path.suffix.lower() not in {".wav", ".mp3", ".flac", ".m4a"}:
            continue
        audio, sample_rate = librosa.load(source_path, sr=None, mono=True)
        processed = compress_long_silence(audio, sample_rate)
        output_path = args.destination / f"{source_path.stem}.wav"
        sf.write(output_path, processed, sample_rate, subtype="PCM_16")
        print(
            f"{source_path.name}: {len(audio) / sample_rate:.3f}s -> "
            f"{len(processed) / sample_rate:.3f}s"
        )


if __name__ == "__main__":
    main()
