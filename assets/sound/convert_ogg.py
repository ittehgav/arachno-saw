from pathlib import Path
import subprocess

# Audio file extensions FFmpeg can usually read
AUDIO_EXTENSIONS = {
    ".wav",
    ".mp3",
    ".flac",
    ".aac",
    ".m4a",
    ".wma",
    ".aiff",
    ".aif",
    ".opus",
    ".oga",
    ".ac3",
    ".amr",
    ".ape",
    ".caf",
    ".mka",
    ".mp2",
    ".mpa",
    ".ra",
    ".tta",
    ".wv",
    ".3gp",
}

# OGG quality (0-10, higher = better)
QUALITY = 6

root = Path.cwd()

for input_file in root.rglob("*"):
    if not input_file.is_file():
        continue

    if input_file.suffix.lower() == ".ogg":
        continue

    if input_file.suffix.lower() not in AUDIO_EXTENSIONS:
        continue

    output_file = input_file.with_suffix(".ogg")

    if output_file.exists():
        print(f"Skipping (already exists): {output_file}")
        continue

    print(f"Converting: {input_file}")

    result = subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-i",
            str(input_file),
            "-c:a",
            "libvorbis",
            "-q:a",
            str(QUALITY),
            str(output_file),
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    if result.returncode == 0:
        print(f"  -> {output_file}")
    else:
        print(f"  Failed: {input_file}")