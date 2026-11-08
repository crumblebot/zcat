# Image and code decoration verification

## Protocol evidence

Primary sources inspected on November 8, 2026:

- [Ghostty features](https://ghostty.org/docs/features) explicitly states that Ghostty supports the Kitty graphics protocol for images in the terminal.
- [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/) specifies direct transmission (`t=d`), RGBA (`f=32`), base64 chunks of at most 4096 bytes, continuation (`m`), quiet mode (`q=2`), and placement columns/rows (`c`, `r`). Both placement dimensions preserve aspect ratio through letterboxing. `C=1` disables automatic cursor movement. zcat reserves rows with linefeeds after transmission, which can scroll at the bottom margin.
- [Rex installation](https://www.superlogical.com/rex/docs/installation.md) lists a macOS client, Linux/FreeBSD servers, and clients for other platforms not yet publicly available.
- [Rex documentation index](https://www.superlogical.com/rex/docs/llms.txt) and [complete public documentation](https://www.superlogical.com/rex/docs/llms-full.txt) don't document a Kitty or Sixel graphics guarantee. A mention of Kitty desktop notifications isn't evidence of image-protocol support. This is an evidence gap, not proof that Rex cannot display images.

Only known Ghostty/Kitty environment markers enable automatic graphics on a TTY. `--images=kitty` explicitly trusts the user's terminal selection, including redirected output. No terminal response query, subprocess, network fetch, filesystem-transfer protocol, or text-art fallback is used.

## Local checks

Linux x86-64, official checksum-verified Zig 0.17.1:

- `zig fmt --check build.zig build.zig.zon src`.
- `zig build test integration -Doptimize=MODE -j2 --summary all`: 10 Zig tests, 18 existing/extended CLI tests, and 5 image tests passed in each of Debug, ReleaseSafe, and ReleaseFast.
- Native installs and version/raw smoke checks passed in all three modes, using separate temporary prefixes. No system binary was replaced.
- Static baseline x86-64 Linux-musl ReleaseSafe: the same 10 Zig and 23 Python tests passed.
- ReleaseSafe baseline cross-builds passed for Linux ARM64-musl, macOS ARM64 15.0, and macOS Intel 15.0. These cross-builds weren't executed.
- Actionlint and `git diff --check` passed.
- Vendored decoder and license hashes match the exact upstream files recorded in `THIRD_PARTY.md`.

The first cross-build attempt exhausted workspace disk space. Removing only zcat's generated `.zig-cache` restored space; all three cross-builds then passed. No source or other worktree was removed.

### Regression coverage

- Default code headers, escaped filenames, stdin labels, per-file numbering, independent opt-outs, explicit continuous `-n`, raw pipes, and multiple operands.
- Exact decoded PNG pixels through native Kitty RGBA transfer, a generated JPEG fixture, 3072-byte raw chunk boundaries, base64 round trips, continuation flags, and quiet mode.
- Direct PNG/JPEG files, terminal auto-selection, explicit image opt-in, unsupported-terminal diagnostics, and byte-preserving raw output.
- Markdown relative paths from a different working directory, percent-encoded spaces, angle-bracket paths with spaces, escaped alt text, missing files, nonlocal URLs, control bytes, invalid percent escapes, and fenced code.
- Payloads bypass the text-numbering adapter, including explicitly numbered Markdown.
- Corrupt input, encoded-size limits, oversized dimensions/pixel counts, multiple images, and `/dev/full` output errors.
- PTY window geometry, preserved aspect ratio, fit within terminal rows/columns, and pipe stdin without terminal queries or hangs.
- Existing Markdown, table layout, highlighting, byte identity, control escaping, large-text fallback, closed pipes, and input errors remain covered.

## Visual limits

Neither Ghostty nor the Rex client is installed in the Linux development environment. Ghostty isn't available from this environment's configured apt repositories. Rex's public client is macOS-only. A server-only installation wouldn't provide a native visual test. Native Ghostty and Rex visual checks were **not performed**. Protocol/PTY assertions aren't a substitute for viewing an image in those terminals.

Rex compatibility remains unverified. Test `zc --images=kitty photo.png` in a Rex version with confirmed Kitty graphics support. Unsupported terminals have no image fallback. Multiplexer passthrough, animation, remote URLs, and formats beyond PNG/JPEG aren't implemented.
