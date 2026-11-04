const std = @import("std");
const options = @import("options.zig");
const terminal = @import("terminal.zig");
const highlight = @import("highlight.zig");
const markdown = @import("markdown.zig");
const max_pretty = 8 * 1024 * 1024;

const Sink = struct {
    out: *std.Io.Writer,
    number: bool,
    line: u64 = 1,
    line_start: bool = true,
    writer: std.Io.Writer = .{ .vtable = &.{ .drain = drain }, .buffer = &.{} },

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *Sink = @fieldParentPtr("writer", w);
        var count: usize = 0;
        for (data[0 .. data.len - 1]) |bytes| {
            try self.write(bytes);
            count += bytes.len;
        }
        const last = data[data.len - 1];
        for (0..splat) |_| try self.write(last);
        return count + last.len * splat;
    }

    fn write(self: *Sink, bytes: []const u8) std.Io.Writer.Error!void {
        if (!self.number) return self.out.writeAll(bytes);
        var pos: usize = 0;
        while (pos < bytes.len) {
            if (self.line_start) {
                try self.out.print("{d: >6}  ", .{self.line});
                self.line_start = false;
            }
            const end = if (std.mem.indexOfScalarPos(u8, bytes, pos, '\n')) |at| at + 1 else bytes.len;
            try self.out.writeAll(bytes[pos..end]);
            if (bytes[end - 1] == '\n') {
                self.line_start = true;
                self.line +|= 1;
            }
            pos = end;
        }
    }
};

pub fn main(init: std.process.Init) void {
    run(init) catch |err| {
        var buffer: [1024]u8 = undefined;
        var stderr = std.Io.File.stderr().writerStreaming(init.io, &buffer);
        stderr.interface.print("zcat: {s}\n", .{@errorName(err)}) catch {};
        stderr.interface.flush() catch {};
        std.process.exit(1);
    };
}

fn run(init: std.process.Init) !void {
    const a = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var opts = options.parse(a, args[1..]) catch |err| {
        var buffer: [1024]u8 = undefined;
        var stderr = std.Io.File.stderr().writerStreaming(init.io, &buffer);
        try stderr.interface.print("zcat: {s}; see --help\n", .{@errorName(err)});
        try stderr.interface.flush();
        std.process.exit(2);
    };
    defer opts.deinit(a);
    var out_buffer: [65536]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &out_buffer);
    const out = &stdout.interface;
    switch (opts.action) {
        .help => try out.writeAll(options.help),
        .version => try out.writeAll("zcat 0.1.1\n"),
        .languages => try out.writeAll("zig javascript typescript tsx python json bash c rust markdown text\n"),
        .run => {},
    }
    if (opts.action != .run) return out.flush();
    const tty = try std.Io.File.stdout().isTty(init.io);
    const no_color = if (init.environ_map.get("NO_COLOR")) |v| v.len != 0 else false;
    const dumb = if (init.environ_map.get("TERM")) |v| std.mem.eql(u8, v, "dumb") else false;
    const color = opts.color == .always or (opts.color == .auto and tty and !no_color and !dumb);
    const pretty = !opts.plain and (tty or opts.color == .always or opts.markdown);
    if (!opts.width_set) if (init.environ_map.get("COLUMNS")) |v| {
        const width = std.fmt.parseInt(usize, v, 10) catch 80;
        opts.width = std.math.clamp(width, 20, 240);
    };
    var sink: Sink = .{ .out = out, .number = opts.number };
    const files = if (opts.files.items.len == 0) &[_][]const u8{"-"} else opts.files.items;
    var failed = false;
    for (files) |path| {
        const stdin = std.mem.eql(u8, path, "-");
        const file = if (stdin) std.Io.File.stdin() else std.Io.Dir.cwd().openFile(init.io, path, .{}) catch |err| {
            try diagnostic(init.io, path, err);
            failed = true;
            continue;
        };
        defer if (!stdin) file.close(init.io);
        process(a, init.io, file, &sink, path, opts, pretty, color) catch |err| {
            if (err == error.WriteFailed) return err;
            try diagnostic(init.io, path, err);
            failed = true;
        };
    }
    try out.flush();
    if (failed) std.process.exit(1);
}

fn diagnostic(io: std.Io, path: []const u8, err: anyerror) !void {
    var buffer: [1024]u8 = undefined;
    var stderr = std.Io.File.stderr().writerStreaming(io, &buffer);
    try stderr.interface.writeAll("zcat: ");
    try terminal.safe(&stderr.interface, path);
    try stderr.interface.print(": {s}\n", .{@errorName(err)});
    try stderr.interface.flush();
}

fn process(a: std.mem.Allocator, io: std.Io, file: std.Io.File, sink: *Sink, path: []const u8, opts: options.Options, pretty: bool, color: bool) !void {
    if ((try file.stat(io)).kind == .directory) return error.IsDirectory;
    var buffer: [65536]u8 = undefined;
    var reader = file.readerStreaming(io, &buffer);
    if (!pretty and !opts.number) {
        _ = try reader.interface.streamRemaining(sink.out);
        return;
    }
    var chunk: [65536]u8 = undefined;
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    var large = !pretty;
    var safe_stream: terminal.SafeStream = .{ .out = &sink.writer };
    while (true) {
        const n = try reader.interface.readSliceShort(&chunk);
        if (n == 0) break;
        if (!large and source.items.len + n <= max_pretty) {
            try source.appendSlice(a, chunk[0..n]);
        } else {
            if (!large) {
                try safe_stream.write(source.items);
                source.clearAndFree(a);
                large = true;
            }
            if (pretty) try safe_stream.write(chunk[0..n]) else try sink.write(chunk[0..n]);
        }
    }
    if (large) {
        if (pretty) try safe_stream.finish();
        return;
    }
    const rendered = &sink.writer;
    if (!terminal.validText(source.items)) {
        try terminal.safe(rendered, source.items);
    } else {
        const lang = opts.language orelse options.detect(path, source.items);
        if (opts.markdown or std.mem.eql(u8, lang, "markdown")) {
            try markdown.render(a, io, rendered, source.items, color, opts.width);
        } else try highlight.render(a, io, rendered, source.items, lang, color);
    }
}

test "numbering continues over chunks without a phantom final line" {
    var w: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer w.deinit();
    var sink: Sink = .{ .out = &w.writer, .number = true };
    try sink.write("a");
    try sink.write("b\nc\n");
    try std.testing.expectEqualStrings("     1  ab\n     2  c\n", w.written());
}

test {
    _ = options;
    _ = terminal;
    _ = highlight;
    _ = markdown;
}
