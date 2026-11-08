# zcat reference

A terminal-aware `cat` alternative written in Zig. Read highlighted code with file headers and line numbers, render Markdown, or display PNG and JPEG images with Kitty graphics.

The project is named **zcat**; its executable is **`zc`**. It doesn't decompress files or replace gzip's `zcat` command.

## Install with Homebrew

Add this repository as a tap, then install the [zcat formula](Formula/zcat.rb):

```sh
brew tap crumblebot/zcat https://github.com/crumblebot/zcat
brew install crumblebot/zcat/zcat
zc README.md
```

The formula is named `zcat` and installs the `zc` command. It doesn't install `zcat` or `zcat-view` aliases.

The tap downloads checksum-pinned release binaries with bundled license notices. You don't need Zig or build dependencies. Releases target Apple Silicon and Intel Macs running macOS 15 or later, and Linux x86-64. Linux packages use static musl linking; all release packages use baseline CPU targets. The release workflow runs native tests before publishing each platform's binary.

Upgrade with `brew update && brew upgrade crumblebot/zcat/zcat`. Uninstall with `brew uninstall crumblebot/zcat/zcat`.

### Migrate from the old tap

If you installed `crumblebot/tap/zcat`, reinstall it from this repository. This briefly removes `zc` without removing other formulas:

```sh
brew uninstall crumblebot/tap/zcat
brew tap crumblebot/zcat https://github.com/crumblebot/zcat
brew install crumblebot/zcat/zcat
zc --version
```

If you no longer use any formulas from `crumblebot/tap`, remove the old tap:

```sh
brew untap crumblebot/tap
```

If Homebrew refuses to load the old formula because it's untrusted, restore formula-specific trust and retry:

```sh
brew trust --formula crumblebot/tap/zcat
brew untap crumblebot/tap
```

Current Homebrew revokes formula-specific trust after uninstalling. Older Homebrew versions might not provide `brew trust`.
Don't force the untap if Homebrew reports other installed formulas. Use the fully qualified formula name to avoid ambiguity.

### Maintain the formula

Update `Formula/zcat.rb` in this repository after publishing a release. Verify each archive against the release's `SHA256SUMS`, then update the URLs and hashes. Don't replace existing release tags or assets.

The old `crumblebot/homebrew-tap` repository has been deleted. Migration works from an existing local tap; don't try to install or clone it again. This repository is the only maintained formula source.
The [Homebrew workflow](.github/workflows/homebrew.yml) checks explicit-URL installation, formula tests, style, strict audit, and uninstall on Linux x86-64 and both Mac architectures.

## Build from source

