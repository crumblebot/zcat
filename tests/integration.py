#!/usr/bin/env python3
"""Black-box CLI checks. Uses only Python's standard library on Unix."""
import errno
import os
from pathlib import Path
import pty
import re
import select
import subprocess
import sys
import tempfile
import unittest

BIN = str(Path(sys.argv.pop(1)).resolve())
ENV = {**os.environ, "TERM": "xterm-256color"}
ENV.pop("NO_COLOR", None)
ANSI = re.compile(rb"\x1b\[[0-9;]*m")


def run(*args, data=b"", **kwargs):
    return subprocess.run([BIN, *args], input=data, capture_output=True,
                          env=kwargs.pop("env", ENV), timeout=30, **kwargs)


def terminal(*args, data=b"", env=ENV):
    master, slave = pty.openpty()
    try:
        proc = subprocess.Popen([BIN, *args], stdin=subprocess.PIPE, stdout=slave,
                                stderr=subprocess.PIPE, env=env)
        os.close(slave)
        slave = None
        proc.stdin.write(data)
        proc.stdin.close()
        result = bytearray()
        while True:
            if not select.select([master], [], [], 30)[0]:
                proc.kill()
                raise AssertionError("PTY output timed out")
            try:
                chunk = os.read(master, 65536)
            except OSError as exc:
                if exc.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            result.extend(chunk)
        assert proc.wait(timeout=30) == 0, proc.stderr.read()
        proc.stderr.close()
        return bytes(result).replace(b"\r\n", b"\n")
    finally:
        os.close(master)
        if slave is not None:
            os.close(slave)


