const std = @import("std");
const testing = std.testing;
const main = @import("./main.zig");
const struct_mapping = @import("./struct_mapping.zig");

test "full" {
    var m = try main.parseIntoTable(
        \\  aa = "a1"
        \\
        \\    bb = 33
    , testing.allocator);
    try testing.expect(m.count() == 2);
    try testing.expect(std.mem.eql(u8, m.get("aa").?.string, "a1"));
    try testing.expect(m.get("bb").?.integer == 33);
    main.deinitTable(&m);
}

test "parse into struct" {
    const Tt = struct {
        aa: i64,
        bb: i64,
    };
    const T1 = struct {
        v1: i64,
    };
    const P2 = struct {
        t1: T1,
    };
    const P1 = struct {
        p2: []P2,
    };
    const Aa = struct {
        aa: i64,
        bb: []const u8,
        b1: bool,
        cc: []i64,
        dd: []const []const u8,
        t1: Tt,
        t2: Tt,
        t3: Tt,
        t4: Tt,
        p1: P1,
        pt1: *T1,
    };

    var ctx = struct_mapping.Context.init(testing.allocator);
    var aa: Aa = undefined;

    const file = try std.fs.cwd().openFile("./test/doc1.toml.txt", .{});
    defer file.close();
    var content = try file.readToEndAlloc(testing.allocator, 1024 * 1024 * 1024);
    defer testing.allocator.free(content);

    try main.parseIntoStruct(content, &ctx, Aa, &aa);

    try testing.expect(aa.aa == 34);
    try testing.expect(std.mem.eql(u8, aa.bb, "abcЖ"));
    try testing.expect(aa.b1 == true);
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
    try testing.expect(aa.t3.aa == 11);
    try testing.expect(aa.t3.bb == 15);
    try testing.expect(aa.t4.aa == 21);
    try testing.expect(aa.t4.bb == 22);

    try testing.expect(aa.p1.p2.len == 2);
    try testing.expect(aa.p1.p2[0].t1.v1 == 44);
    try testing.expect(aa.p1.p2[1].t1.v1 == 50);

    try testing.expect(aa.pt1.v1 == 102);

    ctx.alloc.free(aa.bb);
    ctx.alloc.free(aa.cc);
    ctx.alloc.free(aa.dd[0]);
    ctx.alloc.free(aa.dd[1]);
    ctx.alloc.free(aa.dd);
    ctx.alloc.free(aa.p1.p2);
    ctx.alloc.destroy(aa.pt1);

    ctx.deinit();
}

test "deinit table" {
    const file = try std.fs.cwd().openFile("./test/doc1.toml.txt", .{});
    defer file.close();
    var content = try file.readToEndAlloc(testing.allocator, 1024 * 1024 * 1024);
    defer testing.allocator.free(content);

    var tab = try main.parseIntoTable(content, testing.allocator);
    main.deinitTable(&tab);
}
