FROM ubuntu:22.04

# Install runtime dependencies for headless Godot
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libfontconfig1 \
    libxcursor1 \
    libxinerama1 \
    libxi6 \
    libxrandr2 \
    libasound2 \
    libpulse0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /game

# Copy the exported Linux server build
COPY game/build/server/ /game/

# Make executable
RUN chmod +x /game/game.x86_64

# WebSocket port
EXPOSE 7777

# Run Godot headless in dedicated server mode
CMD ["/game/game.x86_64", "--headless", "--", "--server"]
