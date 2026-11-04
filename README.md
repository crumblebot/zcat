# zcat

A terminal-aware `cat` alternative written in Zig. Read source files with Tree-sitter syntax highlighting, or render Markdown in your terminal.

**Name collision:** Unix systems often provide a gzip decompressor named `zcat`. This project doesn't decompress files. Don't replace `/usr/bin/zcat`. Run the local binary or install it under a distinct name, such as `zcat-view`.

## Build and install

You need **Zig 0.17.1**, Git, and network access for the first build. The compiler version is pinned in `.zigversion`. Download Zig from the [official Zig downloads page](https://ziglang.org/download/) and verify its published SHA-256 checksum.

Build the executable:

```sh
git clone https://github.com/crumblebot/zcat.git
cd zcat
zig build -Doptimize=ReleaseSafe -j2
./zig-out/bin/zcat --help
```

The executable is `zig-out/bin/zcat`. Grammars and the Tree-sitter runtime compile into the binary; no system Tree-sitter installation is required. The dependency commit and package hash are pinned in `build.zig.zon`. Transitive grammar revisions and hashes are pinned by ztreesitter.

Optionally install it without shadowing the system decompressor:

```sh
mkdir -p "$HOME/.local/bin"
cp zig-out/bin/zcat "$HOME/.local/bin/zcat-view"
```

Linux x86-64 is tested natively. Linux ARM64 with musl is cross-compiled, not runtime-tested. Other platforms aren't currently verified.

## Read files and stdin

Highlight source files automatically when stdout is a terminal:

```sh
./zig-out/bin/zcat src/main.zig
./zig-out/bin/zcat README.md
./zig-out/bin/zcat -n src/options.zig src/terminal.zig
printf 'const answer = 42;\n' | ./zig-out/bin/zcat -l zig
```

Concatenate exact bytes when stdout is redirected:

```sh
./zig-out/bin/zcat first.txt second.txt > combined.txt
printf 'stdin\n' | ./zig-out/bin/zcat first.txt - second.txt
./zig-out/bin/zcat -- -dash-prefixed-file
```

No filenames means stdin. Each `-` reads stdin at its current position; after EOF, subsequent `-` operands contribute no bytes. Files are processed in order, without banners or separators.

Force highlighting in a redirected output, or render Markdown without ANSI colors:

```sh
./zig-out/bin/zcat --color=always -l python script.py > highlighted.ansi
./zig-out/bin/zcat --markdown --color=never README.md > readable.txt
./zig-out/bin/zcat --markdown --width 60 tests/fixtures/sample.md
```

Use `--plain` for unmodified streaming output even in a terminal:

```sh
./zig-out/bin/zcat --plain data.bin > copy.bin
```

**Security:** Pretty output escapes input terminal controls, including ESC, OSC sequences, C1 controls, and bidirectional overrides. It never opens URLs or emits OSC hyperlinks. Raw output deliberately preserves all input bytes, including control sequences. Don't use `--plain` to inspect untrusted files directly in a terminal. Normal redirected output also preserves any ANSI sequences already present in the input; it adds none.

## Options

| Option | Behavior |
| --- | --- |
| `--color=auto` | Add ANSI colors only for terminals. This is the default. |
| `--color=always` | Add ANSI colors and enable pretty output even in pipes. |
| `--color=never` | Never add ANSI colors. Terminal Markdown rendering remains enabled. |
| `-l NAME`, `--language NAME`, `--language=NAME` | Override extension and shebang detection. |
| `-m`, `--markdown` | Render Markdown even when output is redirected. |
| `-n`, `--number` | Number output lines continuously across files. Number rendered lines in pretty mode. |
| `--plain`, `--raw` | Stream exact bytes; override color and language options. Can't combine with Markdown or numbering. |
| `--width N` | Set Markdown prose and rule width to 20–240 cells. |
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
- Horizontal rules composed of at least three `-`, `*`, or `_` markers.
- Escaped inline punctuation and literal unknown markup.

This is **not a CommonMark implementation**. Tables, HTML, images, reference links, nested list layout, task checkboxes, setext headings, multi-backtick inline code, and full delimiter-flanking rules aren't implemented. Nested inline styles can lose outer ANSI styling after an inner reset. Unknown constructs remain readable text rather than receiving full Markdown semantics.

Prose wraps to the configured width; code blocks preserve source lines and don't wrap internally. Cell widths approximate combining marks and East Asian characters, not complete grapheme shaping. Emoji sequences and terminal-specific ambiguous widths can differ. Escaped controls can exceed the nominal width. Lists and quotes use flat prefixes without hanging indentation. Resizing a terminal doesn't reflow already printed text.

## Resource and binary behavior

Normal cat mode streams with bounded buffers and preserves arbitrary bytes, including invalid UTF-8 and NUL. Number-only pipe output also streams.

Pretty mode buffers up to **8 MiB per input** for parsing. Larger inputs fall back to streaming, control-escaped text without highlighting or Markdown conversion. Invalid UTF-8 or NUL-containing inputs also use control-escaped text in pretty mode. Incomplete or invalid UTF-8 bytes appear as `\xNN`. The large-input fallback preserves valid UTF-8 across chunk boundaries.

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
