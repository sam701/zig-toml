const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const parse = @import("./parser2.zig").parse;

const MainStruct = struct {
    aa: i64,
};
test "full" {
    var reader = std.Io.Reader.fixed(
        \\ aa = 345
    );
    const result = try parse(MainStruct, &reader, std.testing.allocator);
    defer result.deinit();

    try expectEqual(345, result.value.aa);
}
