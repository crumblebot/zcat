# zcat

A `cat` alternative written in Zig. Run it as **`zc`** to view highlighted code, rendered Markdown, and images.

- Code highlighting with [ztreesitter](https://github.com/pedronaugusto/ztreesitter), file headers, and line numbers.
- Markdown with tables and highlighted code blocks.
- PNG/JPEG images and local Markdown images through Kitty graphics.
- Byte-preserving output when piped; no pager.

## Install

Homebrew packages support macOS 15+ on Apple Silicon and Intel, and Linux x86-64:

```sh
brew tap crumblebot/zcat https://github.com/crumblebot/zcat
brew install crumblebot/zcat/zcat
```

## Use

```sh
zc src/main.zig                         # Highlight code
zc README.md                            # Render Markdown
zc photo.png                            # Display an image in Ghostty or Kitty
zc --no-header --no-line-numbers main.c  # Hide code decorations
zc -l python script                      # Override language detection
zc --markdown --color=never README.md   # Render Markdown without colors
zc first.txt second.txt > combined.txt  # Concatenate exact bytes
zc --help                               # Show all options
```

Images are automatically enabled in recognized Ghostty/Kitty terminals. Rex support is unverified; use `--images=kitty` only with a compatible terminal. No image fallbacks or remote downloads.

Markdown supports a practical subset, not full CommonMark. Use `--plain` for original bytes; raw output doesn't escape terminal controls. Only open trusted Markdown: local image references can read files outside the document directory.

## Build

With **Zig 0.17.1**:

```sh
zig build -Doptimize=ReleaseSafe -j2
./zig-out/bin/zc --help
```

See the [reference](REFERENCE.md) for source setup, options, supported languages, limitations, old-tap migration, and development checks.

MIT licensed. See [third-party notices](THIRD_PARTY.md) for bundled dependencies.
