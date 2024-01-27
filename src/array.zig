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

    ar.* = value.ValueList.init(ctx.alloc);
    errdefer ar.deinit();

    while (true) {
        const val = try value.parse(ctx);
        try ar.append(val);
        comment.skipSpacesAndComments(ctx);
        parser.consumeString(ctx, ",") catch {};
        comment.skipSpacesAndComments(ctx);
        if (parser.consumeString(ctx, "]")) |_| {
            break;
        } else |_| {}
    }
    return ar;
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
