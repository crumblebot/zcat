# Verification record

Verified with the official Zig 0.17.1 compiler on Linux x86-64. The downloaded compiler archive matched SHA-256 `3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a`.

## Automated checks

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
