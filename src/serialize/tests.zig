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

test "infinities" {
    var ba = try std.BoundedArray(u8, 16).init(0);
    var writer = ba.writer().any();

    try serialize(Allocator, std.math.inf(f32), &writer);
    try testing.expectEqualSlices(u8, "inf", ba.constSlice());
    ba.clear();

    try serialize(Allocator, -std.math.inf(f32), &writer);
    try testing.expectEqualSlices(u8, "-inf", ba.constSlice());
    ba.clear();

    try serialize(Allocator, std.math.inf(f64), &writer);
    try testing.expectEqualSlices(u8, "inf", ba.constSlice());
    ba.clear();

    try serialize(Allocator, -std.math.inf(f64), &writer);
    try testing.expectEqualSlices(u8, "-inf", ba.constSlice());
    ba.clear();
}

test "pointers" {
    var ba = try std.BoundedArray(u8, 16).init(0);
    var writer = ba.writer().any();

    const num: u8 = 127;
    try serialize(Allocator, &num, &writer);
    try testing.expectEqualSlices(u8, "127", ba.constSlice());
    ba.clear();
}

test "strings" {
    var ba = try std.BoundedArray(u8, 16).init(0);
    var writer = ba.writer().any();

    // Basic string
    try serialize(Allocator, "hello world", &writer);
    try testing.expectEqualSlices(u8, "\"hello world\"", ba.constSlice());
    ba.clear();

    // String with escape chars
    try serialize(Allocator, "hello\nworld", &writer);
    try testing.expectEqualSlices(u8, "\"hello\\nworld\"", ba.constSlice());
    ba.clear();

    // String with escape quotes
    try serialize(Allocator, "hello\"world", &writer);
    try testing.expectEqualSlices(u8, "\"hello\\\"world\"", ba.constSlice());
    ba.clear();

    // String with backslashes
    try serialize(Allocator, "hello\\world", &writer);
    try testing.expectEqualSlices(u8, "\"hello\\\\world\"", ba.constSlice());
    ba.clear();

    // String with escape quotes and backslashes
    try serialize(Allocator, "hello\\\"world", &writer);
    try testing.expectEqualSlices(u8, "\"hello\\\\\\\"world\"", ba.constSlice());
    ba.clear();
}

test "escape codes" {
    var ba = try std.BoundedArray(u8, 16).init(0);
    var writer = ba.writer().any();

    try serialize(Allocator, "\n", &writer);
    try testing.expectEqualSlices(u8, "\"\\n\"", ba.constSlice());
    ba.clear();

    try serialize(Allocator, "\t", &writer);
    try testing.expectEqualSlices(u8, "\"\\t\"", ba.constSlice());
    ba.clear();

    try serialize(Allocator, "\r", &writer);
    try testing.expectEqualSlices(u8, "\"\\r\"", ba.constSlice());
    ba.clear();

    try serialize(Allocator, "\\", &writer);
    try testing.expectEqualSlices(u8, "\"\\\\\"", ba.constSlice());
    ba.clear();

    try serialize(Allocator, "\x0C", &writer);
    try testing.expectEqualSlices(u8, "\"\\f\"", ba.constSlice());
    ba.clear();

    try serialize(Allocator, "\x08", &writer);
    try testing.expectEqualSlices(u8, "\"\\b\"", ba.constSlice());
    ba.clear();
}

test "arrays" {
    var ba = try std.BoundedArray(u8, 64).init(0);
    var writer = ba.writer().any();

    try serialize(Allocator, [_]usize{ 10, 20, 30, 40, 50 }, &writer);
    try testing.expectEqualSlices(u8, "[ 10, 20, 30, 40, 50 ]", ba.constSlice());
    ba.clear();

    try serialize(Allocator, [_][]const u8{ "this", "is", "a", "string" }, &writer);
    try testing.expectEqualSlices(u8, "[ \"this\", \"is\", \"a\", \"string\" ]", ba.constSlice());
    ba.clear();

    try serialize(Allocator, [_][3]usize{ [_]usize{ 1, 2, 3 }, [_]usize{ 4, 5, 6 }, [_]usize{ 7, 8, 9 } }, &writer);
    try testing.expectEqualSlices(u8, "[ [ 1, 2, 3 ], [ 4, 5, 6 ], [ 7, 8, 9 ] ]", ba.constSlice());
    ba.clear();
}

