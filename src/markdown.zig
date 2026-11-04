const std = @import("std");
const terminal = @import("terminal.zig");
const highlight = @import("highlight.zig");
const options = @import("options.zig");

const Inline = struct {
    out: *std.Io.Writer,
    color: bool,
    width: usize,
    column: usize = 0,

    fn styled(self: *Inline, code: []const u8) !void {
        if (self.color) try self.out.writeAll(code);
    }
    fn emit(self: *Inline, text: []const u8) !void {
        var i: usize = 0;
        while (i < text.len) {
            const n = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
            const end = @min(text.len, i + n);
            const cp = std.unicode.utf8Decode(text[i..end]) catch 0xfffd;
            const width = if (cp == '\t') 4 else terminal.cells(cp);
            // Prefer word boundaries, but also bound long unbroken words.
            if (cp == ' ') {
                var word_cells: usize = 0;
                var iter = std.unicode.Utf8View.init(text[end..]) catch unreachable;
                var it = iter.iterator();
                while (it.nextCodepoint()) |next| {
                    if (next == ' ' or next == '\t') break;
                    word_cells += terminal.cells(next);
                }
                if (self.column + 1 + word_cells > self.width and self.column != 0) {
                    try self.out.writeByte('\n');
                    self.column = 0;
                    i = end;
                    continue;
                }
            }
            if (self.column + width > self.width and self.column != 0) {
                try self.out.writeByte('\n');
                self.column = 0;
            }
            if (cp == '\t') try self.out.writeAll("    ") else try terminal.safe(self.out, text[i..end]);
            self.column += width;
            i = end;
        }
    }

    fn render(self: *Inline, text: []const u8, depth: usize) anyerror!void {
        // Bound repeated delimiter searches on pathological single-line input.
        if (depth > 8 or text.len > 16 * 1024) return self.emit(text);
        var i: usize = 0;
        var start: usize = 0;
        while (i < text.len) {
            if (text[i] == '\\' and i + 1 < text.len and std.mem.indexOfScalar(u8, "\\`*_[]()", text[i + 1]) != null) {
                try self.emit(text[start..i]);
                try self.emit(text[i + 1 .. i + 2]);
                i += 2;
                start = i;
                continue;
            }
            if (text[i] == '[') {
                if (std.mem.indexOf(u8, text[i..], "](")) |middle| {
                    const url_start = i + middle + 2;
                    if (std.mem.indexOfScalarPos(u8, text, url_start, ')')) |end| {
                        try self.emit(text[start..i]);
                        try self.styled("\x1b[4;34m");
                        try self.render(text[i + 1 .. i + middle], depth + 1);
                        try self.styled(terminal.reset);
                        // URLs are visible, never OSC hyperlinks or executed controls.
                        try self.emit(" (");
                        try self.emit(text[url_start..end]);
                        try self.emit(")");
                        i = end + 1;
                        start = i;
                        continue;
                    }
                }
            }
            if (text[i] == '*' or text[i] == '_' or text[i] == '`') {
                const marker = text[i];
                const count: usize = if (marker != '`' and i + 1 < text.len and text[i + 1] == marker) 2 else 1;
                const delimiter = text[i .. i + count];
                if (std.mem.indexOf(u8, text[i + count ..], delimiter)) |distance| {
                    const end = i + count + distance;
                    if (distance != 0) {
                        try self.emit(text[start..i]);
                        try self.styled(if (marker == '`') "\x1b[33m" else if (count == 2) "\x1b[1m" else "\x1b[3m");
                        if (marker == '`') try self.emit(text[i + count .. end]) else try self.render(text[i + count .. end], depth + 1);
                        try self.styled(terminal.reset);
                        i = end + count;
                        start = i;
                        continue;
                    }
                }
            }
            i += 1;
        }
        try self.emit(text[start..]);
    }
};

fn lineAt(source: []const u8, pos: usize) struct { text: []const u8, next: usize } {
    const end = std.mem.indexOfScalarPos(u8, source, pos, '\n') orelse source.len;
    return .{ .text = std.mem.trimEnd(u8, source[pos..end], "\r"), .next = @min(end + 1, source.len) };
}

fn fenceLength(line: []const u8) usize {
    if (line.len < 3 or (line[0] != '`' and line[0] != '~')) return 0;
    var count: usize = 1;
    while (count < line.len and line[count] == line[0]) : (count += 1) {}
    return if (count >= 3) count else 0;
}

