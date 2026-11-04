# Third-party notices

zcat's own code uses the MIT license in `LICENSE`. Dependency licenses remain in effect for their respective components. Unmodified license texts, including copyright notices, are retained in `licenses/`. Distribute that directory and this notice with binaries.

## Runtime and bindings

- [ztreesitter](https://github.com/pedronaugusto/ztreesitter/tree/6c1d940007c77f11d8f4775ca2fc558b404b84d9), commit `6c1d940007c77f11d8f4775ca2fc558b404b84d9`: MIT. See `licenses/ztreesitter-MIT.txt`.
- Tree-sitter's runtime is vendored by that ztreesitter revision in `libs/tree-sitter/`: MIT. See `licenses/tree-sitter-MIT.txt`. The exact runtime source and provenance are available in [ztreesitter's upstream record](https://github.com/pedronaugusto/ztreesitter/blob/6c1d940007c77f11d8f4775ca2fc558b404b84d9/UPSTREAM.md).

## Grammar sources

All linked grammars use MIT licenses. License files are copied from the exact grammar packages fetched by the pinned ztreesitter manifest. TSX and TypeScript share a repository, revision, and license.

| Grammar | Source repository | Source commit | License file |
| --- | --- | --- | --- |
| Zig | [tree-sitter-zig](https://github.com/tree-sitter-grammars/tree-sitter-zig) | `6479aa13f32f701c383083d8b28360ebd682fb7d` | `licenses/zig-MIT.txt` |
| JavaScript | [tree-sitter-javascript](https://github.com/tree-sitter/tree-sitter-javascript) | `58404d8cf191d69f2674a8fd507bd5776f46cb11` | `licenses/javascript-MIT.txt` |
| TypeScript and TSX | [tree-sitter-typescript](https://github.com/tree-sitter/tree-sitter-typescript) | `75b3874edb2dc714fb1fd77a32013d0f8699989f` | `licenses/typescript-MIT.txt` |
| Python | [tree-sitter-python](https://github.com/tree-sitter/tree-sitter-python) | `293fdc02038ee2bf0e2e206711b69c90ac0d413f` | `licenses/python-MIT.txt` |
| JSON | [tree-sitter-json](https://github.com/tree-sitter/tree-sitter-json) | `254c42a6476413b776221e03982ac8ae159eeb72` | `licenses/json-MIT.txt` |
| Bash | [tree-sitter-bash](https://github.com/tree-sitter/tree-sitter-bash) | `a06c2e4415e9bc0346c6b86d401879ffb44058f7` | `licenses/bash-MIT.txt` |
| C | [tree-sitter-c](https://github.com/tree-sitter/tree-sitter-c) | `b780e47fc780ddc8da13afa35a3f4ed5c157823d` | `licenses/c-MIT.txt` |
| Rust | [tree-sitter-rust](https://github.com/tree-sitter/tree-sitter-rust) | `77a3747266f4d621d0757825e6b11edcbf991ca5` | `licenses/rust-MIT.txt` |

The dependency's [grammar catalogue](https://github.com/pedronaugusto/ztreesitter/blob/6c1d940007c77f11d8f4775ca2fc558b404b84d9/grammars/catalogue.zig) records source revisions, mirror commits, query provenance, and licenses. The corresponding `build.zig.zon` pins archive URLs and package hashes.

## Queries

Highlight queries, including inherited ECMAScript and JSX queries, come from [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter/tree/910fdf6f49e9dee7e7257c7d11a76b040fdfb9de), commit `910fdf6f49e9dee7e7257c7d11a76b040fdfb9de`. They use Apache-2.0. See `licenses/nvim-treesitter-Apache-2.0.txt`. The source repository has no separate NOTICE file. ztreesitter resolves query inheritance; zcat doesn't modify those query sources.

The grammar module also makes tag queries available, although zcat doesn't execute tags. Some tag queries originate in [Helix](https://github.com/helix-editor/helix/tree/ba40e547426b0f9896c8bdc699a4ab11f2b37dbc), commit `ba40e547426b0f9896c8bdc699a4ab11f2b37dbc`, under MPL-2.0. The unmodified covered source files are available in that commit's `runtime/queries/` directory. See `licenses/helix-MPL-2.0.txt`. This source link provides access to those files when distributing an executable that includes them.

No GPL- or LGPL-licensed grammars are selected. This notice doesn't relicense any dependency.
