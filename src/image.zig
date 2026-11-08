const std = @import("std");
extern fn stbi_info_from_memory([*]const u8, c_int, *c_int, *c_int, *c_int) c_int;
extern fn stbi_load_from_memory([*]const u8, c_int, *c_int, *c_int, *c_int, c_int) ?[*]u8;
extern fn stbi_image_free([*]u8) void;
extern fn zc_window_size(*[4]u16) void;
pub const max_input = 16 * 1024 * 1024;
const max_pixels = 16 * 1024 * 1024;

pub const Geometry = struct {
    columns: usize = 80,
    rows: usize = 24,
    cell_width: usize = 8,
    cell_height: usize = 16,

    pub fn detect(width: usize) Geometry {
        var ws: [4]u16 = @splat(0);
        zc_window_size(&ws);
        const cols = if (ws[0] > 0) ws[0] else width;
        const rows = if (ws[1] > 0) ws[1] else 24;
        return .{
            .columns = @max(1, @min(cols, width)),
            .rows = @max(1, rows -| 1),
            .cell_width = if (ws[2] >= cols) ws[2] / cols else 8,
            .cell_height = if (ws[3] >= rows) ws[3] / rows else 16,
        };
    }
};

pub const Context = struct {
    enabled: bool = false,
    geometry: Geometry = .{},
    document: []const u8 = "-",
    graphics_out: ?*std.Io.Writer = null,
};

