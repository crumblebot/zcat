const std = @import("std");

pub const help =
    \\zc 0.2.0 — a terminal-aware cat (zcat project)
    \\
    \\Usage: zc [OPTIONS] [FILE ...]
    \\Read FILEs in order; '-' or no files reads stdin. Use '--' before dash-prefixed names.
    \\
    \\  --color=auto|always|never  ANSI policy (default: auto; respects NO_COLOR, TERM=dumb)
    \\  -l, --language NAME       Override detection; use 'text' to disable highlighting
    \\  -m, --markdown            Render Markdown, even when stdout is redirected
    \\  -n, --number              Number output lines (continuous across files)
    \\  --no-header              Hide pretty code filename/language header
    \\  --no-line-numbers        Disable automatic per-file code numbering
    \\  --images=auto|kitty|never Local PNG/JPEG graphics (auto: Ghostty/Kitty TTY)
    \\  --plain, --raw            Exact bytes; excludes -m, -n, and --images=kitty
    \\  --width N                Markdown/image width, 20–240 (default: COLUMNS or 80)
    \\  --list-languages         Print supported language names
    \\  -h, --help               Print this help
    \\  -V, --version            Print version
    \\
    \\Languages: zig, javascript/js, typescript/ts, tsx/jsx, python/py, json,
    \\           bash/sh, c, rust/rs, markdown/md, text/plain
    \\Terminals render Markdown and show highlighted code with headers and line numbers.
    \\Pipes default to exact bytes. --color=always explicitly enables pretty source output.
    \\Pretty output escapes terminal controls; --plain does not. No pager is launched.
    \\
;

pub const Color = enum { auto, always, never };
pub const Options = struct {
    color: Color = .auto,
    language: ?[]const u8 = null,
    markdown: bool = false,
    number: bool = false,
    no_line_numbers: bool = false,
    no_header: bool = false,
    images: enum { auto, kitty, never } = .auto,
    plain: bool = false,
    width: usize = 80,
    width_set: bool = false,
    action: enum { run, help, version, languages } = .run,
    files: std.ArrayList([]const u8) = .empty,

    pub fn deinit(self: *Options, a: std.mem.Allocator) void {
        self.files.deinit(a);
    }
};

pub fn parse(a: std.mem.Allocator, args: []const []const u8) !Options {
    var result: Options = .{};
    errdefer result.deinit(a);
    var end = false;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (end or !std.mem.startsWith(u8, arg, "-") or std.mem.eql(u8, arg, "-")) {
            try result.files.append(a, arg);
        } else if (std.mem.eql(u8, arg, "--")) {
            end = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            result.action = .help;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-V")) {
            result.action = .version;
        } else if (std.mem.eql(u8, arg, "--list-languages")) {
            result.action = .languages;
        } else if (std.mem.eql(u8, arg, "--plain") or std.mem.eql(u8, arg, "--raw")) {
            result.plain = true;
        } else if (std.mem.eql(u8, arg, "--number") or std.mem.eql(u8, arg, "-n")) {
            result.number = true;
        } else if (std.mem.eql(u8, arg, "--no-line-numbers")) {
            result.no_line_numbers = true;
        } else if (std.mem.eql(u8, arg, "--no-header")) {
            result.no_header = true;
        } else if (std.mem.startsWith(u8, arg, "--images=")) {
            result.images = std.meta.stringToEnum(@TypeOf(result.images), arg[9..]) orelse return error.InvalidImages;
        } else if (std.mem.eql(u8, arg, "--markdown") or std.mem.eql(u8, arg, "-m")) {
            result.markdown = true;
        } else if (std.mem.startsWith(u8, arg, "--color=")) {
            result.color = std.meta.stringToEnum(Color, arg[8..]) orelse return error.InvalidColor;
        } else if (std.mem.eql(u8, arg, "--language") or std.mem.eql(u8, arg, "-l")) {
            i += 1;
            if (i == args.len) return error.MissingLanguage;
            result.language = canonical(args[i]) orelse return error.UnknownLanguage;
        } else if (std.mem.startsWith(u8, arg, "--language=")) {
            result.language = canonical(arg[11..]) orelse return error.UnknownLanguage;
        } else if (std.mem.eql(u8, arg, "--width")) {
            i += 1;
            if (i == args.len) return error.MissingWidth;
            result.width_set = true;
            result.width = std.fmt.parseInt(usize, args[i], 10) catch return error.InvalidWidth;
            if (result.width < 20 or result.width > 240) return error.InvalidWidth;
        } else return error.UnknownOption;
    }
    if (result.number and result.no_line_numbers) return error.ConflictingOptions;
    if (result.plain and (result.markdown or result.number or result.images == .kitty)) return error.ConflictingOptions;
    return result;
}

pub fn canonical(name: []const u8) ?[]const u8 {
    const groups = [_][]const []const u8{
        &.{"zig"},                   &.{ "javascript", "js" },     &.{ "typescript", "ts" },
        &.{ "tsx", "jsx" },          &.{ "python", "py" },         &.{"json"},
        &.{ "bash", "sh", "shell" }, &.{ "c", "h" },               &.{ "rust", "rs" },
        &.{ "markdown", "md" },      &.{ "text", "plain", "txt" },
    };
    for (groups) |group| for (group) |alias| {
        if (std.ascii.eqlIgnoreCase(name, alias)) return group[0];
    };
    return null;
}

pub fn detect(path: []const u8, source: []const u8) []const u8 {
    const extension = std.fs.path.extension(path);
    if (extension.len > 1) if (canonical(extension[1..])) |lang| return lang;
    if (std.mem.startsWith(u8, source, "#!")) {
        const line = source[0 .. std.mem.indexOfScalar(u8, source, '\n') orelse source.len];
        if (std.mem.indexOf(u8, line, "python") != null) return "python";
        if (std.mem.indexOf(u8, line, "node") != null) return "javascript";
        if (std.mem.indexOf(u8, line, "bash") != null or std.mem.endsWith(u8, line, "/sh")) return "bash";
    }
    return "text";
}

test "options, aliases, detection, and errors" {
    const t = std.testing;
    var opts = try parse(t.allocator, &.{ "-l", "py", "--color=never", "--", "-file" });
    defer opts.deinit(t.allocator);
    try t.expectEqualStrings("python", opts.language.?);
    try t.expectEqualStrings("-file", opts.files.items[0]);
    try t.expectEqualStrings("rust", detect("x.rs", ""));
    try t.expectEqualStrings("python", detect("-", "#!/usr/bin/env python3\n"));
    try t.expectError(error.UnknownLanguage, parse(t.allocator, &.{ "-l", "bogus" }));
    try t.expectError(error.ConflictingOptions, parse(t.allocator, &.{ "--plain", "-m" }));
    try t.expectError(error.InvalidWidth, parse(t.allocator, &.{ "--width", "0" }));
}
