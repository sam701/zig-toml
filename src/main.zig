const std = @import("std");
const testing = std.testing;

const parser = @import("./parser.zig");
const table_content = @import("./table_content.zig");

pub fn parseIntoMap(input: []const u8, alloc: std.mem.Allocator) !table_content.Map {
    var ctx = parser.Context{
        .input = input,
        .alloc = alloc,
    };
    return table_content.parseIntoMap(&ctx);
}

pub const deinitMap = table_content.deinitMap;

test "full" {
    var m = try parseIntoMap(
        \\  aa = "a1"
        \\
        \\    bb = 33
    , testing.allocator);
    try testing.expect(m.count() == 2);
    try testing.expect(std.mem.eql(u8, m.get("aa").?.string, "a1"));
    try testing.expect(m.get("bb").?.integer == 33);
    deinitMap(&m);
}
