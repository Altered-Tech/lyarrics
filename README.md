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

#### `scan [path]`

Scan a music directory and index all audio files into the local database. `path` can be omitted
if the `LYARRICS_MUSIC_PATH` environment variable is set.

```sh
lyarrics scan /path/to/music
```

#### `fetch`

Fetch lyrics from LRCLIB for all songs in the database that are missing lyrics.

> **Behavior change:** `fetch` used to also re-fetch songs that already had *plain*
> (unsynced) lyrics on every run, trying to upgrade them to synced lyrics. That's no
> longer the default — it was silently re-requesting the same songs from LRCLIB forever,
> burning API calls for tracks that had already succeeded. Pass `--upgrade-plain` to get
> the old behavior back.
>
> A song that LRCLIB doesn't have, or that LRCLIB has but with no lyrics submitted for it,
> is now recorded as such (`details` reports these as "Not Found on LRCLIB" / "No Lyrics
> Available") instead of staying "missing" forever and being re-queried on every run. Pass
> `--recheck-unresolved` to re-check them in case LRCLIB's catalog has since been updated.

```sh
lyarrics fetch [options]

Options:
  --scan <path>          Scan a directory before fetching
  --limit <n>            Maximum number of songs to fetch
  --concurrency <n>      Number of concurrent requests (default: 5)
  --delay <ms>           Delay between requests in milliseconds (default: 500)
  --max-retries <n>      Retries for transient errors (default: 3)
  --dry-run              Preview what would be fetched without writing files
  --upgrade-plain        Also re-fetch songs that already have plain (unsynced) lyrics,
                         in case a synced version is now available (default: off)
  --recheck-unresolved   Also re-check songs previously confirmed not found on LRCLIB or
                         with no lyrics available (default: off)
```

#### `search <artist> <album> <track> <duration>`

Look up lyrics for a single song directly from LRCLIB.

```sh
lyarrics search "Artist" "Album" "Track Title" 210
```

#### `serve`

Start a local web server for browsing your library and triggering scans/fetches from the browser.

```sh
lyarrics serve [--hostname 127.0.0.1] [--port 8080]
```

- `/` — dashboard with lyric-status counts and forms to start a scan or fetch
- `/library` — searchable, filterable, paginated track list (`?q=`, `?status=`, `?page=`)
- `/library/<id>` — a track's metadata and lyrics
- `/settings` — set a default music library path, saved in the database so it pre-fills the
  scan form; falls back to `LYARRICS_MUSIC_PATH` until you save one here
- Only one scan or fetch job runs at a time; starting another while one is in progress is a
  no-op until it finishes.

There's no authentication, so only bind `--hostname` to `127.0.0.1` (the default) or a network
you trust.

#### `details`

Show details for lyric stats in the database.

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
    environment:
      LYARRICS_MUSIC_PATH: /music
    ports:
      - "8080:8080"
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

The web UI starts automatically and is reachable at `http://localhost:8080`. There's no
authentication, so only publish that port on a network you trust — change the host side of the
`ports` mapping (e.g. `"9090:8080"`) if you need a different port or to keep it unpublished.

### Running Commands

Logs from the web server and any commands below all go to the same place. Run `lyarrics`
subcommands via `docker exec`:

```sh
docker exec lyarrics lyarrics scan            # path defaults to $LYARRICS_MUSIC_PATH (/music)
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
| `LYARRICS_MUSIC_PATH` | *(none)* | Default music directory for `scan` and the `serve` dashboard's scan form. Inside the container this is always `/music` (the volume mount target), which is why the sample `compose.yaml` sets it for you. |

The `/data` volume persists the database across container restarts.

## Running Tests

```sh
swift test
```

## License

See [LICENSE](LICENSE).
