const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const parse = @import("./parser2.zig").parse;

const MainStruct = struct {
    i1: i64,
    i2: i32,
    f1: f32,
    b1: bool,
    b2: bool,
};
test "full" {
    var reader = std.Io.Reader.fixed(
        \\    b1 = true
        \\    b2 = false
        \\ i1 = 345
        \\ i2 = 0x468
        \\    f1 = 0.12345
    );
    const result = try parse(MainStruct, &reader, std.testing.allocator);
    defer result.deinit();

    try expectEqual(345, result.value.i1);
    try expectEqual(0x468, result.value.i2);
    try expectEqual(0.12345, result.value.f1);
    try expect(result.value.b1);
    try expect(!result.value.b2);
}
