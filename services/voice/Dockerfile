# Oneova voice server: Cloud Run with one NVIDIA L4 (see deploy.sh).
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
RUN apt-get update && apt-get install -y --no-install-recommends python3.11 python3-pip ffmpeg libsndfile1 git curl unzip \
 && rm -rf /var/lib/apt/lists/* && ln -sf /usr/bin/python3.11 /usr/bin/python
WORKDIR /app
COPY requirements.txt .
RUN python -m pip install --upgrade pip && python -m pip install -r requirements.txt
# OpenVoice v2 converter weights (MIT). Verify the URL and checksum at V0.
RUN mkdir -p /models/openvoice_v2 && curl -fsSL -o /tmp/ov2.zip "${OPENVOICE_V2_URL:-https://myshell-public-repo-host.s3.amazonaws.com/openvoice/checkpoints_v2_0417.zip}" \
 && unzip -q /tmp/ov2.zip -d /tmp/ov2 && mv /tmp/ov2/checkpoints_v2/converter /models/openvoice_v2/converter && rm -rf /tmp/ov2 /tmp/ov2.zip
# Warm the Chatterbox weights into the image so cold starts don't download them.
RUN python -c "from chatterbox.mtl_tts import ChatterboxMultilingualTTS as M; M.from_pretrained(device='cpu', t3_model='v3')" || true
COPY voice ./voice
RUN useradd -m app && chown -R app /app /models
USER app
CMD ["sh", "-c", "uvicorn voice.api:app --host 0.0.0.0 --port ${PORT:-8080} --workers 1"]
