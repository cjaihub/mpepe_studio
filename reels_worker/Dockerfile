FROM node:20-bookworm-slim

# FFmpeg from Debian (libx264 + AAC). Open source, runs on our own project.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund
COPY ladder.js index.js ./

USER node
CMD ["node", "index.js"]
