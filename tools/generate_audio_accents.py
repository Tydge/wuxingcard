"""Generate the short five-element accent layers used by the sound director.

These are original synthesized layers, mixed with CC0 Foley in Godot. Run from
the project root with `python3 tools/generate_audio_accents.py`.
"""

from pathlib import Path
import wave

import numpy as np


RATE = 32000
OUT = Path(__file__).resolve().parents[1] / "assets/audio/sfx"


def write(name: str, samples: np.ndarray) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    samples = np.asarray(samples, dtype=np.float64)
    samples -= np.mean(samples)
    peak = max(np.max(np.abs(samples)), 1e-8)
    samples = np.clip(samples * (0.54 / peak), -1.0, 1.0)
    pcm = (samples * 32767).astype("<i2")
    with wave.open(str(OUT / f"element_{name}.wav"), "wb") as sound:
        sound.setnchannels(1)
        sound.setsampwidth(2)
        sound.setframerate(RATE)
        sound.writeframes(pcm.tobytes())


def time(length: float) -> np.ndarray:
    return np.arange(int(RATE * length)) / RATE


def smooth_noise(length: float, width: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    source = rng.uniform(-1.0, 1.0, int(RATE * length))
    kernel = np.ones(width) / width
    return np.convolve(source, kernel, mode="same")


def envelope(t: np.ndarray, attack: float, decay: float) -> np.ndarray:
    return (1 - np.exp(-t / attack)) * np.exp(-t / decay)


def main() -> None:
    # 金: a restrained struck-metal chime, with inharmonic partials.
    t = time(0.55)
    metal = sum(
        weight * np.sin(2 * np.pi * freq * t) * np.exp(-t / fall)
        for freq, weight, fall in [(710, 1.0, 0.25), (1165, 0.45, 0.34), (1902, 0.25, 0.22), (2740, 0.13, 0.12)]
    ) * (1 - np.exp(-t / 0.002))
    write("metal", metal)

    # 水: two little droplets and a soft, high splash tail.
    t = time(0.52)
    phase = 2 * np.pi * (640 * t - 260 * (1 - np.exp(-t / 0.045)) * 0.045)
    first = np.sin(phase) * envelope(t, 0.003, 0.13)
    shifted = np.maximum(t - 0.13, 0)
    second = np.sin(2 * np.pi * (860 * shifted - 300 * (1 - np.exp(-shifted / 0.035)) * 0.035))
    second *= envelope(shifted, 0.003, 0.10) * (t >= 0.13) * 0.48
    splash = smooth_noise(0.52, 5, 19) * envelope(t, 0.009, 0.18) * 0.65
    write("water", first + second + splash)

    # 木: low bamboo-like knock plus a short leafy brushing tail.
    t = time(0.43)
    wood = (np.sin(2 * np.pi * 290 * t) + 0.22 * np.sin(2 * np.pi * 610 * t)) * envelope(t, 0.002, 0.085)
    wood += smooth_noise(0.43, 17, 23) * envelope(t, 0.02, 0.17) * 0.8
    write("wood", wood)

    # 火: a quick flare of crackle with a low, non-explosive body.
    t = time(0.48)
    fire = smooth_noise(0.48, 3, 31) * envelope(t, 0.017, 0.15)
    fire += np.sin(2 * np.pi * (180 * t + 80 * t * t)) * envelope(t, 0.009, 0.13) * 0.11
    rng = np.random.default_rng(32)
    for index in rng.integers(200, int(RATE * 0.28), size=14):
        end = min(index + 65, len(fire))
        fire[index:end] += np.exp(-np.arange(end - index) / 12) * rng.uniform(-0.15, 0.15)
    write("fire", fire)

    # 土: a compact stone thump with grit, leaving room for the impact Foley.
    t = time(0.55)
    earth = np.sin(2 * np.pi * (95 * t + 70 * t * t)) * envelope(t, 0.003, 0.16)
    earth += smooth_noise(0.55, 19, 41) * envelope(t, 0.004, 0.11) * 0.6
    write("earth", earth)


if __name__ == "__main__":
    main()
