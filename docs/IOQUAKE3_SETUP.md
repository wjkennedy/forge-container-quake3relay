# ioquake3 Setup Guide

The ioquake3 Dockerfile can take a long time to build from source (5-15 minutes depending on your system). Here are faster alternatives.

## Option 1: Use Pre-built Binary (Fastest - Recommended)

Download a pre-compiled ioquake3 binary and mount it via Docker volume:

```bash
# Download pre-built binary (example)
wget https://ioquake3-builds.example.com/ioquake3.x86_64

# Run with docker-compose override
docker-compose -f docker-compose.yml \
  -f docker-compose.override.yml \
  up --build
```

**docker-compose.override.yml:**
```yaml
services:
  ioquake3:
    volumes:
      - ./ioquake3.x86_64:/opt/ioquake3/build/release-linux-x86_64/ioquake3.x86_64:ro
```

## Option 2: Use Lightweight Dockerfile (No Build)

```bash
# Use the lightweight Dockerfile that expects a pre-built binary
docker build -f docker/ioquake3/Dockerfile.lightweight \
  -t quake3-server:lightweight .
```

Then mount your pre-built binary:
```bash
docker run -p 27960:27960/udp \
  -v ./ioquake3.x86_64:/opt/ioquake3/build/release-linux-x86_64/ioquake3.x86_64:ro \
  quake3-server:lightweight
```

## Option 3: Build Locally (One-time, Fastest for Later Runs)

Build ioquake3 once on your machine, then use Docker to run it:

```bash
# Clone and build locally
git clone https://github.com/ioquake/ioq3
cd ioq3
make -j$(nproc) PLATFORM=linux ARCH=x86_64 SKIP_RENDERER=1 USE_CODEC_OPUS=1

# Copy binary to project
cp build/release-linux-x86_64/ioquake3.x86_64 ../forge-quake3-relay/docker/ioquake3/

# Use the lightweight Docker image
cd ../forge-quake3-relay
docker-compose -f docker-compose.yml up
```

## Option 4: Use Mock Q3 Server (Development Only)

For testing the relay without a real Quake 3 server:

```bash
# Create a simple UDP echo server for testing
npm run test:mock-server
```

## Build Dependencies (if building from source)

The current Dockerfile includes:
- `libsdl2-dev` - Graphics library
- `libcurl4-openssl-dev` - HTTP client
- `libgl1-mesa-dev` - OpenGL support
- `libopusfile-dev` - Audio codec
- `libopus-dev` - Audio codec

## Troubleshooting

**Build fails with "Error: undefined reference"**
- Ensure all dev packages are installed
- Try: `apt-get install -y libglvnd-dev libx11-dev`

**Binary not found after build**
- Check build.log: `docker build ... 2>&1 | tee build.log`
- Ensure nproc returns a valid number

**Cannot bind UDP port 27960**
- Check if port is in use: `netstat -nulp | grep 27960`
- Try a different port: `-p 27961:27960/udp`

## Fastest Setup Path

1. Download a pre-built ioquake3 binary
2. Use `Dockerfile.lightweight`
3. Mount binary via Docker volume
4. Run relay with `docker-compose up`

This gives you a running relay in seconds instead of minutes.
