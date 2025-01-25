const std = @import("std");
const serialize = @import("./root.zig").serialize;
const testing = std.testing;
const Allocator = testing.allocator;

test "basic literals" {
    var ba = try std.BoundedArray(u8, 16).init(0);
    var writer = ba.writer().any();

    // Comptime integers
    try serialize(Allocator, 127, &writer);
    try testing.expectEqualSlices(u8, "127", ba.constSlice());
    ba.clear();

    try serialize(Allocator, -127, &writer);
    try testing.expectEqualSlices(u8, "-127", ba.constSlice());
    ba.clear();

    // Runtime integers
    var n: i16 = 127;
    try serialize(Allocator, n, &writer);
    try testing.expectEqualSlices(u8, "127", ba.constSlice());
    ba.clear();

    n = -127;
    try serialize(Allocator, n, &writer);
    try testing.expectEqualSlices(u8, "-127", ba.constSlice());
    ba.clear();

    // Booleans
    try serialize(Allocator, true, &writer);
    try testing.expectEqualSlices(u8, "true", ba.constSlice());
    ba.clear();

    try serialize(Allocator, false, &writer);
    try testing.expectEqualSlices(u8, "false", ba.constSlice());
    ba.clear();
}

test "strings" {
    var ba = try std.BoundedArray(u8, 16).init(0);
    var writer = ba.writer().any();

    // Basic string
    try serialize(Allocator, "hello world", &writer);
    try testing.expectEqualSlices(u8, ba.constSlice(), "\"hello world\"");
    ba.clear();

    // String with escape chars
    try serialize(Allocator, "hello\nworld", &writer);
    try testing.expectEqualSlices(u8, ba.constSlice(), "\"hello\nworld\"");
    ba.clear();

    // String with escape quotes
    try serialize(Allocator, "hello\"world", &writer);
    try testing.expectEqualSlices(u8, ba.constSlice(), "\"hello\\\"world\"");
    ba.clear();

    // String with backslashes
    try serialize(Allocator, "hello\\world", &writer);
    try testing.expectEqualSlices(u8, "\"hello\\world\"", ba.constSlice());
    ba.clear();

    // String with escape quotes
    try serialize(Allocator, "hello\\\"world", &writer);
    try testing.expectEqualSlices(u8, ba.constSlice(), "\"hello\\\\\"world\"");
    ba.clear();
}

test "basic test" {
    const TestStruct2 = struct {
        field1: i32,
    };

    const TestStruct = struct {
        field1: i32,
        field2: []const u8,
        field3: bool,
        field4: f64,
        field5: [5]u8,
        field6: [5][]const u8,
        field7: TestStruct2,
    };

    const t = TestStruct{
        .field1 = 1024,
        .field2 = "hello \" \\\" \" world",
        .field3 = false,
        .field4 = 3.14,
        .field5 = [_]u8{ 1, 2, 3, 4, 5 },
        .field6 = [_][]const u8{ "This", "is", "a", "text", "line" },
        .field7 = .{ .field1 = 10 },
    };

    var buf: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    var gwriter = stream.writer();
    var writer = gwriter.any();
    try serialize(Allocator, t, &writer);
    std.debug.print("\n{s}", .{buf});
}