pub fn extension(path: []const u8) bool {
    const ext = std.fs.path.extension(path);
    for ([_][]const u8{ ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tiff", ".avif" }) |candidate| {
        if (std.ascii.eqlIgnoreCase(ext, candidate)) return true;
    }
    return false;
}

pub fn signature(bytes: []const u8) bool {
    return std.mem.startsWith(u8, bytes, "\x89PNG\r\n\x1a\n") or std.mem.startsWith(u8, bytes, "\xff\xd8\xff");
}

// Encoded bytes are bounded before invoking the decoder. Its allocator has a
// separate hard budget, including temporary allocations (image_decode.c).
pub fn render(a: std.mem.Allocator, out: *std.Io.Writer, bytes: []const u8, geometry: Geometry) !void {
    if (bytes.len > max_input) return error.ImageTooLarge;
    if (!signature(bytes)) return error.UnsupportedImageFormat;
    var w: c_int = 0;
    var h: c_int = 0;
    var channels: c_int = 0;
    if (stbi_info_from_memory(bytes.ptr, @intCast(bytes.len), &w, &h, &channels) == 0) return error.InvalidImage;
    if (w <= 0 or h <= 0 or w > 8192 or h > 8192 or @as(u64, @intCast(w)) * @as(u64, @intCast(h)) > max_pixels) return error.ImageTooLarge;
    const pixels = stbi_load_from_memory(bytes.ptr, @intCast(bytes.len), &w, &h, &channels, 4) orelse return error.InvalidImage;
    defer stbi_image_free(pixels);
    const size = fit(@intCast(w), @intCast(h), geometry);
    const scaled = try a.alloc(u8, size.width * size.height * 4);
    defer a.free(scaled);
    for (0..size.height) |y| for (0..size.width) |x| {
        const src = ((y * @as(usize, @intCast(h)) / size.height) * @as(usize, @intCast(w)) + x * @as(usize, @intCast(w)) / size.width) * 4;
        @memcpy(scaled[(y * size.width + x) * 4 ..][0..4], pixels[src..][0..4]);
    };
    try transmit(out, scaled, size.width, size.height, size.columns, size.rows);
}

const Size = struct { width: usize, height: usize, columns: usize, rows: usize };
fn fit(w: usize, h: usize, g: Geometry) Size {
    // Never enlarge or exceed a screen, even when ioctl is unavailable. Cap
    // reported terminal geometry too; it is not a trusted allocation size.
    const cw = std.math.clamp(g.cell_width, 1, 256);
    const ch = std.math.clamp(g.cell_height, 1, 256);
    const max_w = std.math.clamp(g.columns, 1, 240) * cw;
    const max_h = std.math.clamp(g.rows, 1, 100) * ch;
    var width = @min(w, max_w);
    var height = @max(1, h * width / w);
    if (height > max_h) {
        height = max_h;
        width = @max(1, w * height / h);
    }
    return .{ .width = width, .height = height, .columns = (width + cw - 1) / cw, .rows = (height + ch - 1) / ch };
}

pub fn transmit(out: *std.Io.Writer, rgba: []const u8, w: usize, h: usize, cols: usize, rows: usize) !void {
    // 3072 raw bytes produce at most 4096 base64 bytes, always on a quartet
    // boundary. Quiet mode prevents replies leaking into the caller's shell.
    try out.writeByte('\r');
    var offset: usize = 0;
    while (offset < rgba.len) {
        const end = @min(offset + 3072, rgba.len);
        const more: u8 = if (end < rgba.len) 1 else 0;
        if (offset == 0) {
            try out.print("\x1b_Ga=T,t=d,f=32,s={d},v={d},c={d},r={d},C=1,q=2,m={d};", .{ w, h, cols, rows, more });
        } else try out.print("\x1b_Gm={d};", .{more});
        var encoded: [4096]u8 = undefined;
        try out.writeAll(std.base64.standard.Encoder.encode(&encoded, rgba[offset..end]));
        try out.writeAll("\x1b\\");
        offset = end;
    }
    // Reserve image rows using linefeeds (which scroll reliably at the bottom),
    // not cursor-down commands (which can stop at the screen boundary).
    for (0..rows) |_| try out.writeByte('\n');
    try out.writeByte('\r');
}

pub fn file(a: std.mem.Allocator, io: std.Io, out: *std.Io.Writer, path: []const u8, geometry: Geometry) !void {
    const f = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer f.close(io);
    if ((try f.stat(io)).kind != .file) return error.NotRegularImage;
    var buffer: [8192]u8 = undefined;
    var reader = f.readerStreaming(io, &buffer);
    const bytes = try reader.interface.allocRemaining(a, .limited(max_input));
    defer a.free(bytes);
    try render(a, out, bytes, geometry);
}

// Decode once, reject URL schemes both before and after decoding, and reject
// controls/NUL rather than passing them to filesystem APIs. No URL is fetched.
pub fn localPath(a: std.mem.Allocator, document: []const u8, url: []const u8) ![]u8 {
    var decoded: std.ArrayList(u8) = .empty;
    defer decoded.deinit(a);
    var i: usize = 0;
    while (i < url.len) : (i += 1) {
        var c = url[i];
        if (c == '%') {
            if (i + 2 >= url.len) return error.InvalidImagePath;
            c = (std.fmt.charToDigit(url[i + 1], 16) catch return error.InvalidImagePath) * 16 + (std.fmt.charToDigit(url[i + 2], 16) catch return error.InvalidImagePath);
            i += 2;
        }
        if (c < 32 or c == 127 or c == ':' or c == '?' or c == '#') return error.NonlocalImagePath;
        try decoded.append(a, c);
    }
    if (decoded.items.len == 0 or std.mem.startsWith(u8, decoded.items, "//") or !std.unicode.utf8ValidateSlice(decoded.items)) return error.InvalidImagePath;
    if (std.fs.path.isAbsolute(decoded.items)) return a.dupe(u8, decoded.items);
    return std.fs.path.join(a, &.{ std.fs.path.dirname(document) orelse ".", decoded.items });
}

test "bounded aspect-preserving dimensions" {
    const s = fit(8000, 4000, .{ .columns = 20, .rows = 4 });
    try std.testing.expectEqual(@as(usize, 128), s.width);
    try std.testing.expectEqual(@as(usize, 64), s.height);
    try std.testing.expect(s.columns <= 20 and s.rows <= 4);
    const tall = fit(1, 8192, .{ .columns = 1, .rows = 1 });
    try std.testing.expectEqual(@as(usize, 1), tall.width);
    try std.testing.expectEqual(@as(usize, 16), tall.height);
}

test "local paths decode once and reject schemes and controls" {
    const a = std.testing.allocator;
    const path = try localPath(a, "docs/readme.md", "a%20b.png");
    defer a.free(path);
    try std.testing.expectEqualStrings("docs/a b.png", path);
    for ([_][]const u8{ "https://host/a", "https%3a//host/a", "//host/a", "a%00.png", "a%1b.png", "a%", "" }) |url| {
        if (localPath(a, "-", url)) |p| {
            a.free(p);
            return error.ExpectedRejection;
        } else |_| {}
    }
}