fn rule(line: []const u8) bool {
    if (line.len == 0 or std.mem.indexOfScalar(u8, "*-_", line[0]) == null) return false;
    var count: usize = 0;
    for (line) |c| {
        if (c == line[0]) count += 1 else if (c != ' ' and c != '\t') return false;
    }
    return count >= 3;
}

pub fn render(a: std.mem.Allocator, io: std.Io, out: *std.Io.Writer, source: []const u8, color: bool, width: usize) !void {
    var pos: usize = 0;
    var paragraph = false;
    var inline_out: Inline = .{ .out = out, .color = color, .width = width };
    while (pos < source.len) {
        const current = lineAt(source, pos);
        pos = current.next;
        const text = std.mem.trim(u8, current.text, " \t");
        const fence = fenceLength(text);
        if (fence > 0) {
            if (paragraph) try out.writeByte('\n');
            paragraph = false;
            const info = std.mem.trim(u8, text[fence..], " \t");
            const word = info[0 .. std.mem.indexOfAny(u8, info, " \t") orelse info.len];
            const lang = options.canonical(word) orelse "text";
            const begin = pos;
            var end = source.len;
            while (pos < source.len) {
                const next = lineAt(source, pos);
                const candidate = std.mem.trim(u8, next.text, " \t");
                const size = fenceLength(candidate);
                if (size >= fence and candidate[0] == text[0] and std.mem.trim(u8, candidate[size..], " \t").len == 0) {
                    end = pos;
                    pos = next.next;
                    break;
                }
                pos = next.next;
            }
            try highlight.render(a, io, out, source[begin..end], lang, color);
            if (end > begin and source[end - 1] != '\n') try out.writeByte('\n');
            inline_out.column = 0;
            continue;
        }
        if (text.len == 0) {
            if (paragraph) try out.writeByte('\n');
            try out.writeByte('\n');
            inline_out.column = 0;
            paragraph = false;
            continue;
        }
        if (rule(text)) {
            if (paragraph) try out.writeByte('\n');
            for (0..width) |_| try out.writeAll("─");
            try out.writeByte('\n');
            inline_out.column = 0;
            paragraph = false;
            continue;
        }
        var heading: usize = 0;
        while (heading < text.len and text[heading] == '#') : (heading += 1) {}
        const is_heading = heading >= 1 and heading <= 6 and heading < text.len and text[heading] == ' ';
        var body = text;
        var prefix: []const u8 = "";
        var block = is_heading;
        if (is_heading) {
            body = std.mem.trimStart(u8, text[heading + 1 ..], " ");
        } else if (text[0] == '>') {
            prefix = "│ ";
            body = std.mem.trimStart(u8, text[1..], " ");
            block = true;
        } else if (text.len >= 2 and std.mem.indexOfScalar(u8, "-*+", text[0]) != null and text[1] == ' ') {
            prefix = "• ";
            body = std.mem.trimStart(u8, text[2..], " ");
            block = true;
        } else {
            var digits: usize = 0;
            while (digits < text.len and std.ascii.isDigit(text[digits])) : (digits += 1) {}
            if (digits > 0 and digits + 1 < text.len and (text[digits] == '.' or text[digits] == ')') and text[digits + 1] == ' ') {
                prefix = text[0 .. digits + 2];
                body = text[digits + 2 ..];
                block = true;
            }
        }
        if (block and paragraph) {
            try out.writeByte('\n');
            inline_out.column = 0;
        } else if (paragraph) try inline_out.emit(" ");
        if (is_heading) try inline_out.styled("\x1b[1;36m");
        try inline_out.emit(prefix);
        try inline_out.render(body, 0);
        if (is_heading) try inline_out.styled(terminal.reset);
        if (block) {
            try out.writeByte('\n');
            inline_out.column = 0;
        }
        paragraph = !block;
    }
    if (paragraph) try out.writeByte('\n');
}

test "Markdown blocks, inline text, links, fences, and safety" {
    var w: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer w.deinit();
    try render(std.testing.allocator, std.testing.io, &w.writer, "# Title\n\nA **bold** and *soft* `code` [link](https://example.com).\n\n- item\n> quote\n\n```zig\nconst x = 42;\n```\n\x1b[2J\n", false, 80);
    const text = w.written();
    try std.testing.expect(std.mem.startsWith(u8, text, "Title\n"));
    try std.testing.expect(std.mem.indexOf(u8, text, "A bold and soft code link (https://example.com).") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "• item\n│ quote") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "const x = 42;") != null);
    try std.testing.expect(std.mem.indexOfScalar(u8, text, 27) == null);
}
