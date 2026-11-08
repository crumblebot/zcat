const std = @import("std");
const terminal = @import("terminal.zig");
const highlight = @import("highlight.zig");
const options = @import("options.zig");
const image = @import("image.zig");
const Images = struct { a: std.mem.Allocator, io: std.Io, context: image.Context };

const Inline = struct {
    out: *std.Io.Writer,
    color: bool,
    width: usize,
    column: usize = 0,
    images: ?Images = null,

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
            if (text[i] == '\\' and i + 1 < text.len and std.mem.indexOfScalar(u8, "\\`*_[]()|!", text[i + 1]) != null) {
                try self.emit(text[start..i]);
                try self.emit(text[i + 1 .. i + 2]);
                i += 2;
                start = i;
                continue;
            }
            if (self.images != null and text[i] == '!' and i + 1 < text.len and text[i + 1] == '[') {
                if (std.mem.indexOf(u8, text[i + 2 ..], "](")) |middle| {
                    const alt_end = i + 2 + middle;
                    const url_start = alt_end + 2;
                    if (std.mem.indexOfScalarPos(u8, text, url_start, ')')) |end| {
                        try self.emit(text[start..i]);
                        if (self.column != 0) try self.out.writeByte('\n');
                        self.column = 0;
                        try self.emit("[image: ");
                        try self.emit(text[i + 2 .. alt_end]);
                        try self.emit("]");
                        try self.out.writeByte('\n');
                        self.column = 0;
                        const imgs = self.images;
                        if (imgs) |ctx| {
                            var url = std.mem.trim(u8, text[url_start..end], " ");
                            if (url.len >= 2 and url[0] == '<' and url[url.len - 1] == '>') url = url[1 .. url.len - 1];
                            const path = image.localPath(ctx.a, ctx.context.document, url) catch |err| {
                                try self.out.print("[{s}; local images only]\n", .{@errorName(err)});
                                i = end + 1;
                                start = i;
                                continue;
                            };
                            defer ctx.a.free(path);
                            if (!ctx.context.enabled) return error.ImageProtocolUnavailable;
                            try image.file(ctx.a, ctx.io, ctx.context.graphics_out orelse self.out, path, ctx.context.geometry);
                        } else return error.ImageProtocolUnavailable;
                        i = end + 1;
                        start = i;
                        continue;
                    }
                }
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

const max_columns = 32;
const Row = struct {
    cells: [max_columns][]const u8 = @splat(""),
    len: usize = 0,
};
const Alignment = enum { left, center, right };

// Split only unescaped pipes outside matched backtick spans. Bound the column
// count so malformed or adversarial input cannot allocate unbounded row state.
fn tableRow(raw: []const u8) ?Row {
    const text = std.mem.trim(u8, raw, " \t");
    if (text.len > 16 * 1024 or fenceLength(text) > 0 or std.mem.startsWith(u8, text, ">") or
        (text.len >= 2 and std.mem.indexOfScalar(u8, "-*+", text[0]) != null and text[1] == ' ')) return null;
    var heading: usize = 0;
    while (heading < text.len and text[heading] == '#') : (heading += 1) {}
    if (heading >= 1 and heading <= 6 and heading < text.len and text[heading] == ' ') return null;
    var digits: usize = 0;
    while (digits < text.len and std.ascii.isDigit(text[digits])) : (digits += 1) {}
    if (digits > 0 and digits + 1 < text.len and (text[digits] == '.' or text[digits] == ')') and text[digits + 1] == ' ') return null;
    var result: Row = .{};
    var start: usize = if (std.mem.startsWith(u8, text, "|")) 1 else 0;
    var i = start;
    var pipes: usize = start;
    while (i < text.len) {
        if (text[i] == '\\' and i + 1 < text.len) {
            i += 2;
            continue;
        }
        if (text[i] == '`') {
            var end = i + 1;
            while (end < text.len and text[end] == '`') : (end += 1) {}
            if (std.mem.indexOf(u8, text[end..], text[i..end])) |distance| {
                i = end + distance + (end - i);
                continue;
            }
            i = end;
            continue;
        }
        if (text[i] == '|') {
            if (result.len == max_columns) return null;
            result.cells[result.len] = std.mem.trim(u8, text[start..i], " \t");
            result.len += 1;
            pipes += 1;
            start = i + 1;
        }
        i += 1;
    }
    if (start < text.len or !std.mem.endsWith(u8, text, "|")) {
        if (result.len == max_columns) return null;
        result.cells[result.len] = std.mem.trim(u8, text[start..], " \t");
        result.len += 1;
    }
    return if (pipes > 0 and result.len > 0) result else null;
}

fn tableAlignment(row: Row, count: usize) ?[max_columns]Alignment {
    if (row.len != count) return null;
    var result: [max_columns]Alignment = @splat(.left);
    for (row.cells[0..count], 0..) |cell, i| {
        var marker = cell;
        const left = std.mem.startsWith(u8, marker, ":");
        const right = std.mem.endsWith(u8, marker, ":");
        if (left) marker = marker[1..];
        if (right and marker.len > 0) marker = marker[0 .. marker.len - 1];
        if (marker.len < 3) return null;
        for (marker) |c| if (c != '-') return null;
        result[i] = if (left and right) .center else if (right) .right else .left;
    }
    return result;
}

// Input here is already sanitized inline output. Only our SGR sequences remain.
fn visibleWidth(text: []const u8) usize {
    var i: usize = 0;
    var width: usize = 0;
    while (i < text.len) {
        if (text[i] == 27) {
            i = (std.mem.indexOfScalarPos(u8, text, i, 'm') orelse unreachable) + 1;
            continue;
        }
        const n = std.unicode.utf8ByteSequenceLength(text[i]) catch unreachable;
        width += terminal.cells(std.unicode.utf8Decode(text[i..][0..n]) catch unreachable);
        i += n;
    }
    return width;
}

fn cellText(a: std.mem.Allocator, text: []const u8, color: bool, width: usize) !std.Io.Writer.Allocating {
    // Sanitize before wrapping: escaped controls must count as their visible
    // representation, not as one invisible input code point.
    var safe: std.Io.Writer.Allocating = .init(a);
    defer safe.deinit();
    try terminal.safe(&safe.writer, text);
    var result: std.Io.Writer.Allocating = .init(a);
    errdefer result.deinit();
    var renderer: Inline = .{ .out = &result.writer, .color = color, .width = width };
    try renderer.render(safe.written(), 0);
    return result;
}

fn spaces(out: *std.Io.Writer, n: usize) !void {
    try out.splatByteAll(' ', n);
}

fn tableBorder(out: *std.Io.Writer, widths: []const usize) !void {
    try out.writeAll("├");
    for (widths, 0..) |width, i| {
        for (0..width + 2) |_| try out.writeAll("─");
        try out.writeAll(if (i + 1 == widths.len) "┤\n" else "┼");
    }
}

fn renderTableRow(a: std.mem.Allocator, out: *std.Io.Writer, row: Row, header: Row, widths: []const usize, alignment: []const Alignment, color: bool, stacked: bool, width: usize) !void {
    if (stacked) {
        for (widths, 0..) |_, i| {
            var label = try cellText(a, header.cells[i], color, width);
            defer label.deinit();
            try out.writeAll(label.written());
            if (color) try out.writeAll(terminal.reset);
            try out.writeByte('\n');
            var value = try cellText(a, row.cells[i], color, width);
            defer value.deinit();
            try out.writeAll(value.written());
            if (color) try out.writeAll(terminal.reset);
            try out.writeByte('\n');
        }
        try out.writeByte('\n');
        return;
    }
    var cells: [max_columns]std.Io.Writer.Allocating = undefined;
    var initialized: usize = 0;
    defer for (cells[0..initialized]) |*cell| cell.deinit();
    for (widths, 0..) |w, i| {
        cells[i] = try cellText(a, row.cells[i], color, w);
        initialized += 1;
    }
    var positions: [max_columns]usize = @splat(0);
    var styles: [max_columns][]const u8 = @splat("");
    while (true) {
        var more = false;
        try out.writeAll("│");
        for (widths, 0..) |w, i| {
            const text = cells[i].written();
            const begin = positions[i];
            const end = std.mem.indexOfScalarPos(u8, text, begin, '\n') orelse text.len;
            const fragment = text[begin..end];
            const padding = w -| visibleWidth(fragment);
            const left = switch (alignment[i]) {
                .left => 0,
                .center => padding / 2,
                .right => padding,
            };
            try spaces(out, left + 1);
            try out.writeAll(styles[i]);
            try out.writeAll(fragment);
            if (color) try out.writeAll(terminal.reset);
            try spaces(out, padding - left + 1);
            try out.writeAll("│");
            // Preserve active styling across wrapped fragments, without coloring
            // padding or other cells. Inline's current model uses the last SGR.
            var at: usize = 0;
            while (std.mem.indexOfScalarPos(u8, fragment, at, 27)) |escape| {
                const finish = (std.mem.indexOfScalarPos(u8, fragment, escape, 'm') orelse unreachable) + 1;
                styles[i] = fragment[escape..finish];
                at = finish;
            }
            positions[i] = if (end < text.len) end + 1 else text.len;
            more = more or positions[i] < text.len;
        }
        try out.writeByte('\n');
        if (!more) break;
    }
}

fn renderTable(a: std.mem.Allocator, out: *std.Io.Writer, source: []const u8, header: Row, alignment: [max_columns]Alignment, body_start: usize, color: bool, width: usize) !usize {
    var wanted: [max_columns]usize = @splat(3);
    var end = body_start;
    // Two passes, but only one row of rendered cells is retained in memory.
    var row = header;
    while (true) {
        for (wanted[0..header.len], 0..) |*w, i| {
            var text = try cellText(a, row.cells[i], false, std.math.maxInt(usize) / 2);
            defer text.deinit();
            w.* = @max(w.*, @min(width, visibleWidth(text.written())));
        }
        if (end == source.len) break;
        const next = lineAt(source, end);
        row = tableRow(next.text) orelse break;
        end = next.next;
    }
    var widths: [max_columns]usize = @splat(3);
    const stacked = header.len * 6 + 1 > width;
    if (!stacked) {
        var budget = width - (header.len * 6 + 1);
        while (budget > 0) {
            var grew = false;
            for (widths[0..header.len], wanted[0..header.len]) |*w, want| {
                if (budget == 0) break;
                if (w.* < want) {
                    w.* += 1;
                    budget -= 1;
                    grew = true;
                }
            }
            if (!grew) break;
        }
        try renderTableRow(a, out, header, header, widths[0..header.len], alignment[0..header.len], color, false, width);
        try tableBorder(out, widths[0..header.len]);
    } else if (end == body_start) {
        // Header-only tables still retain their labels on narrow terminals.
        for (header.cells[0..header.len]) |label| {
            var text = try cellText(a, label, color, width);
            defer text.deinit();
            try out.writeAll(text.written());
            if (color) try out.writeAll(terminal.reset);
            try out.writeByte('\n');
        }
    }
    var pos = body_start;
    while (pos < end) {
        const next = lineAt(source, pos);
        try renderTableRow(a, out, tableRow(next.text).?, header, widths[0..header.len], alignment[0..header.len], color, stacked, width);
        pos = next.next;
    }
    return end;
}

pub fn render(a: std.mem.Allocator, io: std.Io, out: *std.Io.Writer, source: []const u8, color: bool, width: usize) !void {
    return renderImages(a, io, out, source, color, width, .{});
}

pub fn renderImages(a: std.mem.Allocator, io: std.Io, out: *std.Io.Writer, source: []const u8, color: bool, width: usize, context: image.Context) !void {
    var pos: usize = 0;
    var paragraph = false;
    var inline_out: Inline = .{ .out = out, .color = color, .width = width, .images = .{ .a = a, .io = io, .context = context } };
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
        if (tableRow(text)) |header| {
            if (pos < source.len) {
                const separator = lineAt(source, pos);
                if (tableRow(separator.text)) |markers| {
                    if (tableAlignment(markers, header.len)) |alignment| {
                        if (paragraph) try out.writeByte('\n');
                        pos = try renderTable(a, out, source, header, alignment, separator.next, color, width);
                        inline_out.column = 0;
                        paragraph = false;
                        continue;
                    }
                }
            }
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
