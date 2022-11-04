const std = @import("std");
const parser = @import("./parser.zig");
const spaces = @import("./spaces.zig");
const testing = std.testing;

fn isBareKeyChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '_';
}

fn parseBareKey(ctx: *parser.Context) []const u8 {
    return parser.takeWhile(ctx, isBareKeyChar);
}

pub const Key = union(enum) {
    bare: []const u8,
    dotted: []const []const u8,
};

fn parseDotted(ctx: *parser.Context, first: []const u8) !Key {
    var ar = std.ArrayList([]const u8).init(ctx.alloc);
    try ar.append(first);
    while (ctx.current()) |cur| {
        if (cur != '.') break;

        _ = ctx.next();
        spaces.skipSpaces(ctx);
        var next = parseBareKey(ctx);
        try ar.append(next);
        spaces.skipSpaces(ctx);
    }
    return Key{ .dotted = ar.toOwnedSlice() };
}

pub fn parse(ctx: *parser.Context) !Key {
    var first = parseBareKey(ctx);
    spaces.skipSpaces(ctx);
    if (ctx.current()) |cur| {
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
    var ctx = parser.Context{
        .input = "abc =",
        .alloc = testing.allocator,
    };

    var key = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, key.bare, "abc"));
    try testing.expect(ctx.current().? == '=');
}

test "dotted" {
    var ctx = parser.Context{
        .input = "aa.bb . cc .dd",
        .alloc = testing.allocator,
    };

    var key = try parse(&ctx);
    try testing.expect(key.dotted.len == 4);
    try testing.expect(std.mem.eql(u8, key.dotted[1], "bb"));
    try testing.expect(ctx.current() == null);

    ctx.alloc.free(key.dotted);
}

// TODO: Quoted keys: aa."pp.tt".cc
