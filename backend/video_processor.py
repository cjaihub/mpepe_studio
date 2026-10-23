import ffmpeg
import os

def extract_thumbnail(input_path: str, output_path: str) -> None:
    """
    Extracts the very first frame of the video and saves it as a high-quality JPEG.
    """
    try:
        (
            ffmpeg
            .input(input_path, ss=0)
            .output(output_path, vframes=1, qscale=2)
            .overwrite_output()
            .run(capture_stdout=True, capture_stderr=True)
        )
        print(f"Successfully extracted thumbnail to {output_path}")
    except ffmpeg.Error as e:
        print(f"Error extracting thumbnail: {e.stderr.decode('utf-8')}")
        raise

def optimize_video_for_web(input_path: str, output_path: str) -> None:
    """
    Transcodes the video using web-optimized settings:
    - 1080p max height
    - H.264 codec
    - AAC audio
    - -movflags faststart (moves moov atom to beginning)
    - Reasonable bitrate cap
    """
    try:
        (
            ffmpeg
            .input(input_path)
            .output(
                output_path,
                vcodec='libx264',
                acodec='aac',
                movflags='faststart',
                vf="scale=-2:'min(1080,ih)'",
                b='2500k',
                maxrate='2500k',
                bufsize='5000k'
            )
            .overwrite_output()
            .run(capture_stdout=True, capture_stderr=True)
        )
        print(f"Successfully optimized video to {output_path}")
    except ffmpeg.Error as e:
        print(f"Error optimizing video: {e.stderr.decode('utf-8')}")
        raise
