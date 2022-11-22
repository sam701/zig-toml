const std = @import("std");
const testing = std.testing;

const parser = @import("./parser.zig");
const table_content = @import("./table_content.zig");
const struct_mapping = @import("./struct_mapping.zig");

pub fn parseIntoMap(input: []const u8, alloc: std.mem.Allocator) !table_content.Map {
    var ctx = parser.Context{
        .input = input,
        .alloc = alloc,
    };
    return table_content.parseIntoMap(&ctx);
}

pub fn parseIntoStruct(input: []const u8, ctx: *struct_mapping.Context, comptime T: type, dest: *T) !void {
    var map = try parseIntoMap(input, ctx.alloc);
    try struct_mapping.intoStruct(ctx, T, dest, &map);
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

test "parse into struct" {
    const Aa = struct {
        aa: i64,
        bb: []const u8,
        cc: []i64,
        dd: []const []const u8,
    };

    var ctx = struct_mapping.Context.init(testing.allocator);
    var aa: Aa = undefined;
    try parseIntoStruct(
        \\aa = 34
        \\ bb = "abc"
        \\  cc = [3, 15]
        \\dd = ["aa", "bb"]
    , &ctx, Aa, &aa);

    try testing.expect(aa.aa == 34);
    try testing.expect(std.mem.eql(u8, aa.bb, "abc"));
    try testing.expect(aa.cc.len == 2);
    try testing.expect(aa.cc[0] == 3);
    try testing.expect(aa.cc[1] == 15);

    try testing.expect(aa.dd.len == 2);
    try testing.expect(std.mem.eql(u8, aa.dd[0], "aa"));
    try testing.expect(std.mem.eql(u8, aa.dd[1], "bb"));

    ctx.alloc.free(aa.bb);
    ctx.alloc.free(aa.cc);
    ctx.alloc.free(aa.dd[0]);
    ctx.alloc.free(aa.dd[1]);
    ctx.alloc.free(aa.dd);

    ctx.deinit();
}
