#!/usr/bin/env python3
"""Native Kitty wire/PTY regression tests; not a terminal visual test."""
import base64
import fcntl
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import termios
import unittest
import zlib

# Share the existing timeout-bounded runner and PTY reader.
sys.path.insert(0, str(Path(__file__).parent))
from integration import BIN, ENV, run, terminal

PACKET = re.compile(rb"\x1b_G([^;]*);([A-Za-z0-9+/=]*)\x1b\\")


def png(width, height, rgba=None):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    data = b"" if rgba is None else b"".join(b"\0" + rgba[y*width*4:(y+1)*width*4] for y in range(height))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(data)) + chunk(b"IEND", b"")


def unpack(output):
    packets = PACKET.findall(output)
    assert packets, output[:200]
    controls = [dict(item.split(b"=", 1) for item in c.split(b",")) for c, _ in packets]
    assert controls[0][b"a"] == b"T"
    assert controls[0][b"t"] == b"d"
    assert controls[0][b"f"] == b"32"
    assert controls[0][b"q"] == b"2"
    assert controls[0][b"C"] == b"1"
    for i, ((_, data), control) in enumerate(zip(packets, controls)):
        assert len(data) <= 4096 and len(data) % 4 == 0
        assert control[b"m"] == (b"0" if i == len(packets)-1 else b"1")
        if i:
            assert set(control) == {b"m"}
    return controls[0], b"".join(base64.b64decode(d, validate=True) for _, d in packets)


