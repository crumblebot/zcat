const std = @import("std");
const ts = @import("ztreesitter");
const grammars = @import("grammars");
const terminal = @import("terminal.zig");

pub fn grammar(name: []const u8) ?ts.Grammar {
    inline for (.{ "zig", "javascript", "typescript", "tsx", "python", "json", "bash", "c", "rust" }) |key| {
        if (std.mem.eql(u8, name, key)) return @field(grammars, key);
    }
    return null;
}

const codes = [_][]const u8{ "", "\x1b[90m", "\x1b[32m", "\x1b[35m", "\x1b[36m", "\x1b[33m", "\x1b[34m" };
fn style(name: []const u8) u8 {
    const classes = [_][]const []const u8{
        &.{},                                 &.{"comment"},               &.{ "string", "character" },
        &.{ "keyword", "operator" },          &.{ "type", "constructor" }, &.{ "number", "boolean", "constant" },
        &.{ "function", "attribute", "tag" },
    };
    for (classes, 0..) |group, i| for (group) |class| {
        if (std.mem.eql(u8, name, class) or
            (std.mem.startsWith(u8, name, class) and name.len > class.len and name[class.len] == '.')) return @intCast(i);
    };
    return 0;
}

// Execute the grammar's real bundled highlight query, including ztreesitter's
// predicate evaluation. Smaller captures override broad enclosing captures.
pub fn styles(a: std.mem.Allocator, io: std.Io, text: []const u8, lang: ts.Grammar) ![]u8 {
    const result = try a.alloc(u8, text.len);
    errdefer a.free(result);
    @memset(result, 0);
    const lengths = try a.alloc(u32, text.len);
    defer a.free(lengths);
    @memset(lengths, std.math.maxInt(u32));
    var parser: ts.Parser = .init();
    defer parser.deinit();
    try parser.setLanguage(lang.language());
    var tree = try parser.parse(io, .{ .slice = text }, null, .{});
    defer tree.deinit();
    const highlights = lang.queries.highlights orelse return result;
    var query = try ts.Query.init(a, lang.language(), highlights.text, .{ .dialect = highlights.dialect });
    defer query.deinit();
    var cursor = try ts.QueryCursor.init(a);
    defer cursor.deinit();
    var captures = cursor.captures(io, &query, tree.rootNode(), .{ .slice = text }, .{});
    while (try captures.next()) |event| {
        const node = event.node();
        const start = @min(node.startByte(), text.len);
        const end = @min(node.endByte(), text.len);
        const color = style(query.captureName(event.capture().index));
        if (color == 0) continue;
        for (start..end) |i| if (end - start <= lengths[i]) {
            result[i] = color;
            lengths[i] = @intCast(end - start);
        };
    }
    return result;
}

pub fn render(a: std.mem.Allocator, io: std.Io, out: *std.Io.Writer, text: []const u8, name: []const u8, color: bool) !void {
    const lang = grammar(name);
    if (!color or lang == null or text.len == 0) return terminal.safe(out, text);
    const colors = try styles(a, io, text, lang.?);
    defer a.free(colors);
    var pos: usize = 0;
    while (pos < text.len) {
        const id = colors[pos];
        var end = pos + 1;
        while (end < text.len and colors[end] == id) : (end += 1) {}
        if (id != 0) try out.writeAll(codes[id]);
        try terminal.safe(out, text[pos..end]);
        if (id != 0) try out.writeAll(terminal.reset);
        pos = end;
    }
}

test "syntax captures distinguish keywords from strings and comments" {
    const source = "const text = \"const\"; // const\n";
    const colors = try styles(std.testing.allocator, std.testing.io, source, grammar("zig").?);
    defer std.testing.allocator.free(colors);
    try std.testing.expectEqual(@as(u8, 3), colors[0]);
    try std.testing.expectEqual(@as(u8, 2), colors[14]);
    try std.testing.expectEqual(@as(u8, 1), colors[24]);
}

test "all bundled queries compile and capture real syntax" {
    const samples = .{
        .{ "zig", "pub fn main() void { const x = 42; } // hi" },
        .{ "javascript", "const x = 'hello'; // hi" },
        .{ "typescript", "const x: number = 42;" },
        .{ "tsx", "const x = <div title=\"hi\">Hello</div>;" },
        .{ "python", "def hello():\n    return 'world' # hi\n" },
        .{ "json", "{\"hello\": 42, \"yes\": true}" },
        .{ "bash", "#!/bin/bash\necho \"hi\" # hi\n" },
        .{ "c", "int main(void) { return 42; } // hi" },
        .{ "rust", "fn main() { let x = 42; } // hi" },
    };
    inline for (samples) |sample| {
        const colors = try styles(std.testing.allocator, std.testing.io, sample[1], grammar(sample[0]).?);
        defer std.testing.allocator.free(colors);
        var any = false;
        for (colors) |c| if (c != 0) {
            any = true;
        };
        try std.testing.expect(any);
    }
}
