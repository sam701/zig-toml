const std = @import("std");
const testing = std.testing;

const parser = @import("./parser.zig");
const table_content = @import("./table_content.zig");
const struct_mapping = @import("./struct_mapping.zig");
pub const Table = @import("./value.zig").Table;

pub fn parseIntoTable(input: []const u8, alloc: std.mem.Allocator) !Table {
    var ctx = parser.Context{
        .input = input,
        .alloc = alloc,
    };
    return table_content.parse(&ctx);
}

pub fn parseIntoStruct(input: []const u8, ctx: *struct_mapping.Context, comptime T: type, dest: *T) !void {
    var map = try parseIntoTable(input, ctx.alloc);
    try struct_mapping.intoStruct(ctx, T, dest, &map);
}

pub const deinitTable = table_content.deinitTable;

test "full" {
    var m = try parseIntoTable(
        \\  aa = "a1"
        \\
        \\    bb = 33
    , testing.allocator);
    try testing.expect(m.count() == 2);
    try testing.expect(std.mem.eql(u8, m.get("aa").?.string, "a1"));
    try testing.expect(m.get("bb").?.integer == 33);
    deinitTable(&m);
}

test "parse into struct" {
    const Tt = struct {
        aa: i64,
        bb: i64,
    };
    const Aa = struct {
        aa: i64,
        bb: []const u8,
        cc: []i64,
        dd: []const []const u8,
        t1: Tt,
        t2: Tt,
    };

    var ctx = struct_mapping.Context.init(testing.allocator);
    var aa: Aa = undefined;

    const file = try std.fs.cwd().openFile("./test/doc1.toml.txt", .{});
    defer file.close();
    var content = try file.readToEndAlloc(testing.allocator, 1024 * 1024 * 1024);
    defer testing.allocator.free(content);

    try parseIntoStruct(content, &ctx, Aa, &aa);

    try testing.expect(aa.aa == 34);
    try testing.expect(std.mem.eql(u8, aa.bb, "abc"));
    try testing.expect(aa.cc.len == 3);
    try testing.expect(aa.cc[0] == 3);
    try testing.expect(aa.cc[1] == 15);
    try testing.expect(aa.cc[2] == 20);

    try testing.expect(aa.dd.len == 2);
    try testing.expect(std.mem.eql(u8, aa.dd[0], "aa"));
    try testing.expect(std.mem.eql(u8, aa.dd[1], "bb"));

    try testing.expect(aa.t1.aa == 3);
    try testing.expect(aa.t1.bb == 4);
    try testing.expect(aa.t2.aa == 5);
    try testing.expect(aa.t2.bb == 6);

    ctx.alloc.free(aa.bb);
    ctx.alloc.free(aa.cc);
    ctx.alloc.free(aa.dd[0]);
    ctx.alloc.free(aa.dd[1]);
    ctx.alloc.free(aa.dd);

    ctx.deinit();
}

test "deinit table" {
    const file = try std.fs.cwd().openFile("./test/doc1.toml.txt", .{});
    defer file.close();
    var content = try file.readToEndAlloc(testing.allocator, 1024 * 1024 * 1024);
    defer testing.allocator.free(content);

    var table = try parseIntoTable(content, testing.allocator);
    deinitTable(&table);
}
