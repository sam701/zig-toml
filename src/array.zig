const std = @import("std");
const parser = @import("./parser.zig");
const testing = std.testing;

const value = @import("./value.zig");
const spaces = @import("./spaces.zig");
const comment = @import("./comment.zig");

pub fn parse(ctx: *parser.Context) !?*value.ValueList {
    parser.consumeString(ctx, "[") catch return null;
    comment.skipSpacesAndComments(ctx);

    var ar = try ctx.alloc.create(value.ValueList);
    errdefer ctx.alloc.destroy(ar);

    ar.* = .{};
    errdefer ar.deinit(ctx.alloc);

    while (true) {
        if (parser.consumeString(ctx, "]")) |_| {
            break;
        } else |_| {}

        const val = try value.parse(ctx);
        try ar.append(ctx.alloc, val);
        comment.skipSpacesAndComments(ctx);
        parser.consumeString(ctx, ",") catch |e| {
            if (parser.consumeString(ctx, "]")) |_| {
                break;
            } else |_| {
                return e;
            }
        };
        comment.skipSpacesAndComments(ctx);
    }
    return ar;
}

test "empty array" {
    var ctx = parser.testInput("[]");
    const ar = (try parse(&ctx)).?;

    try testing.expect(ar.items.len == 0);

    (value.Value{ .array = ar }).deinit(ctx.alloc);
}

test "array without commas" {
    var ctx = parser.testInput("[1 2]");
    try testing.expectError(error.UnexpectedToken, parse(&ctx));
}

test "array" {
    var ctx = parser.testInput(
        \\[  3, 4 ,  
        \\"aa", # comment
        \\[5], ]x
    );
    const ar = (try parse(&ctx)).?;

    try testing.expect(ar.items.len == 4);
    try testing.expect(ar.items[0].integer == 3);
    try testing.expect(ar.items[1].integer == 4);
    try testing.expect(std.mem.eql(u8, ar.items[2].string, "aa"));
    try testing.expect(ar.items[3].array.items[0].integer == 5);

    (value.Value{ .array = ar }).deinit(ctx.alloc);
}
