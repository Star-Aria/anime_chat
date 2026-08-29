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


# Keep a small margin above GPT-SoVITS's five-second lower bound so duration
# rounding in different decoders cannot turn a valid reference into 4.99s.
MINIMUM_REFERENCE_SECONDS = 5.1


def compress_long_silence(
    audio: np.ndarray,
    sample_rate: int,
    *,
    minimum_silence_seconds: float = 0.85,
    retained_silence_seconds: float = 0.70,
    minimum_output_seconds: float = MINIMUM_REFERENCE_SECONDS,
) -> np.ndarray:
    """Shorten sustained near-silence without making the reference too short."""
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
    # GPT-SoVITS reference audio must stay above five seconds. Limit the
    # total deletion budget instead of padding artificial silence afterwards.
    removable_samples = max(
        0,
        len(audio) - round(minimum_output_seconds * sample_rate),
    )
    for silence_start, silence_end in ranges:
        silence_start = max(cursor, min(silence_start, len(audio)))
        silence_end = max(silence_start, min(silence_end, len(audio)))
        pieces.append(audio[cursor:silence_start])
        silence = audio[silence_start:silence_end]
        if len(silence) > retained_samples:
            desired_removal = len(silence) - retained_samples
            actual_removal = min(desired_removal, removable_samples)
            kept_samples = len(silence) - actual_removal
            left = kept_samples // 2
            right = kept_samples - left
            pieces.append(np.concatenate((silence[:left], silence[-right:])))
            removable_samples -= actual_removal
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
        source_seconds = len(audio) / sample_rate
        if source_seconds < MINIMUM_REFERENCE_SECONDS:
            raise ValueError(
                f"{source_path.name} is only {source_seconds:.3f}s; "
                f"GPT-SoVITS reference audio must be at least "
                f"{MINIMUM_REFERENCE_SECONDS:.1f}s"
            )
        if source_path.stem.startswith("neutral_"):
            # Neutral references define the character's ordinary speaking pace.
            # Preserve them exactly so daily speech does not become hurried.
            processed = audio.copy()
        elif source_path.stem == "感激 安心":
            # This expressive sample contains two near-second silent gaps which
            # GPT-SoVITS tends to reproduce too literally in every grateful line.
            processed = compress_long_silence(
                audio,
                sample_rate,
                minimum_silence_seconds=0.45,
                retained_silence_seconds=0.28,
            )
        else:
            processed = compress_long_silence(audio, sample_rate)
        output_path = args.destination / f"{source_path.stem}.wav"
        processed_seconds = len(processed) / sample_rate
        if processed_seconds < MINIMUM_REFERENCE_SECONDS:
            raise RuntimeError(
                f"{source_path.name} became {processed_seconds:.3f}s after "
                "processing; refusing to write an invalid reference"
            )
        sf.write(output_path, processed, sample_rate, subtype="PCM_16")
        print(
            f"{source_path.name}: {source_seconds:.3f}s -> "
            f"{processed_seconds:.3f}s"
        )


if __name__ == "__main__":
    main()
