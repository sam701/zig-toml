const std = @import("std");
const parser = @import("./parser.zig");
const testing = std.testing;

const string = @import("./string.zig");
const integer = @import("./integer.zig");
const array = @import("./array.zig");

pub const Value = union(enum) {
    string: []const u8,
    integer: i64,
    array: []Value,

    pub fn deinit(self: Value, alloc: std.mem.Allocator) void {
        switch (self) {
            .string => |str| alloc.free(str),
            .array => |ar| {
                for (ar) |element| {
                    element.deinit(alloc);
                }
                alloc.free(ar);
            },
            else => {},
        }
    }
};

pub fn parse(ctx: *parser.Context) anyerror!Value {
    if (try string.parse(ctx)) |str| {
        return Value{ .string = str };
    } else if (try integer.parse(ctx)) |int| {
        return Value{ .integer = int };
    } else if (try array.parse(ctx)) |ar| {
        return Value{ .array = ar };
    }
    return error.CannotParseValue;
}

test "value string" {
    var ctx = parser.testInput(
        \\"abc"
    );
    var val = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, val.string, "abc"));
    val.deinit(ctx.alloc);
}

test "value integer" {
    var ctx = parser.testInput(
        \\123
    );
    var val = try parse(&ctx);
    try testing.expect(val.integer == 123);
}
