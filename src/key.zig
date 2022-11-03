const std = @import("std");
const parser = @import("./parser.zig");
const testing = std.testing;

fn isBareKeyChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '_';
}

fn parseBareKey(src: *parser.Source) ![]const u8 {
    return src.takeWhile(isBareKeyChar);
}

pub const Key = union(enum) {
    bare: []const u8,
    dotted: []const []const u8,
};

fn parseDotted(ctx: *parser.Context, first: []const u8) !Key {
    var ar = std.ArrayList([]const u8).init(ctx.alloc);
    try ar.append(first);
    while (ctx.src.current()) |cur| {
        if (cur != '.') break;

        _ = try ctx.src.next();
        try ctx.src.skipSpaces();
        var next = try parseBareKey(ctx.src);
        try ar.append(next);
        try ctx.src.skipSpaces();
    }
    return Key{ .dotted = ar.toOwnedSlice() };
}

pub fn parse(ctx: *parser.Context) !Key {
    var first = try parseBareKey(ctx.src);
    try ctx.src.skipSpaces();
    if (ctx.src.current()) |cur| {
        if (cur == '.') {
            return parseDotted(ctx, first);
        } else {
            return Key{ .bare = first };
        }
    } else {
        return error.UnexpectedEOF;
    }
}

test "bare" {
    var src = parser.Source.init("abc =");
    var ctx = parser.Context{
        .src = &src,
        .alloc = testing.allocator,
    };

    var key = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, key.bare, "abc"));
    try testing.expect(ctx.src.current().? == '=');
}

test "dotted" {
    var src = parser.Source.init("aa.bb . cc .dd");
    var ctx = parser.Context{
        .src = &src,
        .alloc = testing.allocator,
    };

    var key = try parse(&ctx);
    try testing.expect(key.dotted.len == 4);
    try testing.expect(std.mem.eql(u8, key.dotted[1], "bb"));
    try testing.expect(ctx.src.current() == null);

    ctx.alloc.free(key.dotted);
}
