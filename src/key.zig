const std = @import("std");
const parser = @import("parser");
const spaces = @import("./spaces.zig");
const string = @import("./string.zig");
const testing = std.testing;

fn isBareKeyChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '_';
}

fn parseBareKey(ctx: *parser.Context) !parser.String {
    if (try string.parseSingleLine(ctx)) |v| {
        return parser.String{ .content = v, .allocated = true };
    } else {
        const v = parser.takeWhile(ctx, isBareKeyChar);
        return parser.String.fromSlice(v);
    }
}

pub const Key = union(enum) {
    bare: parser.String,
    dotted: []const parser.String,

    pub fn deinit(self: *const Key, alloc: std.mem.Allocator) void {
        switch (self.*) {
            .bare => |x| x.deinit(alloc),
            .dotted => |ar| {
                for (ar) |x| x.deinit(alloc);
                alloc.free(ar);
            },
        }
    }

    pub fn asChain(self: *const Key, one: *[1]parser.String) []const parser.String {
        switch (self.*) {
            .bare => |str| {
                one[0] = str;
                return one[0..1];
            },
            .dotted => |chain| return chain,
        }
    }
};

fn parseDotted(ctx: *parser.Context, first: parser.String) !Key {
    var ar = std.ArrayList(parser.String).init(ctx.alloc);
    try ar.append(first);
    while (ctx.current()) |cur| {
        if (cur != '.') break;

        _ = ctx.next();
        spaces.skipSpaces(ctx);
        const next = try parseBareKey(ctx);
        try ar.append(next);
        spaces.skipSpaces(ctx);
    }
    return Key{ .dotted = try ar.toOwnedSlice() };
}

pub fn parse(ctx: *parser.Context) !Key {
    const first = try parseBareKey(ctx);
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
    var ctx = parser.testInput("abc =");
    const key = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, key.bare.content, "abc"));
    try testing.expect(ctx.current().? == '=');
}

test "dotted" {
    var ctx = parser.testInput("aa.bb . cc .dd");
    var key = try parse(&ctx);
    try testing.expect(key.dotted.len == 4);
    try testing.expect(std.mem.eql(u8, key.dotted[1].content, "bb"));
    try testing.expect(ctx.current() == null);
    key.deinit(ctx.alloc);
}

test "quoted key" {
    var ctx = parser.testInput(
        \\dd."bb cc" = "aa"
    );
    var key = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, key.dotted[0].content, "dd"));
    try testing.expect(std.mem.eql(u8, key.dotted[1].content, "bb cc"));
    key.deinit(ctx.alloc);
}

test "quoted literal key" {
    var ctx = parser.testInput(
        \\dd.'bb cc' = "aa"
    );
    var key = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, key.dotted[0].content, "dd"));
    try testing.expect(std.mem.eql(u8, key.dotted[1].content, "bb cc"));
    key.deinit(ctx.alloc);
}

test "quoted key error" {
    var ctx = parser.testInput(
        \\"""bb cc""" = "aa"
    );
    try testing.expectError(error.UnexpectedMultilineString, parse(&ctx));
}
