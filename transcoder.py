import subprocess
from pathlib import Path

def transcode_to_720(input_path: str | Path, output_path: str | Path) -> None:
    subprocess.run(
        [
            "ffmpeg",
            "-i", str(input_path),
            "-vf", "scale=-2:720",
            "-c:v", "libx264",
            "-c:a", "aac",
            str(output_path)
        ],
        check=True,
        capture_output=True,
        text=True
    )