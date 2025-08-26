# cl10 — Clipboard watcher (CLI-only MVP)

A minimalist, keyboard-first clipboard history manager for macOS.
This MVP is **text-only, ephemeral, foreground**, with a single binary that runs both the watcher and the CLI.

> Status: **MVP** — stable enough for daily use; no persistence yet.

---

## Features (MVP)

* **Clipboard watcher** (`cl10 watch`) observes the macOS pasteboard (text only).
* **In-memory ring buffer**: fixed capacity **10** (indices **0..9**, `0` = newest).
* **De-dupe**: new text that matches an existing entry (after normalization) moves that entry to `0` — no duplicates.
* **UNIX socket IPC**: CLI talks to the watcher via `/tmp/cl10-$UID.sock` (0600 perms).
* **No persistence**: history lives only while the watcher is running.
* **No Accessibility prompts**: we read and write the clipboard; we do **not** simulate paste.

Normalization rules:

* Trim trailing newlines.
* Convert `CRLF → LF`.
* Case-sensitive (no lowercasing).
* Ignore empty/whitespace-only captures.
* Skip items larger than **256 KB**.

---

## Requirements

* macOS **12+**
* Swift toolchain (Xcode or Command Line Tools)

---

## Install / Build

From the project root (the folder with `Package.swift`):

```bash
swift build -c release
# optional: symlink so `cl10` is on your PATH
sudo ln -sf "$(pwd)/.build/release/cl10" /usr/local/bin/cl10
```

If you prefer not to symlink, call the binary directly: `./.build/release/cl10`.

---

## Usage

Open **two terminal tabs**: keep the watcher running in one, issue commands from the other.

### Start the watcher (tab 1)

```bash
cl10 watch
# or: ./.build/release/cl10 watch
# [INFO] … IPC listening at /tmp/cl10-<uid>.sock
# [INFO] … Watcher started
```

### Drive it (tab 2)

```bash
cl10 list                 # show 0..9 with preview + byte size
cl10 add "hello world"    # add arbitrary text (doesn’t touch clipboard)
cl10 copy 0               # copy item at index 0 to the system clipboard
cl10 up 3                 # move item 3 up one
cl10 down 1               # move item 1 down one
cl10 top 7                # move item 7 to the top (index 0)
cl10 del 2                # delete item 2
cl10 clear                # clear all (asks “YES” if TTY)
cl10 version              # prints CLI version; if watcher reachable, shows Watcher version too
```

### Quick smoke check

```bash
cl10 add "hello"
cl10 list
cl10 copy 0 && pbpaste    # -> hello
```

> Tip: the watcher log prints `[INFO] Capture: …` whenever it sees new text from other apps.
> Self-writes (from `cl10 copy N`) are ignored to avoid loops.

---

## Wire protocol (for debugging)

The watcher speaks single-line commands over a UNIX domain socket at `/tmp/cl10-$UID.sock`.

```bash
# Using `nc`:
printf 'PING\n'    | nc -U /tmp/cl10-$(id -u).sock    # -> PONG
printf 'VERSION\n' | nc -U /tmp/cl10-$(id -u).sock    # -> CL10 0.1.0-mvp
printf 'LIST\n'    | nc -U /tmp/cl10-$(id -u).sock
```

Supported commands: `LIST`, `COPY n`, `ADD <text>`, `DEL n`, `CLEAR`, `UP n`, `DOWN n`, `TOP n`, `VERSION`, `PING`.

---

## Output format

`cl10 list` prints one line per non-empty slot:

```
0  "SELECT …"  128B
1  "hello"     5B
```

Previews show the **first line** of the text (escaped) and the **byte length**.

---

## Exit codes (CLI)

* `0` success
* `1` generic error
* `2` bad arguments / index out of range
* `3` watcher not running / cannot connect to socket
* `4` command timeout (IPC/connect)
* `5` unsupported operation

Canonical messages:

* No watcher: `E3 Watcher not running. Start it with: cl10 watch`
* Bad index: `E2 Index out of range. Use 'cl10 list' for valid indices.`
* Timeout: `E4 Timed out talking to watcher. Is it running?`

---

## Logging

* **Watcher stdout**:

  * `INFO` on start/stop and new captures
  * `WARN Skipped text >256KB` for oversize items
  * `ERROR` on fatal failures
* **CLI**: human one-liners only; no log files.

---

## Troubleshooting

**Renamed/moved the repo and now it won’t build?**
Swift caches can retain absolute paths.

```bash
# stop watcher + remove socket (optional)
pkill -f "/cl10 watch" || true
rm -f /tmp/cl10-$(id -u).sock

# clean SwiftPM state
rm -rf .build .swiftpm
swift package reset

# (optional) clear Xcode cache
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex

# rebuild
swift build -c release
```

**CLI says “watcher not running” but watcher is up?**
You may have multiple watchers or a stale socket.

```bash
pkill -f "/cl10 watch" || true
rm -f /tmp/cl10-$(id -u).sock
cl10 watch
```

**Verify the socket directly:**

```bash
printf 'PING\n' | nc -U /tmp/cl10-$(id -u).sock   # -> PONG
```

---

## Project layout

```
Package.swift
Sources/
  CL10/
    main.swift
    CLI/CLI.swift
    IPC/Client.swift
    IPC/Server.swift
    Watcher/PasteboardWatcher.swift
    Ring/HistoryStore.swift
    Clipboard/Clipboard.swift
    Common/{Constants,Logger,Normalizer,ExitCode,SocketPaths}.swift
    IPC/Wire.swift
```

---

## Roadmap (from the briefs)

* **Shell mode** (`cl10 shell`): interactive picker, reorder with keys.
* **Menu bar picker** (read-only; click to copy).
* **Persistence** (opt-in): file/SQLite; optional encryption via Keychain-wrapped key.
* **Images/files** (later): extend beyond text.
* **“Paste” automation** (later): out of MVP; would require Accessibility consent.
* **Packaging**: universal binaries, notarization, Homebrew tap.

---

## License

MIT kgro 2025.
