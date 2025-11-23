const std = @import("std");
const testing = std.testing;
const main = @import("./root.zig");
const struct_mapping = @import("./struct_mapping.zig");
const datetime = @import("./datetime.zig");
const Table = @import("./table.zig").Table;

comptime {
    _ = @import("./serialize/tests.zig");
}

test "full" {
    var p = main.Parser(main.Table).init(testing.allocator);
    defer p.deinit();

    const parsed = try p.parseString(
        \\  aa = "a1"
        \\
        \\    bb = 33
    );
    defer parsed.deinit();
    const m = parsed.value;

    try testing.expect(m.count() == 2);
    try testing.expect(std.mem.eql(u8, m.get("aa").?.string, "a1"));
    try testing.expect(m.get("bb").?.integer == 33);
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
    const E1 = enum {
        EnumValue1,
        EnumValue2,
    };
    const UEnum = enum {
        s1,
        s2,
        i1,
        abc,
    };

    const U1 = union(UEnum) {
        s1: []const u8,
        s2: []const u8,
        i1: i32,
        abc,
    };
    const Aa = struct {
        aa: i64,
        aa2: i8,
        aa3: i16 = 500,
        bb: []const u8,
        bb2: []const u8 = "test1",
        b1: bool,
        cc: []i64,
        dd: []const []const u8,
        d2: [3][]const u8,
        t1: Tt,
        t2: Tt,
        t3: Tt,
        t4: Tt,
        p1: P1,
        pt1: *T1,
        f1: f64,
        f1a: f16,
        f1b: f16,
        f2: f64,
        d1: datetime.Date,
        ti1: datetime.Time,
        dt1: datetime.DateTime,
        o1: ?i32,
        o2: ?i32,
        e1: E1,
        tab1: Table,
        tab2: *Table,
        hm: main.HashMap(Tt),
        hm2: *main.HashMap(Tt),
        u1: U1,
        u2: U1,
    };

    var p = main.Parser(Aa).init(testing.allocator);
    defer p.deinit();

    const parsed = try p.parseFile("./test/doc1.toml.txt");
    const aa: Aa = parsed.value;
    defer parsed.deinit();

    try testing.expect(aa.aa == 34);
    try testing.expect(aa.aa2 == 50);
    try testing.expect(aa.aa3 == 500);
    try testing.expect(std.mem.eql(u8, aa.bb, "abcЖ"));
    try testing.expectEqual("test1", aa.bb2);
    try testing.expect(aa.b1 == true);
    try testing.expect(aa.f1 == 125.55);
    try testing.expect(aa.f1a == 99.5);
    try testing.expect(aa.f1b == 99.0);
    try testing.expect(aa.f2 == 125.0);
    try testing.expect(aa.o1 == null);
    try testing.expect(aa.o2.? == 45);
    try testing.expect(std.meta.eql(aa.d1, datetime.Date{ .year = 2022, .month = 12, .day = 10 }));
    try testing.expect(std.meta.eql(aa.ti1, datetime.Time{ .hour = 9, .minute = 7, .second = 14, .nanosecond = 345678000 }));
    try testing.expect(std.meta.eql(aa.dt1, datetime.DateTime{
        .date = datetime.Date{ .year = 2022, .month = 12, .day = 14 },
        .time = datetime.Time{ .hour = 16, .minute = 44, .second = 30 },
        .offset_minutes = 120,
    }));
    try testing.expect(aa.cc.len == 3);
    try testing.expect(aa.cc[0] == 3);
    try testing.expect(aa.cc[1] == 15);
    try testing.expect(aa.cc[2] == 20);

    try testing.expect(aa.dd.len == 2);
    try testing.expect(std.mem.eql(u8, aa.dd[0], "aa"));
    try testing.expect(std.mem.eql(u8, aa.dd[1], "bb"));

    try testing.expectEqualSlices(u8, aa.d2[0], "a1");
    try testing.expectEqualSlices(u8, aa.d2[1], "a2");
    try testing.expectEqualSlices(u8, aa.d2[2], "a3");

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
    try testing.expectEqual(E1.EnumValue1, aa.e1);

    try testing.expectEqual(3, aa.tab1.get("a").?.table.get("val").?.integer);
    try testing.expectEqualSlices(u8, "str1", aa.tab1.get("b").?.table.get("val").?.string);
    try testing.expectEqual(4, aa.tab2.get("a").?.table.get("val").?.integer);
    try testing.expectEqualSlices(u8, "str2", aa.tab2.get("b").?.table.get("val").?.string);

    try testing.expectEqual(3, aa.hm.map.get("f1").?.aa);
    try testing.expectEqual(4, aa.hm.map.get("f1").?.bb);
    try testing.expectEqual(5, aa.hm.map.get("f2").?.aa);
    try testing.expectEqual(6, aa.hm.map.get("f2").?.bb);
    try testing.expectEqual(10, aa.hm.map.get("f3").?.aa);
    try testing.expectEqual(11, aa.hm.map.get("f3").?.bb);

    try testing.expectEqual(3, aa.hm2.map.get("f1").?.aa);
    try testing.expectEqual(4, aa.hm2.map.get("f1").?.bb);
    try testing.expectEqual(5, aa.hm2.map.get("f2").?.aa);
    try testing.expectEqual(6, aa.hm2.map.get("f2").?.bb);
    try testing.expectEqual(10, aa.hm2.map.get("f3").?.aa);
    try testing.expectEqual(11, aa.hm2.map.get("f3").?.bb);

    try testing.expectEqualStrings("string2", aa.u1.s2);
    try testing.expectEqual(UEnum.abc, aa.u2);
}

test "optionals (--release=fast/safe)" {
    const Sub = struct {
        id: u16,
        name: ?[]const u8,
    };

    const Opts = struct {
        sub: ?Sub,
    };

    var p = main.Parser(Opts).init(testing.allocator);
    defer p.deinit();

    const parsed = try p.parseString(
        \\ [sub]
        \\ id = 12
        \\ name = "world"
    );
    defer parsed.deinit();
    const m = parsed.value;

    try std.testing.expect(m.sub != null);
    try std.testing.expectEqual(12, m.sub.?.id);
    try std.testing.expectEqualStrings("world", m.sub.?.name.?);
}

test "deinit table" {
    var p = main.Parser(main.Table).init(testing.allocator);
    defer p.deinit();

    const parsed = try p.parseFile("./test/doc1.toml.txt");
    _ = parsed.value;
    defer parsed.deinit();
}
