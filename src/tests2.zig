const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualSlices = std.testing.expectEqualSlices;

const parse = @import("./parser2.zig").parse;

const MainStruct = struct {
    i1: i64,
    i2: i32,
    f1: f32,
    b1: bool,
    b2: bool,
    s1: []const u8,
    s2: []const u8,
    s3: []const u8,
    s4: []const u8,
    a1: [3]u8,
    a5: []const i32,
    a6: []const i32,
    an1: []const []const i32,
    st1: Struct1,
    st2: *Struct1,
    st3: Struct1,
    st4: Struct2,
    st5: Struct2,
    st6: Struct2,
    st7: *Struct3,
    st8: *Struct3,
    ta1: []Struct1,
    date1: []const u8,
    datetime: []const u8,
    datetime_local: []const u8,
    time: []const u8,
    opt1: ?i32,
    opt2: ?i32 = null,
    e1: E1,
    u1: U1,
    u2: U1,
    u3: U1,
    u4: U1,
};
const E1 = enum { value1, value2, v3, v4 };
const U1 = union(E1) {
    value1: []const u8,
    value2: i32,
    v3,
    v4: *Struct1,
};
const Struct1 = struct { i1: i32, b1: bool };
const Struct2 = struct { st1: Struct1 };
const Struct3 = struct { st1: *Struct1 };

test "full" {
    var reader = std.Io.Reader.fixed(
        \\    b1 = true
        \\    b2 = false
        \\ i1 = 345
        \\ i2 = 0x468
        \\    f1 = 0.12345
        \\  s1 = "abc"
        \\  s2 = 'abc'
        \\  s3 = """
        \\  line1
        \\ line2"""
        \\ s4 = '''
        \\ line1'''
        \\ a1 = "abc"
        \\ a5 = [1,2]
        \\ a6 = [1, # comment
        \\ 2,]
        \\ an1 = [[1,2,],[3, 4]]
        \\ st3.i1 = 3
        \\ st1 = { i1 = 3, b1 = true }
        \\ 'st2' = { i1 = 3, b1 = true }
        \\
        \\ st3."b1" = true
        \\ st4 = { st1.i1 = 3, st1.b1 = true}
        \\ date1 = 2025-11-23
        \\ datetime = 2025-11-23T03:34:85+02:00
        \\ datetime_local = 2025-11-23 03:34:85
        \\ time = 03:34:85
        \\ opt1 = 34
        \\ opt2 = null
        \\ e1 = "value2"
        \\ u1.value1 = "t3"
        \\ u2 = "v3"
        \\ u3  = {value2 = 678}
        // \\ u4.v4.i1 = 12
        // \\ u4.v4.b1 = true
        \\
        \\
        \\ [st5]
        \\ st1.i1 = 3
        \\ st1.b1 = true
        \\
        \\ [st6.st1]
        \\ i1 = 4
        \\ b1 = false
        \\ [st7]
        \\ st1.i1 = 3
        \\ st1.b1 = true
        \\
        \\ [st8.st1]
        \\ i1 = 4
        \\ b1 = false
        \\ [[ta1]]
        \\ i1 = 7
        \\ b1 = true
        \\ [[ta1]]
        \\ i1 = 8
        \\ b1 = false
    );
    const result = try parse(MainStruct, &reader, std.testing.allocator);
    defer result.deinit();

    try expectEqual(345, result.value.i1);
    try expectEqual(0x468, result.value.i2);
    try expectEqual(0.12345, result.value.f1);
    try expect(result.value.b1);
    try expect(!result.value.b2);
    try expectEqualStrings("abc", result.value.s1);
    try expectEqualStrings("abc", result.value.s2);
    try expectEqualStrings("  line1\n line2", result.value.s3);
    try expectEqualStrings(" line1", result.value.s4);
    try expectEqualStrings("abc", &result.value.a1);
    try expectEqualSlices(i32, &.{ 1, 2 }, result.value.a5);
    try expectEqualStrings("2025-11-23", result.value.date1);
    try expectEqualStrings("2025-11-23T03:34:85+02:00", result.value.datetime);
    try expectEqualStrings("2025-11-23 03:34:85", result.value.datetime_local);
    try expectEqualStrings("03:34:85", result.value.time);
    try expectEqual(34, result.value.opt1);
    try expectEqual(null, result.value.opt2);
    try expectEqual(E1.value2, result.value.e1);
    try expectEqualStrings("t3", result.value.u1.value1);
    try expectEqual(678, result.value.u3.value2);
    try expectEqual(E1.v3, result.value.u2);
    // try expectEqual(12, result.value.u4.v4.i1);
    // try expectEqual(true, result.value.u4.v4.b1);

    try expectEqual(2, result.value.an1.len);
    try expectEqualSlices(i32, &.{ 1, 2 }, result.value.an1[0]);
    try expectEqualSlices(i32, &.{ 3, 4 }, result.value.an1[1]);

    try expectEqual(Struct1{ .i1 = 3, .b1 = true }, result.value.st1);
    try expectEqual(Struct1{ .i1 = 3, .b1 = true }, result.value.st2.*);
    try expectEqual(Struct1{ .i1 = 3, .b1 = true }, result.value.st3);
    try expectEqual(Struct1{ .i1 = 3, .b1 = true }, result.value.st4.st1);
    try expectEqual(Struct1{ .i1 = 3, .b1 = true }, result.value.st5.st1);
    try expectEqual(Struct1{ .i1 = 4, .b1 = false }, result.value.st6.st1);
    try expectEqual(Struct1{ .i1 = 3, .b1 = true }, result.value.st7.st1.*);
    try expectEqual(Struct1{ .i1 = 4, .b1 = false }, result.value.st8.st1.*);

    try expectEqual(2, result.value.ta1.len);
    try expectEqual(Struct1{ .i1 = 7, .b1 = true }, result.value.ta1[0]);
    try expectEqual(Struct1{ .i1 = 8, .b1 = false }, result.value.ta1[1]);
}
