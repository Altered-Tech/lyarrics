# lyarrics

A Swift CLI tool for fetching and managing synced song lyrics from [LRCLIB](https://lrclib.net).

## Requirements

- Swift 6.2+
- `ffprobe` (part of [FFmpeg](https://ffmpeg.org)) for music library scanning

> **Note:** When running natively on macOS, macOS 15+ is required.

## Building

```sh
swift build -c release
```

## Usage

```
lyarrics <subcommand> [options]
```

### Subcommands

#### `scan <path>`

Scan a music directory and index all audio files into the local database.

```sh
lyarrics scan /path/to/music
```

#### `fetch`

Fetch lyrics from LRCLIB for all songs in the database that are missing lyrics.

```sh
lyarrics fetch [options]

Options:
  --scan <path>        Scan a directory before fetching
  --limit <n>          Maximum number of songs to fetch
  --concurrency <n>    Number of concurrent requests (default: 5)
  --delay <ms>         Delay between requests in milliseconds (default: 500)
  --max-retries <n>    Retries for transient errors (default: 3)
  --dry-run            Preview what would be fetched without writing files
```

#### `search <artist> <album> <track> <duration>`

Look up lyrics for a single song directly from LRCLIB.

```sh
lyarrics search "Artist" "Album" "Track Title" 210
```

#### `serve`

Start a local web server.

```sh
lyarrics serve [--hostname 127.0.0.1] [--port 8080]
```

#### `details`

Show details for a track in the database.

## Architecture

The project has two targets:

- **LRCLib** — Swift library wrapping the LRCLIB API (OpenAPI-generated client)
- **lyarrics** — CLI executable using SQLite for local storage and Hummingbird for the web server

Lyrics are saved as `.lrc` files alongside the original audio files.

## Docker / Linux

Pre-built images are available for Linux (amd64/arm64) on GitHub Container Registry.

### Docker Compose

Create a `compose.yaml` (or copy the one from this repo):

```yaml
name: lyarrics

services:
  lyarrics:
    image: ghcr.io/altered-tech/lyarrics:latest
    container_name: lyarrics
    volumes:
      - lyarrics-data:/data
      - ${MUSIC_PATH}:/music

volumes:
  lyarrics-data:
```

Set `MUSIC_PATH` to your music library and start the container:

```sh
MUSIC_PATH=/path/to/music docker compose up -d
```

### Running Commands

The container keeps running and tails the log file. Run `lyarrics` subcommands via `docker exec`:

```sh
docker exec lyarrics lyarrics scan /music
docker exec lyarrics lyarrics fetch --scan /music
```

Logs are written to `/var/log/lyarrics.log` inside the container and can be viewed with:

```sh
docker logs lyarrics
```

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `LYARRICS_DB_PATH` | `/data/library.db` | Path to the SQLite database |

The `/data` volume persists the database across container restarts.

## Running Tests

```sh
swift test
```

## License

See [LICENSE](LICENSE).