You need **Zig 0.17.1**, Git, and network access for the first build. The compiler version is pinned in `.zigversion`. Download Zig from the [official Zig downloads page](https://ziglang.org/download/) and verify its published SHA-256 checksum.

Build the executable:

```sh
git clone https://github.com/crumblebot/zcat.git
cd zcat
zig build -Doptimize=ReleaseSafe -j2
./zig-out/bin/zc --help
```

The executable is `zig-out/bin/zc`. Grammars, the image decoder, and the Tree-sitter runtime compile into the binary; no system Tree-sitter installation is required. The dependency commit and package hash are pinned in `build.zig.zon`. Transitive grammar revisions and hashes are pinned by ztreesitter.

Optionally install `zc` in your local binary directory:

```sh
mkdir -p "$HOME/.local/bin"
cp zig-out/bin/zc "$HOME/.local/bin/zc"
```

If you built an earlier version, remove its `zig-out` directory before rebuilding to discard the old executable. Update scripts that invoke `zcat-view` or this project's former `zcat` binary to use `zc`.

Linux x86-64, macOS Intel, and macOS ARM64 builds have passed native tests. Linux ARM64 with musl is cross-compiled, not runtime-tested. Windows isn't verified.

## Read files and stdin

Highlight source files automatically when stdout is a terminal:

```sh
zc src/main.zig
zc README.md
zc -n src/options.zig src/terminal.zig
printf 'const answer = 42;\n' | zc -l zig
```

Concatenate exact bytes when stdout is redirected:

```sh
zc first.txt second.txt > combined.txt
printf 'stdin\n' | zc first.txt - second.txt
zc -- -dash-prefixed-file
```

No filenames means stdin. Each `-` reads stdin at its current position; after EOF, subsequent `-` operands contribute no bytes. Raw and redirected files are processed in order, without banners or separators.

Force highlighting in a redirected output, or render Markdown without ANSI colors:

```sh
zc --color=always -l python script.py > highlighted.ansi
zc --markdown --color=never README.md > readable.txt
zc --markdown --width 60 tests/fixtures/sample.md
```

Use `--plain` for unmodified streaming output even in a terminal:

```sh
zc --plain data.bin > copy.bin
```

**Security:** Pretty output escapes input terminal controls, including ESC, OSC sequences, C1 controls, and bidirectional overrides. It never opens URLs or emits OSC hyperlinks. Raw output deliberately preserves all input bytes, including control sequences. Don't use `--plain` to inspect untrusted files directly in a terminal. Normal redirected output also preserves any ANSI sequences already present in the input; it adds none.

## Code headers and line numbers

Pretty output for recognized source languages includes an escaped filename, language, and per-file line numbers. Stdin uses the label `stdin`. Markdown fences don't receive file headers or automatic numbers. Plain text doesn't receive decorations.

Disable either decoration independently:

```sh
zc --no-header src/main.zig
zc --no-line-numbers src/main.zig
zc --no-header --no-line-numbers --color=always src/main.zig
```

`-n` keeps explicit continuous numbering across files, including raw pipes. Headers aren't numbered. In pretty code output, a header starts on a new line, even if the previous file has no final newline. Automatic per-file numbering also finishes an unterminated final line. `--plain` disables all automatic decorations. Default redirected output remains byte-for-byte unchanged.

Number prefixes occupy at least eight cells. Source lines aren't wrapped or truncated, so long code lines can exceed the terminal width. With explicit `-n`, Markdown reserves eight cells from its layout width.

## Display images

In Ghostty, run:

```sh
zc photo.png
zc photo.jpg
zc README.md
```

`zc` transmits decoded RGBA pixels directly through the [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/). It doesn't run shell tools or open image viewers. PNG and JPEG are supported, including local Markdown images in prose:

```markdown
![Screenshot](images/screenshot.png)
![A filename with spaces](images/screen%20shot.jpg)
![Another filename with spaces](<images/screen shot.png>)
```

Relative paths resolve against the Markdown file's directory; stdin resolves against the working directory. Absolute local paths are allowed. Percent escapes decode once. URL schemes, network paths, query strings, fragments, and control bytes are rejected. Remote images receive a textual diagnostic; they aren't fetched. Local image errors identify the input document on stderr and stop that document, but later file operands still run. Only open trusted Markdown: local image references can read files accessible to your user, including paths outside the document directory.

Images use separate display rows with escaped alt text. Fenced code, inline code, and table cells don't display embedded images. Reference-style images, optional titles, and destinations containing literal parentheses aren't implemented. Encode parentheses as `%28` and `%29`. GIF, WebP, BMP, TIFF, and AVIF aren't supported; there is no ASCII, colored-block, Sixel, or external-viewer fallback.

### Terminal support

[Ghostty's official feature documentation](https://ghostty.org/docs/features) explicitly lists Kitty graphics support. Automatic image output requires a TTY with `TERM=xterm-ghostty`, `TERM=xterm-kitty`, or `TERM_PROGRAM=ghostty`. These markers aren't a protocol handshake. Multiplexer passthrough isn't implemented.

Rex's [official installation documentation](https://www.superlogical.com/rex/docs/installation) lists a macOS client and Linux/FreeBSD servers. Its [public documentation index](https://www.superlogical.com/rex/docs/llms.txt) doesn't establish Kitty or Sixel graphics support. Rex compatibility is **unverified**, and Rex isn't automatically enabled. If your Rex version supports Kitty graphics, explicitly opt in:

```sh
zc --images=kitty photo.png
zc --images=kitty README.md
```

`--images=kitty` trusts your terminal choice and can emit protocol escapes into redirected output. It also enables pretty processing for stdin. `--images=never` disables graphics; pretty local-image requests then fail with `ImageProtocolUnavailable`. Use `--plain` for original bytes instead. Unsupported or unrecognized terminals receive the same diagnostic in pretty mode. There are no terminal queries or waits for terminal replies, even with piped stdin.

Image dimensions fit within the terminal's columns and available rows without upscaling. The renderer uses the window-size ioctl for cell geometry, with an 8 × 16 pixel estimate when pixel dimensions aren't available. Without a reported grid, it uses configured width and 24 rows. It preserves aspect ratio, caps placement at 240 columns and 100 rows, and reserves one reported terminal row. Nearest-neighbor downsampling can reduce image quality. Already printed images don't reflow after resizing.

No native Ghostty or Rex client was available in the Linux development environment. Protocol and PTY tests verify transmitted bytes and sizing, not visual appearance in those clients. See [image verification](IMAGE_VERIFICATION.md).

## Options

| Option | Behavior |
| --- | --- |
| `--color=auto` | Add ANSI colors only for terminals. This is the default. |
| `--color=always` | Add ANSI colors and enable pretty output even in pipes. |
| `--color=never` | Never add ANSI colors. Terminal Markdown rendering remains enabled. |
| `-l NAME`, `--language NAME`, `--language=NAME` | Override extension and shebang detection. |
| `-m`, `--markdown` | Render Markdown even when output is redirected. |
| `-n`, `--number` | Number output lines continuously across files. Number rendered lines in pretty mode. |
| `--no-header` | Hide the automatic pretty-code filename and language header. |
| `--no-line-numbers` | Disable automatic code numbering; can't combine with `-n`. |
| `--images=auto\|kitty\|never` | Detect Ghostty/Kitty TTYs, explicitly emit Kitty graphics, or disable images. |
| `--plain`, `--raw` | Stream exact bytes; override color and language options. Can't combine with Markdown, explicit numbering, or `--images=kitty`. |
| `--width N` | Set Markdown layout and maximum image width to 20–240 cells. |
| `--list-languages` | List canonical language names. |
| `-h`, `--help` | Show help. |
| `-V`, `--version` | Show version. |
| `--` | Treat remaining operands as filenames. |

`NO_COLOR`, when nonempty, and `TERM=dumb` suppress automatic colors. Explicit `--color=always` overrides both. Width defaults to `COLUMNS`, clamped to 20–240, or 80. `--width` takes precedence. No pager is started.

Exit status is 0 on success, 1 on input or output errors, and 2 on invalid arguments. Input errors identify the file and don't prevent reading later files. Output errors stop processing. A closed pipe can also terminate through the operating system's broken-pipe signal.

## Syntax highlighting

The renderer uses [pedronaugusto/ztreesitter](https://github.com/pedronaugusto/ztreesitter) to parse source and execute each grammar's bundled highlight query, including query predicates. Highlighting isn't a regular-expression approximation. Smaller captures take precedence over enclosing captures; a compact ANSI palette colors comments, strings, keywords, types, numbers, and functions.

| Language | Names and detected extensions |
| --- | --- |
| Zig | `zig` |
| JavaScript | `javascript`, `js` |
| TypeScript | `typescript`, `ts` |
| TSX and JSX | `tsx`, `jsx` |
| Python | `python`, `py` |
| JSON | `json` |
| Bash | `bash`, `sh`, `shell` |
| C | `c`, `h` |
| Rust | `rust`, `rs` |
| Markdown | `markdown`, `md` |
| Plain text | `text`, `plain`, `txt` |

Extensions are case-insensitive. Python, Node.js, Bash, and `/sh` shebangs provide fallback detection for extensionless input and stdin. Unknown files remain text. `-l text` disables source highlighting and automatic Markdown rendering. A language override alone doesn't enable pretty output in a pipe; add `--color=always` or `--markdown`.

## Markdown subset

The native terminal renderer supports:

- ATX headings, from `#` through `######`, with a space after the markers.
- Paragraphs with joined soft line breaks and width-aware wrapping.
- Flat unordered lists, ordered lists, and block quotes.
- Paired single-marker emphasis, double-marker strong emphasis, and single-backtick inline code.
- Inline links rendered as `label (URL)`, without active terminal hyperlinks.
- Backtick and tilde fences, with optional language names and Tree-sitter code highlighting.
- Pipe tables with header and delimiter rows, optional outer pipes, alignment markers, and wrapped cells.
- Horizontal rules composed of at least three `-`, `*`, or `_` markers.
- Escaped inline punctuation and literal unknown markup.

Tables keep column boundaries aligned, excluding ANSI styling from width calculations. Long words and cell contents wrap within `--width`. When columns can't fit with three content cells each, rows use stacked header/value pairs. Escape literal pipes as `\|`; pipes inside matched backtick spans don't split cells. Missing cells are empty; extra cells are ignored. Tables end at blank lines, non-pipe prose, headings, lists, quotes, or fences. Rows longer than 16 KiB or wider than 32 columns remain ordinary text.

This is **not a CommonMark implementation**. HTML, reference links, nested list layout, task checkboxes, setext headings, multi-backtick inline code styling, and full delimiter-flanking rules aren't implemented. Nested inline styles can lose outer ANSI styling after an inner reset. Unknown constructs remain readable text rather than receiving full Markdown semantics.

Prose wraps to the configured width; code blocks preserve source lines and don't wrap internally. Cell widths approximate combining marks and East Asian characters, not complete grapheme shaping. Emoji sequences and terminal-specific ambiguous widths can differ. Escaped controls can exceed the nominal width. Lists and quotes use flat prefixes without hanging indentation. Resizing a terminal doesn't reflow already printed text.

## Resource and binary behavior

Normal cat mode streams with bounded buffers and preserves arbitrary bytes, including invalid UTF-8 and NUL. Number-only pipe output also streams.

Images allow at most **16 MiB encoded**, **8192 pixels per axis**, and **16,777,216 decoded pixels**. The decoder has a **128 MiB allocation budget**, including intermediates. Decoder failures and budget exhaustion report `InvalidImage`; input-limit errors can report `StreamTooLong`. RGBA resampling adds at most 64 MiB. Kitty payload chunks contain at most 4096 base64 bytes, and quiet mode suppresses terminal replies.

Pretty text mode buffers up to **8 MiB per input** for parsing. Larger text inputs fall back to streaming, control-escaped text without highlighting, headers, automatic numbering, or Markdown conversion. Invalid UTF-8 or NUL-containing inputs also use control-escaped text in pretty mode. Incomplete or invalid UTF-8 bytes appear as `\xNN`. The large-input fallback preserves valid UTF-8 across chunk boundaries.

Inline Markdown spans longer than 16 KiB remain literal text to bound delimiter-search work. Inline nesting stops after eight levels. Highlighting doesn't perform semantic analysis, language injections, or theme customization. Parse trees and queries add memory beyond the input buffer; the cap isn't a total memory limit.

## Run checks

Python 3 is required only for CLI integration tests. The integration suite uses Unix pseudoterminals and Python's standard library.

```sh
zig fmt --check build.zig build.zig.zon src
zig build test integration -j2
zig build test integration -Doptimize=ReleaseSafe -j2
zig build test integration -Doptimize=ReleaseFast -j2
zig build -Doptimize=ReleaseSafe -j2
zig build -Dtarget=aarch64-linux-musl -Doptimize=ReleaseSafe -j2
```

Unit tests compile and run all nine grammar highlight queries. Black-box tests cover binary identity, multiple operands, stdin, detection, actual highlighting, PTY policies, Markdown, Unicode, control escaping, large inputs, and input/output errors. GitHub Actions runs the three native optimization modes and the ARM64 cross-build.

## License

zcat is MIT-licensed. Bundled dependencies have their own licenses and retained copyright notices. See [third-party notices](THIRD_PARTY.md) and [`licenses/`](licenses/). Include those notices when distributing binaries.
