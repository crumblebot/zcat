# Verification record

Verified with the official Zig 0.17.1 compiler on Linux x86-64. The downloaded compiler archive matched SHA-256 `3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a`.

## Version 0.2.0 images and code decorations

See [image and code decoration verification](IMAGE_VERIFICATION.md) for protocol sources, exact local test counts, cross-builds, and the absence of native Ghostty/Rex visual verification. This version retains byte-preserving default redirected output.

## Version 0.1.2 executable rename

The project and release archives remain named `zcat`; the installed executable is `zc`.

Local Linux x86-64 checks passed with Zig 0.17.1:

- Formatting: `zig fmt --check build.zig build.zig.zon src`.
- Unit and integration tests in Debug, ReleaseSafe, and ReleaseFast: 8 Zig tests and 17 CLI tests per mode.
- Clean native installs in all three modes contained `zig-out/bin/zc`, without `zcat` or `zcat-view` executables.
- Help displayed `Usage: zc [OPTIONS] [FILE ...]`; version displayed `zc 0.1.2`.
- Integration tests verified the `zc:` prefix for invalid options and missing files, preserving existing table tests.
- Linux ARM64-musl cross-compilation passed without execution. A native ReleaseSafe build restored the local executable.
- A native raw-mode smoke check reproduced `hello` followed by a newline.

The following sections retain historical executable names and results from earlier versions.

## Version 0.1.1 table regression

The CLI regression failed against 0.1.0 before the renderer changed:

```text
python3 tests/integration.py zig-out/bin/zcat Cli.test_markdown_table_regression
FAIL: ['| Path | Contents | | --- | --- | | apps/server/src/ |',
       'Server code | | apps/web/ | Web client |']
```

The cause was missing table block recognition: header, delimiter, and body lines all entered the paragraph path. The renderer now recognizes the block before paragraph processing and renders cells separately.

After the fix, `zig build test integration -Doptimize=MODE -j2 --summary all` passed **8 Zig tests and 17 CLI tests** in each of Debug, ReleaseSafe, and ReleaseFast. Native builds and `--version` passed in all three modes. Formatting passed. Linux ARM64-musl cross-compilation passed, without execution; the local executable was restored to native ReleaseSafe.

New CLI coverage includes the reported paths table, ANSI-independent column alignment, left/center/right alignment, inline code and links, escaped pipes, code-span pipes, ragged rows, Unicode, control safety, wrapped long words, stacked narrow layouts, block boundaries, malformed delimiters, oversized rows, and a 10,000-row table. The tests drive the real executable, including a PTY table check.

The [native release dry run](https://github.com/crumblebot/zcat/actions/runs/41812578412) passed on Linux x86-64, macOS Intel, and macOS ARM64: 8 Zig tests per platform; 17 CLI passes on Linux, 16 passes and one Linux-only `/dev/full` skip on each Mac. The three-mode [Linux CI run](https://github.com/crumblebot/zcat/actions/runs/41812580766) also passed. Static x86-64-musl baseline-CPU builds passed the same 8 Zig and 17 CLI tests locally. Both baseline-CPU macOS 15 deployment targets cross-compiled locally; release CI executes those targets natively before publication.

Homebrew installation results are recorded in the [tap's CI](https://github.com/crumblebot/homebrew-tap/actions). The historical checks in the following sections describe the initial 0.1.0 release.

## Initial automated checks

| Command | Observed result |
| --- | --- |
| `zig fmt --check build.zig build.zig.zon src` | Passed. |
| `zig build test integration -Doptimize=Debug -j2 --summary all` | 28/28 build steps; 8/8 Zig tests; 13/13 Python CLI tests. |
| `zig build test integration -Doptimize=ReleaseSafe -j2 --summary all` | 28/28 build steps; 8/8 Zig tests; 13/13 Python CLI tests. |
| `zig build test integration -Doptimize=ReleaseFast -j2 --summary all` | 28/28 build steps; 8/8 Zig tests; 13/13 Python CLI tests. |
| `zig build -Doptimize=Debug -j2` | Built and installed a native executable. |
| `zig build -Doptimize=ReleaseSafe -j2` | Built and installed a native executable. |
| `zig build -Doptimize=ReleaseFast -j2` | Built and installed a native executable. |
| `zig build -Dtarget=aarch64-linux-musl -Doptimize=ReleaseSafe -j2` | Built a statically linked ARM64 ELF executable. Not executed. |
| `git diff --cached --check` | Passed before the initial commit. |

`./zig-out/bin/zcat --version` printed `zcat 0.1.0` after each native build. After the cross-build, a native ReleaseSafe build restored the local executable.

## CLI coverage

The Python suite runs the actual executable. It checks:

- Exact binary output in pipes, including NUL, invalid UTF-8, input ANSI sequences, missing final newlines, and inputs exceeding 8 MiB.
- Multiple files, repeated stdin operands, dash-prefixed filenames, and continuous line numbering.
- Extension and shebang detection, explicit language overrides, and ANSI highlighting for every bundled parser.
- Real Unix pseudoterminals for automatic coloring, `NO_COLOR`, `TERM=dumb`, forced color, raw mode, and automatic Markdown rendering.
- Markdown headings, paragraphs, lists, quotes, links, inline styles, rules, closed and unclosed fences, and highlighted fenced code.
- Configured widths, Unicode text, UTF-8 split across streaming boundaries, and input terminal-control escaping.
- Invalid options, missing files, unreadable files, directories, `/dev/full`, and closed output pipes.

The unreadable-file test drops root privileges for the subprocess when necessary. No tests were skipped in the native runs recorded here. These are functional checks, not benchmarks or a complete CommonMark conformance suite.

## Fixed regression

An initial CLI run found that passing a directory into Zig's streaming fast-copy path triggered an `ISDIR` panic. zcat now checks the input type before reading. The integration suite verifies a nonzero normal exit for directories and continued processing after other input errors.

## Manual smoke checks

These commands produced readable output with no added ANSI sequences:

```sh
printf 'stdin smoke\n' | ./zig-out/bin/zcat --plain
./zig-out/bin/zcat -m --color=never tests/fixtures/sample.md
```

The first command reproduced its input. The second rendered the fixture's heading, inline markup, lists, quote, rule, and fenced code.

## Limits of verification

Only Linux x86-64 was executed. ARM64 was cross-compiled only. macOS and Windows weren't tested. No throughput, latency, coverage-percentage, fuzzing, or security-audit claims are made. GitHub Actions repeats the native checks on Ubuntu and cross-compiles ARM64; its live status is available in the repository's Actions tab.