class Images(unittest.TestCase):
    def test_exact_rgba_and_chunk_boundaries(self):
        for w, h in [(1, 1), (32, 24), (33, 24), (40, 40)]:
            rgba = bytes((i * 37) % 256 for i in range(w*h*4))
            result = run("--images=kitty", "--color=always", data=png(w, h, rgba))
            self.assertEqual(result.returncode, 0, result.stderr)
            control, decoded = unpack(result.stdout)
            self.assertEqual(decoded, rgba)
            self.assertEqual(int(control[b"s"]), w)
            self.assertEqual(int(control[b"v"]), h)
            self.assertEqual(len(PACKET.findall(result.stdout)), (len(rgba) + 3071)//3072)
            self.assertNotIn(b"\x1b", PACKET.sub(b"", result.stdout))

    def test_file_jpeg_raw_and_protocol_policy(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp, "photo.png")
            source = png(2, 1, b"\xff\0\0\xff" * 2)
            path.write_bytes(source)
            self.assertEqual(run(str(path)).stdout, source)
            self.assertEqual(terminal("--plain", str(path)), source)
            denied = run("--color=always", str(path))
            self.assertEqual(denied.returncode, 1)
            self.assertIn(b"ImageProtocolUnavailable", denied.stderr)
            self.assertNotIn(b"\x1b_G", denied.stdout)
            unpack(terminal(str(path), env={**ENV, "TERM": "xterm-ghostty"}))
            unpack(terminal(str(path), env={**ENV, "TERM": "xterm-kitty"}))
            self.assertEqual(run("--images=never", "--color=always", str(path)).returncode, 1)
            jpg = Path(__file__).parent / "fixtures/red.jpg"
            result = run("--images=kitty", str(jpg))
            self.assertEqual(result.returncode, 0, result.stderr)
            control, decoded = unpack(result.stdout)
            self.assertEqual((int(control[b"s"]), int(control[b"v"])), (2, 1))
            self.assertEqual(len(decoded), 8)
            for i in [0, 4]:
                self.assertGreater(decoded[i], 250)
                self.assertLess(decoded[i+1], 5)
                self.assertLess(decoded[i+2], 5)
                self.assertEqual(decoded[i+3], 255)

    def test_markdown_local_paths_alt_and_no_network(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a b.png").write_bytes(png(1, 1, b"\xff\0\0\xff"))
            doc = root / "doc.md"
            doc.write_text("before ![evil\x1b[2J](a%20b.png) after\n![space](<a b.png>)\n")
            result = run("-m", "--images=kitty", str(doc))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(PACKET.findall(result.stdout)), 2)
            self.assertIn(b"evil\\x1b[2J", result.stdout)
            self.assertIn(b"after", result.stdout)
            self.assertNotIn(b"\x1b", PACKET.sub(b"", result.stdout))
            numbered = run("-m", "-n", "--images=kitty", str(doc))
            for packet in PACKET.finditer(numbered.stdout):
                _, decoded = unpack(packet.group())  # Numbering never touches payloads.
                self.assertEqual(decoded, b"\xff\0\0\xff")
            self.assertEqual(run(str(doc)).stdout, doc.read_bytes())
            missing = run("-m", "--images=kitty", data=b"![missing](absent.png)\n")
            self.assertEqual(missing.returncode, 1)
            self.assertIn(b"FileNotFound", missing.stderr)
            for url in [b"https://example.invalid/a.png", b"file:///tmp/a", b"//host/a", b"https%3a//host/a", b"a%00.png", b"a%1b.png", b"a%XX.png"]:
                result = run("-m", "--images=kitty", data=b"![alt](" + url + b")\n")
                self.assertNotIn(b"\x1b_G", result.stdout)
                self.assertIn(b"local images only", result.stdout)
            literal = b"```md\n![no](a%20b.png)\n```\n"
            self.assertNotIn(b"\x1b_G", run("-m", "--images=kitty", data=literal).stdout)

    def test_corrupt_oversized_and_output_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp, "bad.png")
            for data in [b"bad", png(1, 1), png(8193, 1), png(8192, 8192), b"x"*(16*1024*1024+1)]:
                p.write_bytes(data)
                result = run("--images=kitty", str(p))
                self.assertEqual(result.returncode, 1)
                self.assertTrue(result.stderr.startswith(b"zc: "))
                self.assertNotIn(b"\x1b_G", result.stdout)
            p.write_bytes(png(1, 1, b"\xff"*4))
            if Path("/dev/full").exists():
                with open("/dev/full", "wb") as out:
                    result = subprocess.run([BIN, "--images=kitty", str(p)], stdout=out, stderr=subprocess.PIPE, timeout=5)
                self.assertNotEqual(result.returncode, 0)
            result = run("--images=kitty", str(p), str(p))
            self.assertEqual(len(PACKET.findall(result.stdout)), 2)
            unsupported = Path(tmp, "unsupported.webp")
            unsupported.write_bytes(b"RIFFinvalidWEBP")
            result = run("--images=kitty", str(unsupported), str(p))
            self.assertEqual(result.returncode, 1)
            self.assertIn(b"UnsupportedImageFormat", result.stderr)
            self.assertEqual(len(PACKET.findall(result.stdout)), 1)
            evil = str(Path(tmp, "missing\x1b[2J.png"))
            result = run("--images=kitty", evil)
            self.assertIn(b"\\x1b", result.stderr)
            self.assertNotIn(b"\x1b", result.stderr)
            directory = Path(tmp, "directory.png")
            directory.mkdir()
            self.assertEqual(run("--images=kitty", str(directory)).returncode, 1)

    def test_terminal_sizing_without_input_queries(self):
        # stdin is a pipe. The program must never read a terminal reply.
        import pty
        master, slave = pty.openpty()
        try:
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 6, 10, 100, 120))
            data = png(400, 200, b"\xff" * (400*200*4))
            proc = subprocess.Popen([BIN, "--images=kitty", "--color=always"], stdin=subprocess.PIPE, stdout=slave, stderr=subprocess.PIPE, env=ENV)
            os.close(slave)
            slave = None
            proc.stdin.write(data)
            proc.stdin.close()
            import select
            output = b""
            while select.select([master], [], [], 5)[0]:
                try:
                    part = os.read(master, 65536)
                except OSError:
                    break
                if not part:
                    break
                output += part
            self.assertEqual(proc.wait(timeout=5), 0, proc.stderr.read())
            proc.stderr.close()
            control, rgba = unpack(output)
            self.assertLessEqual(int(control[b"c"]), 10)
            self.assertLessEqual(int(control[b"r"]), 5)
            self.assertEqual((int(control[b"s"]), int(control[b"v"])), (100, 50))
            self.assertEqual(len(rgba), 100*50*4)
        finally:
            os.close(master)
            if slave is not None:
                os.close(slave)


if __name__ == "__main__":
    unittest.main(verbosity=2)