class Cli(unittest.TestCase):
    def test_help_version_errors(self):
        self.assertIn(b"Usage: zc [OPTIONS] [FILE ...]", run("--help").stdout)
        self.assertEqual(run("--version").stdout, b"zc 0.2.0\n")
        self.assertIn(b"typescript", run("--list-languages").stdout)
        for args in [("--bogus",), ("--color=bogus",), ("-l",),
                     ("-l", "unknown"), ("--width", "19"),
                     ("--plain", "-m"), ("--plain", "-n")]:
            result = run(*args)
            self.assertEqual(result.returncode, 2, args)
            self.assertTrue(result.stderr.startswith(b"zc: "), result.stderr)
        missing = run("/nonexistent-zc-input")
        self.assertEqual(missing.returncode, 1)
        self.assertTrue(missing.stderr.startswith(b"zc: "), missing.stderr)

    def test_markdown_table_regression(self):
        source = b"| Path | Contents |\n| --- | --- |\n| apps/server/src/ | Server code |\n| apps/web/ | Web client |\n"
        result = run("-m", "--color=never", "--width", "60", data=source)
        self.assertEqual(result.returncode, 0)
        lines = result.stdout.decode().splitlines()
        self.assertTrue(any("Path" in line and "Contents" in line and "│" in line for line in lines), lines)
        self.assertTrue(any("apps/server/src/" in line and "Server code" in line for line in lines), lines)
        self.assertNotIn("---", result.stdout.decode())
        self.assertTrue(all(len(line) <= 60 for line in lines), lines)

    def test_table_alignment_and_inline_cells(self):
        source = b"Left | Middle | Right\n:--- | :---: | ---:\n**a** | `b` | [c](url)\nx\\|y | `p|q` | 12\nempty | |\nshort | row\nextra | cells | kept | ignored\n"
        plain = run("-m", "--color=never", "--width", "60", data=source).stdout
        colored = run("-m", "--color=always", "--width", "60", data=source).stdout
        self.assertIn(b"\x1b[", colored)
        self.assertEqual(ANSI.sub(b"", colored), plain)
        self.assertNotIn(b"**", plain)
        self.assertIn(b"x|y", plain)
        self.assertIn(b"p|q", plain)
        self.assertIn(b"c (url)", plain)
        self.assertNotIn(b"ignored", plain)
        lines = plain.decode().splitlines()
        separators = [tuple(i for i, ch in enumerate(line) if ch == "│")
                      for line in lines if line.startswith("│") and "x|y" not in line and "p|q" not in line]
        self.assertTrue(all(pos == separators[0] for pos in separators))
        cells = lines[2].split("│")[1:-1]
        self.assertTrue(cells[0].startswith(" a"), cells)
        self.assertGreaterEqual(len(cells[1]) - len(cells[1].lstrip()), 2)
        self.assertTrue(cells[2].endswith("c (url) "), cells)

    def test_table_wrapping_and_stacked_layout(self):
        import unicodedata
        def cells(line):
            return sum(0 if unicodedata.combining(ch) else
                       2 if unicodedata.east_asian_width(ch) in "WF" else 1 for ch in line)
        source = ("| Path | Contents |\n| --- | --- |\n" +
                  "".join(f"| {path} | **Code** with café 界 and averylongunbrokenword |\n" for path in
                          ["apps/server/src/", "apps/server/drizzle/", "apps/server/skills/",
                           "apps/server/workspace-image/", "apps/web/", "apps/docs/", "apps/site/", "openapi/", "GLOSSARY.md"]) +
                  "| unsafe | \x1b[2J and \u202eevil |\n").encode()
        for width in [20, 30, 60, 80, 240]:
            plain = run("-m", "--color=never", "--width", str(width), data=source)
            color = run("-m", "--color=always", "--width", str(width), data=source)
            self.assertEqual(plain.returncode, 0, plain.stderr)
            self.assertEqual(ANSI.sub(b"", color.stdout), plain.stdout)
            self.assertTrue(all(cells(line) <= width for line in plain.stdout.decode().splitlines()), plain.stdout)
            self.assertNotIn(b"\x1b", ANSI.sub(b"", color.stdout))
            self.assertNotIn("\u202e".encode(), plain.stdout)
        source = b"one | two | three | four\n--- | --- | --- | ---\nfirst | second | third | fourth\n"
        narrow = run("-m", "--width", "20", "--color=never", data=source).stdout
        self.assertEqual(narrow, b"one\nfirst\ntwo\nsecond\nthree\nthird\nfour\nfourth\n\n")
        self.assertIn("│".encode(), terminal("-m", "--width", "80", data=source))

    def test_table_boundaries_and_non_tables(self):
        table = b"A | B\n--- | ---\nx | y\n"
        for suffix, expected in [(b"paragraph after\n", b"paragraph after\n"),
                                 (b"# Heading | pipe\n", b"Heading | pipe\n"),
                                 (b"```text | info\na | b\n```\n", b"a | b\n"),
                                 (b"- list | item\n", "• list | item\n".encode())]:
            result = run("-m", "--color=never", data=b"before\n" + table + suffix).stdout
            self.assertTrue(result.startswith(b"before\n"), result)
            self.assertTrue(result.endswith(expected), result)
        for source in [b"a | b\nnot a delimiter\n", b"a | b\n-- | ---\n", b"a | b\n--- | --- | ---\n",
                       b"a \\| b\n--- | ---\n", b"`a | b`\n--- | ---\n"]:
            self.assertNotIn("│".encode(), run("-m", data=source).stdout)
        # Too many columns or oversized rows remain ordinary text; parsing stays bounded.
        for source in [(b"x | " * 40 + b"x\n") * 2,
                       b"a | b\n--- | ---\n" + b"x" * 17000 + b" | y\n",
                       table + b"x | y\n" * 10000]:
            result = run("-m", "--width", "20", data=source)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_exact_pipe_bytes(self):
        for data in [b"", b"no newline", bytes(range(256)) * 1000,
                     b"# heading\n**bold**\n\x1b[2J\x00\xff"]:
            self.assertEqual(run(data=data).stdout, data)
            self.assertEqual(run("--color=never", data=data).stdout, data)
            self.assertEqual(run("--plain", "--color=always", data=data).stdout, data)

    def test_multiple_inputs_and_dash_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            (path / "a").write_bytes(b"a")
            (path / "b").write_bytes(b"b\x00\xff")
            (path / "-dash").write_bytes(b"dash")
            result = run("a", "-", "b", "-", data=b"stdin", cwd=tmp)
            self.assertEqual(result.stdout, b"astdinb\x00\xff")
            self.assertEqual(result.returncode, 0)
            self.assertEqual(run("--", "-dash", cwd=tmp).stdout, b"dash")
            result = run("missing", "a", "also-missing", "b", cwd=tmp)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, b"ab\x00\xff")
            self.assertIn(b"missing", result.stderr)
            self.assertEqual(run(tmp).returncode, 1)  # directory, not file

    def test_unreadable_file_continues(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            path.chmod(0o755)
            denied = path / "denied"
            denied.write_bytes(b"secret")
            denied.chmod(0)
            allowed = path / "allowed"
            allowed.write_bytes(b"readable")
            allowed.chmod(0o644)
            kwargs = {}
            if os.getuid() == 0:
                import pwd
                uid = pwd.getpwnam("nobody").pw_uid
                kwargs["preexec_fn"] = lambda: os.setuid(uid)
            result = run(str(denied), str(allowed), **kwargs)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, b"readable")
            self.assertIn(b"AccessDenied", result.stderr)

    def test_numbering(self):
        self.assertEqual(run("-n", data=b"one\ntwo").stdout,
                         b"     1  one\n     2  two")
        self.assertEqual(run("-n", data=b"").stdout, b"")
        with tempfile.TemporaryDirectory() as tmp:
            for name, data in [("a", b"one"), ("b", b"two\nthree\n")]:
                Path(tmp, name).write_bytes(data)
            self.assertEqual(run("-n", "a", "b", cwd=tmp).stdout,
                             b"     1  onetwo\n     2  three\n")

    def test_highlight_and_detection(self):
        samples = {
            "zig": b"pub fn main() void { const x = 42; }\n",
            "js": b"const x = 'hello';\n",
            "ts": b"const x: number = 42;\n",
            "tsx": b"const x = <div>hello</div>;\n",
            "py": b"def hello():\n    return 'world'\n",
            "json": b'{"key": 42, "yes": true}\n',
            "sh": b'#!/bin/bash\necho "hello"\n',
            "c": b"int main(void) { return 42; }\n",
            "rs": b"fn main() { let x = 42; }\n",
        }
        with tempfile.TemporaryDirectory() as tmp:
            for ext, source in samples.items():
                result = run("--color=always", "--no-header", "--no-line-numbers", "-l", ext, data=source)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(b"\x1b[", result.stdout, ext)
                self.assertEqual(ANSI.sub(b"", result.stdout), source, ext)
                name = str(Path(tmp, "example." + ext))
                Path(name).write_bytes(source)
                self.assertEqual(run(name).stdout, source)
                self.assertIn(b"\x1b[", terminal(name))
        source = b"#!/usr/bin/env python3\nprint('hi')\n"
        self.assertIn(b"\x1b[", run("--color=always", data=source).stdout)
        self.assertNotIn(b"\x1b", run("--color=always", "-l", "text", data=b"42").stdout)

    def test_code_decorations(self):
        source = b"const x = 42;\nconst y = 0;"
        text = ANSI.sub(b"", terminal("-l", "zig", data=source))
        self.assertIn(b"stdin [zig]", text)
        self.assertIn(b"     1  const x", text)
        self.assertIn(b"     2  const y", text)
        self.assertEqual(ANSI.sub(b"", terminal("--no-header", "--no-line-numbers", "-l", "zig", data=source)), source)
        self.assertNotIn(b"stdin", terminal("--no-header", "-l", "zig", data=source))
        self.assertNotIn(b"     1", terminal("--no-line-numbers", "-l", "zig", data=source))
        self.assertEqual(run("-l", "zig", data=source).stdout, source)
        self.assertEqual(run("-n", "--no-line-numbers").returncode, 2)
        with tempfile.TemporaryDirectory() as tmp:
            names = [str(Path(tmp, "a.zig")), str(Path(tmp, "b\x1b[2J.zig"))]
            for name in names:
                Path(name).write_bytes(source)
            text = ANSI.sub(b"", terminal(*names))
            self.assertEqual(text.count(b"     1  const x"), 2)
            self.assertIn(b"b\\x1b[2J.zig", text)
            self.assertNotIn(b"\x1b", text)
            self.assertEqual(run(*names).stdout, source * 2)
            text = ANSI.sub(b"", terminal("-n", *names))
            self.assertIn(b"     3  const x", text)

    def test_terminal_policies(self):
        data = b"const x = 42;\n"
        self.assertIn(b"\x1b[", terminal("-l", "zig", data=data))
        self.assertEqual(terminal("--plain", "-l", "zig", data=data), data)
        for flags, env in [(("--color=never",), ENV),
                           ((), {**ENV, "NO_COLOR": "1"}),
                           ((), {**ENV, "TERM": "dumb"})]:
            self.assertNotIn(b"\x1b", terminal(*flags, "-l", "zig", data=data, env=env))
        self.assertIn(b"\x1b[", terminal("--color=always", "-l", "zig", data=data,
                                         env={**ENV, "NO_COLOR": "1"}))

    def test_markdown_subset_and_fences(self):
        source = Path(__file__).with_name("fixtures").joinpath("sample.md").read_bytes()
        rendered = run("-m", "--color=never", data=source)
        self.assertEqual(rendered.returncode, 0, rendered.stderr)
        for text in [b"A small example", b"bold", b"emphasis", b"inline code",
                     "• first item".encode(), b"1. ordered item", "│ quoted text".encode(),
                     b"site (https://example.com)", b"const answer = 42;"]:
            self.assertIn(text, rendered.stdout)
        self.assertNotIn(b"\x1b", rendered.stdout)
        self.assertNotIn(b"```", rendered.stdout)
        self.assertNotIn(b"**", rendered.stdout)
        highlighted = run("-m", "--color=always", data=b"```zig\nconst x = 42;\n```\n").stdout
        self.assertIn(b"\x1b[", highlighted)
        self.assertEqual(ANSI.sub(b"", highlighted), b"const x = 42;\n")
        self.assertEqual(run("-m", data=b"~~~unknown\nhello\n~~~~\n").stdout, b"hello\n")
        self.assertEqual(run("-m", data=b"```\nunclosed").stdout, b"unclosed\n")
        with tempfile.TemporaryDirectory() as tmp:
            name = Path(tmp, "example.md")
            name.write_bytes(source)
            self.assertEqual(run(str(name)).stdout, source)
            self.assertIn(b"A small example", terminal("--color=never", str(name)))
            self.assertNotIn(b"# A small", terminal("--color=never", str(name)))

    def test_width_and_unicode(self):
        result = run("-m", "--width", "20", "--color=never",
                     data=("# café\n\n" + "word " * 30 + "\n---\n").encode()).stdout.decode()
        self.assertIn("café", result)
        self.assertTrue(all(len(line) <= 20 for line in result.splitlines()))
        self.assertIn("─" * 20, result)
        env = {**ENV, "COLUMNS": "24"}
        self.assertIn(("─" * 24).encode(), run("-m", data=b"---\n", env=env).stdout)

    def test_control_and_binary_safety(self):
        source = b"# hello\x1b[2J\n\x1b]52;c;evil\x07\r\x00\xff\xc2\x9b"
        for args in [("-m", "--color=never"), ("--color=always", "-l", "zig")]:
            result = run(*args, data=source)
            self.assertEqual(result.returncode, 0, result.stderr)
            clean = ANSI.sub(b"", result.stdout)
            self.assertNotIn(b"\x1b", clean)
            self.assertNotIn(b"\x00", clean)
            self.assertNotIn(b"\x07", clean)
            self.assertIn(b"\\x1b", clean)
        self.assertNotIn(b"\x1b", terminal("--color=never", data=source))
        self.assertNotIn(b"\x1b", run("-m", data="hello\u202eevil".encode()).stdout)
        for args, data in [(("--color=always", "-l", "js"), b'const x = "\x1b]52;c;evil\x07";\n'),
                           (("-m", "--color=always"), b'# hi\x1b[2J\n```zig\n// \x1b]52;c;x\x07\n```\n')]:
            result = run(*args, data=data)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(b"\\x1b", result.stdout)
            self.assertNotIn(b"\x1b", ANSI.sub(b"", result.stdout))

    def test_large_stream_and_fallback(self):
        source = bytes(range(256)) * 40000  # > pretty cap; ordinary cat stays exact
        self.assertEqual(run(data=source).stdout, source)
        # A Unicode code point crosses the streaming chunk boundary.
        source = b"a" * (8 * 1024 * 1024 + 65535) + "界".encode() + b"\x1b[2J\n"
        result = run("--color=always", "-l", "zig", data=source)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, source.replace(b"\x1b", b"\\x1b"))

    @unittest.skipUnless(Path("/dev/full").exists(), "Linux /dev/full required")
    def test_output_errors(self):
        with open("/dev/full", "wb") as out:
            result = subprocess.run([BIN], input=b"hello", stdout=out,
                                    stderr=subprocess.PIPE, timeout=30)
        self.assertNotEqual(result.returncode, 0)

    def test_closed_pipe(self):
        read, write = os.pipe()
        os.close(read)
        try:
            proc = subprocess.run([BIN], input=b"hello", stdout=write,
                                  stderr=subprocess.PIPE, timeout=30)
            self.assertNotEqual(proc.returncode, 0)
        finally:
            os.close(write)


if __name__ == "__main__":
    unittest.main(verbosity=2)