test "structs" {
    var ba = try std.BoundedArray(u8, 512).init(0);
    var writer = ba.writer().any();

    const TestStruct = struct {
        field1: i32,
        field2: []const u8,
        field3: bool,
        field4: f64,
        field5: [5]u8,
        field6: [5][]const u8,
    };

    const t = TestStruct{
        .field1 = 100,
        .field2 = "hello world",
        .field3 = true,
        .field4 = 3.14,
        .field5 = [_]u8{ 1, 2, 3, 4, 5 },
        .field6 = [_][]const u8{ "This", "is", "a", "text", "line" },
    };

    const result =
        \\field1 = 100
        \\field2 = "hello world"
        \\field3 = true
        \\field4 = 3.14
        \\field5 = [ 1, 2, 3, 4, 5 ]
        \\field6 = [ "This", "is", "a", "text", "line" ]
        \\
    ;

    try serialize(Allocator, t, &writer);
    try testing.expectEqualSlices(u8, result, ba.constSlice());
}

test "tables follow top level fields" {
    var ba = try std.BoundedArray(u8, 512).init(0);
    var writer = ba.writer().any();

    const TestStruct2 = struct {
        field1: i32,
    };

    const TestStruct = struct {
        field1: i32,
        field2: []const u8,
        field3: bool,
        field4: f64,
        field7: TestStruct2,
        field5: [5]u8,
        field6: [5][]const u8,
    };

    const t = TestStruct{
        .field1 = 100,
        .field2 = "hello world",
        .field3 = true,
        .field4 = 3.14,
        .field5 = [_]u8{ 1, 2, 3, 4, 5 },
        .field6 = [_][]const u8{ "This", "is", "a", "text", "line" },
        .field7 = .{ .field1 = 10 },
    };

    const result =
        \\field1 = 100
        \\field2 = "hello world"
        \\field3 = true
        \\field4 = 3.14
        \\field5 = [ 1, 2, 3, 4, 5 ]
        \\field6 = [ "This", "is", "a", "text", "line" ]
        \\[field7]
        \\field1 = 10
        \\
    ;

    try serialize(Allocator, t, &writer);
    try testing.expectEqualSlices(u8, result, ba.constSlice());
}

test "top level tables" {
    var ba = try std.BoundedArray(u8, 512).init(0);
    var writer = ba.writer().any();

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
        .field1 = 100,
        .field2 = "hello world",
        .field3 = true,
        .field4 = 3.14,
        .field5 = [_]u8{ 1, 2, 3, 4, 5 },
        .field6 = [_][]const u8{ "This", "is", "a", "text", "line" },
        .field7 = .{ .field1 = 10 },
    };

    const result =
        \\field1 = 100
        \\field2 = "hello world"
        \\field3 = true
        \\field4 = 3.14
        \\field5 = [ 1, 2, 3, 4, 5 ]
        \\field6 = [ "This", "is", "a", "text", "line" ]
        \\[field7]
        \\field1 = 10
        \\
    ;

    try serialize(Allocator, t, &writer);
    try testing.expectEqualSlices(u8, result, ba.constSlice());
}

test "sub tables" {
    var ba = try std.BoundedArray(u8, 512).init(0);
    var writer = ba.writer().any();

    const TestStruct3 = struct {
        field1: i32,
    };

    const TestStruct2 = struct {
        field1: i32,
        field2: *const TestStruct3,
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
        .field1 = 100,
        .field2 = "hello world",
        .field3 = true,
        .field4 = 3.14,
        .field5 = [_]u8{ 1, 2, 3, 4, 5 },
        .field6 = [_][]const u8{ "This", "is", "a", "text", "line" },
        .field7 = .{ .field1 = 10, .field2 = &.{ .field1 = 100 } },
    };

    const result =
        \\field1 = 100
        \\field2 = "hello world"
        \\field3 = true
        \\field4 = 3.14
        \\field5 = [ 1, 2, 3, 4, 5 ]
        \\field6 = [ "This", "is", "a", "text", "line" ]
        \\[field7]
        \\field1 = 10
        \\[field7.field2]
        \\field1 = 100
        \\
    ;

    try serialize(Allocator, t, &writer);
    try testing.expectEqualSlices(u8, result, ba.constSlice());
}
