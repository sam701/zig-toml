const std = @import("std");
const parser = @import("./parser.zig");
const testing = std.testing;

const string = @import("./string.zig");
const integer = @import("./integer.zig");

pub const Value = union(enum) {
    string: []const u8,
    integer: i64,

    pub fn deinit(self: Value, ctx: *parser.Context) void {
        switch (self) {
            .string => |str| ctx.alloc.free(str),
            else => {},
        }
    }
};

pub fn parse(ctx: *parser.Context) !Value {
    if (try string.parse(ctx)) |str| {
        return Value{ .string = str };
    } else if (try integer.parse(ctx)) |int| {
        return Value{ .integer = int };
    }
    return error.CannotParseValue;
}

test "value string" {
    var ctx = parser.testInput(
        \\"abc"
    );
    var val = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, val.string, "abc"));
    val.deinit(&ctx);
}

test "value integer" {
    var ctx = parser.testInput(
        \\123
    );
    var val = try parse(&ctx);
    try testing.expect(val.integer == 123);
}
