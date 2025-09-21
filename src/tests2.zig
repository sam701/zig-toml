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
};
const Struct1 = struct {
    i1: i32,
    b1: bool,
};

const Struct2 = struct {
    st1: Struct1,
};

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

    try expectEqual(2, result.value.an1.len);
    try expectEqualSlices(i32, &.{ 1, 2 }, result.value.an1[0]);
    try expectEqualSlices(i32, &.{ 3, 4 }, result.value.an1[1]);

    try expectEqual(Struct1{ .i1 = 3, .b1 = true }, result.value.st1);
    try expectEqual(Struct1{ .i1 = 3, .b1 = true }, result.value.st2.*);
    try expectEqual(Struct1{ .i1 = 3, .b1 = true }, result.value.st3);
    try expectEqual(Struct1{ .i1 = 3, .b1 = true }, result.value.st4.st1);
}
