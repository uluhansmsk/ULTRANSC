# Stage 1: Build whisper.cpp
FROM python:3.11-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    ca-certificates \
    curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git . && \
    cmake -B build -DWHISPER_BUILD_EXAMPLES=ON && \
    cmake --build build --config Release -j$(nproc) --target whisper-cli

# Stage 2: Runtime image
FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    ca-certificates \
    curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy whisper-cli executable
COPY --from=builder /build/build/bin/whisper-cli /usr/local/bin/whisper-cli

# Install latest yt-dlp binary
RUN curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp && \
    chmod a+rx /usr/local/bin/yt-dlp

# Copy application and install
COPY . /app
RUN pip install --no-cache-dir -e .

# Prepare directories
RUN mkdir -p /app/queue/incoming /app/queue/processing /app/queue/done /app/queue/failed /app/workspace /app/models /app/logs

ENTRYPOINT ["python", "-m", "ultransc"]
CMD ["--watch"]
