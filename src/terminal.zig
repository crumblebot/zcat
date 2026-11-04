const std = @import("std");
pub const reset = "\x1b[0m";

// Never forward input control sequences in pretty mode, including Unicode C1
// controls and bidi overrides. Plain cat mode deliberately bypasses this.
pub fn safe(out: *std.Io.Writer, text: []const u8) std.Io.Writer.Error!void {
    var i: usize = 0;
    while (i < text.len) {
        const n = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
        const end = @min(text.len, i + n);
        const valid = std.unicode.utf8ValidateSlice(text[i..end]);
        const cp = if (valid)
            std.unicode.utf8Decode(text[i..end]) catch 0xfffd
        else
            0xfffd;
        if ((cp < 32 and cp != '\n' and cp != '\t') or cp == 127 or
            (cp >= 0x80 and cp <= 0x9f) or (cp >= 0x202a and cp <= 0x202e) or
            (cp >= 0x2066 and cp <= 0x2069) or !valid)
        {
            for (text[i..end]) |byte| try out.print("\\x{x:0>2}", .{byte});
        } else try out.writeAll(text[i..end]);
        i = end;
    }
}

pub const SafeStream = struct {
    out: *std.Io.Writer,
    pending: [4]u8 = undefined,
    len: usize = 0,

    pub fn write(self: *SafeStream, bytes: []const u8) std.Io.Writer.Error!void {
        for (bytes) |byte| {
            if (self.len != 0 and byte & 0xc0 != 0x80) try self.finish();
            self.pending[self.len] = byte;
            self.len += 1;
            const expected = std.unicode.utf8ByteSequenceLength(self.pending[0]) catch 1;
            if (self.len >= expected) try self.finish();
        }
    }
    pub fn finish(self: *SafeStream) std.Io.Writer.Error!void {
        try safe(self.out, self.pending[0..self.len]);
        self.len = 0;
    }
};

pub fn validText(text: []const u8) bool {
    if (!std.unicode.utf8ValidateSlice(text)) return false;
    for (text) |byte| if (byte == 0) return false;
    return true;
}

// Approximate terminal cell widths, not grapheme shaping. Emoji sequences and
// ambiguous-width characters depend on the terminal and are documented limits.
pub fn cells(cp: u21) usize {
    if ((cp >= 0x300 and cp <= 0x36f) or cp == 0x200d or (cp >= 0xfe00 and cp <= 0xfe0f)) return 0;
    if ((cp >= 0x1100 and cp <= 0x115f) or (cp >= 0x2e80 and cp <= 0xa4cf) or
        (cp >= 0xac00 and cp <= 0xd7a3) or (cp >= 0xf900 and cp <= 0xfaff) or
        (cp >= 0xfe10 and cp <= 0xfe6f) or (cp >= 0xff01 and cp <= 0xff60) or
        (cp >= 0x1f300 and cp <= 0x1faff) or (cp >= 0x20000 and cp <= 0x3ffff)) return 2;
    return 1;
}

test "streaming sanitizer preserves split UTF-8 and escapes incomplete sequences" {
    var w: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer w.deinit();
    var stream: SafeStream = .{ .out = &w.writer };
    try stream.write("\xe7");
    try stream.write("\x95");
    try stream.write("\x8c\xe2");
    try stream.write("\x1b[2J\xc3");
    try stream.finish();
    try std.testing.expectEqualStrings("界\\xe2\\x1b[2J\\xc3", w.written());
}

test "terminal controls, invalid UTF-8, and Unicode" {
    var w: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer w.deinit();
    try safe(&w.writer, "Hi\x1b[2J\x00\xc2\x9b\xff café �\n");
    try std.testing.expectEqualStrings("Hi\\x1b[2J\\x00\\xc2\\x9b\\xff café �\n", w.written());
    try std.testing.expect(!validText("a\x00"));
    try std.testing.expectEqual(@as(usize, 2), cells('界'));
}
