const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const parse = @import("./parser2.zig").parse;

const MainStruct = struct {
    i1: i64,
    i2: i32,
    f1: f32,
};
test "full" {
    var reader = std.Io.Reader.fixed(
        \\ i1 = 345
        \\ i2 = 0x468
        \\    f1 = 0.12345
    );
    const result = try parse(MainStruct, &reader, std.testing.allocator);
    defer result.deinit();

    try expectEqual(345, result.value.i1);
    try expectEqual(0x468, result.value.i2);
    try expectEqual(0.12345, result.value.f1);
}
