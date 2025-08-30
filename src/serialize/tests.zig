const std = @import("std");
const serialize = @import("../root.zig").serialize;
const testing = std.testing;
const Allocator = testing.allocator;
const datetime = @import("../datetime.zig");
const Date = datetime.Date;
const Time = datetime.Time;
const DateTime = datetime.DateTime;

test "basic literals" {
    var buf: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    // Comptime integers
    try serialize(Allocator, 127, &writer);
    try testing.expectEqualSlices(u8, "127", writer.buffered());
    writer.end = 0;

    try serialize(Allocator, -127, &writer);
    try testing.expectEqualSlices(u8, "-127", writer.buffered());
    writer.end = 0;

    // Runtime integers
    var n: i16 = 127;
    try serialize(Allocator, n, &writer);
    try testing.expectEqualSlices(u8, "127", writer.buffered());
    writer.end = 0;

    n = -127;
    try serialize(Allocator, n, &writer);
    try testing.expectEqualSlices(u8, "-127", writer.buffered());
    writer.end = 0;

    // Booleans
    try serialize(Allocator, true, &writer);
    try testing.expectEqualSlices(u8, "true", writer.buffered());
    writer.end = 0;

    try serialize(Allocator, false, &writer);
    try testing.expectEqualSlices(u8, "false", writer.buffered());
    writer.end = 0;
}

test "infinities" {
    var buf: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try serialize(Allocator, std.math.inf(f32), &writer);
    try testing.expectEqualSlices(u8, "inf", writer.buffered());
    writer.end = 0;

    try serialize(Allocator, -std.math.inf(f32), &writer);
    try testing.expectEqualSlices(u8, "-inf", writer.buffered());
    writer.end = 0;

    try serialize(Allocator, std.math.inf(f64), &writer);
    try testing.expectEqualSlices(u8, "inf", writer.buffered());
    writer.end = 0;

    try serialize(Allocator, -std.math.inf(f64), &writer);
    try testing.expectEqualSlices(u8, "-inf", writer.buffered());
    writer.end = 0;
}

test "pointers" {
    var buf: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    const num: u8 = 127;
    try serialize(Allocator, &num, &writer);
    try testing.expectEqualSlices(u8, "127", writer.buffered());
    writer.end = 0;
}

test "enums" {
    const Color = enum {
        Red,
        Green,
        Yellow,
        Blue,
        Pink,
    };

    const color = Color.Blue;
    var buf: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try serialize(Allocator, color, &writer);
    try testing.expectEqualSlices(u8, "\"Blue\"", writer.buffered());
    writer.end = 0;
}

test "optionals" {
    var buf: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    var optval: ?u32 = null;
    try serialize(Allocator, optval, &writer);
    try testing.expectEqualSlices(u8, "", writer.buffered());

    optval = 100;
    try serialize(Allocator, optval, &writer);
    try testing.expectEqualSlices(u8, "100", writer.buffered());
}

test "unions" {
    const MyUnion = union(enum) {
        f1: u8,
        f2: u16,
        f3: []const u8,
    };

    const u = MyUnion{ .f1 = 255 };
    var buf: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try serialize(Allocator, u, &writer);
    try testing.expectEqualSlices(u8, "255", writer.buffered());
    writer.end = 0;
}

test "strings" {
    var buf: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    // Basic string
    try serialize(Allocator, "hello world", &writer);
    try testing.expectEqualSlices(u8, "\"hello world\"", writer.buffered());
    writer.end = 0;

    // String with escape chars
    try serialize(Allocator, "hello\nworld", &writer);
    try testing.expectEqualSlices(u8, "\"hello\\nworld\"", writer.buffered());
    writer.end = 0;

    // String with escape quotes
    try serialize(Allocator, "hello\"world", &writer);
    try testing.expectEqualSlices(u8, "\"hello\\\"world\"", writer.buffered());
    writer.end = 0;

    // String with backslashes
    try serialize(Allocator, "hello\\world", &writer);
    try testing.expectEqualSlices(u8, "\"hello\\\\world\"", writer.buffered());
    writer.end = 0;

    // String with escape quotes and backslashes
    try serialize(Allocator, "hello\\\"world", &writer);
    try testing.expectEqualSlices(u8, "\"hello\\\\\\\"world\"", writer.buffered());
    writer.end = 0;
}

test "date times" {
    var buf: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try serialize(Allocator, Date{ .day = 1, .month = 2, .year = 2025 }, &writer);
    try testing.expectEqualSlices(u8, "2025-02-01", writer.buffered());
    writer.end = 0;

    try serialize(Allocator, Time{ .hour = 15, .minute = 5, .second = 0 }, &writer);
    try testing.expectEqualSlices(u8, "15:05:00", writer.buffered());
    writer.end = 0;

    try serialize(Allocator, Time{ .hour = 15, .minute = 5, .second = 0, .nanosecond = 123456789 }, &writer);
    try testing.expectEqualSlices(u8, "15:05:00.123456789", writer.buffered());
    writer.end = 0;

    try serialize(Allocator, DateTime{
        .time = .{ .hour = 15, .minute = 5, .second = 0, .nanosecond = 123456789 },
        .date = .{ .day = 1, .month = 2, .year = 2025 },
        .offset_minutes = 150,
    }, &writer);
    try testing.expectEqualSlices(u8, "2025-02-0115:05:00.123456789-02:30", writer.buffered());
    writer.end = 0;
}

test "escape codes" {
    var buf: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try serialize(Allocator, "\n", &writer);
    try testing.expectEqualSlices(u8, "\"\\n\"", writer.buffered());
    writer.end = 0;

    try serialize(Allocator, "\t", &writer);
    try testing.expectEqualSlices(u8, "\"\\t\"", writer.buffered());
    writer.end = 0;

    try serialize(Allocator, "\r", &writer);
    try testing.expectEqualSlices(u8, "\"\\r\"", writer.buffered());
    writer.end = 0;

    try serialize(Allocator, "\\", &writer);
    try testing.expectEqualSlices(u8, "\"\\\\\"", writer.buffered());
    writer.end = 0;

    try serialize(Allocator, "\x0C", &writer);
    try testing.expectEqualSlices(u8, "\"\\f\"", writer.buffered());
    writer.end = 0;

    try serialize(Allocator, "\x08", &writer);
    try testing.expectEqualSlices(u8, "\"\\b\"", writer.buffered());
    writer.end = 0;
}

test "arrays" {
    var buf: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try serialize(Allocator, [_]usize{ 10, 20, 30, 40, 50 }, &writer);
    try testing.expectEqualSlices(u8, "[ 10, 20, 30, 40, 50 ]", writer.buffered());
    writer.end = 0;

    try serialize(Allocator, [_][]const u8{ "this", "is", "a", "string" }, &writer);
    try testing.expectEqualSlices(u8, "[ \"this\", \"is\", \"a\", \"string\" ]", writer.buffered());
    writer.end = 0;

    try serialize(Allocator, [_][3]usize{ [_]usize{ 1, 2, 3 }, [_]usize{ 4, 5, 6 }, [_]usize{ 7, 8, 9 } }, &writer);
    try testing.expectEqualSlices(u8, "[ [ 1, 2, 3 ], [ 4, 5, 6 ], [ 7, 8, 9 ] ]", writer.buffered());
    writer.end = 0;
}

test "arrays containing complex objects" {
    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    const TestStruct2 = struct {
        field1: i32,
        field2: f32,
    };
    const TestStruct = struct {
        field1: [2]TestStruct2,
        field2: [2]*const TestStruct2,
        field3: [2]std.StringHashMap(usize),
    };

    const tp1 = TestStruct2{
        .field1 = 100,
        .field2 = 0.1,
    };
    const tp2 = TestStruct2{
        .field1 = 200,
        .field2 = 0.2,
    };

    var hashmap1 = std.StringHashMap(usize).init(testing.allocator);
    var hashmap2 = std.StringHashMap(usize).init(testing.allocator);
    defer hashmap1.deinit();
    defer hashmap2.deinit();
    try hashmap1.put("a", 1);
    try hashmap1.put("b", 2);
    try hashmap1.put("c", 3);
    try hashmap2.put("d", 4);
    try hashmap2.put("e", 5);
    try hashmap2.put("f", 6);

    const t = TestStruct{
        .field1 = [_]TestStruct2{ TestStruct2{ .field1 = 10, .field2 = 2.71 }, TestStruct2{ .field1 = 20, .field2 = 3.14 } },
        .field2 = [_]*const TestStruct2{ &tp1, &tp2 },
        .field3 = [_]std.StringHashMap(usize){ hashmap1, hashmap2 },
    };

    const result =
        \\[[field1]]
        \\field1 = 10
        \\field2 = 2.71
        \\[[field1]]
        \\field1 = 20
        \\field2 = 3.14
        \\[[field2]]
        \\field1 = 100
        \\field2 = 0.1
        \\[[field2]]
        \\field1 = 200
        \\field2 = 0.2
        \\[[field3]]
        \\a = 1
        \\b = 2
        \\c = 3
        \\[[field3]]
        \\d = 4
        \\e = 5
        \\f = 6
        \\
    ;

    try serialize(Allocator, t, &writer);
    try testing.expectEqualSlices(u8, result, writer.buffered());
}

test "structs" {
    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

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
    try testing.expectEqualSlices(u8, result, writer.buffered());
}

test "tables follow top level fields" {
    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

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
    try testing.expectEqualSlices(u8, result, writer.buffered());
}

test "top level tables" {
    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

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
    try testing.expectEqualSlices(u8, result, writer.buffered());
}

test "sub tables" {
    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

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
    try testing.expectEqualSlices(u8, result, writer.buffered());
}

test "sort fields" {
    var buf: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    const TestStruct = struct {
        field3: i32,
        field1: f32,
    };

    const t = TestStruct{ .field1 = 3.14, .field3 = 123 };

    const result =
        \\field1 = 3.14
        \\field3 = 123
        \\
    ;

    try serialize(Allocator, t, &writer);
    try testing.expectEqualSlices(u8, result, writer.buffered());
}

test "tables with no basic value" {
    var buf: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    const TestStruct3 = struct {
        field3: i32,
    };

    const TestStruct2 = struct {
        field2: *const TestStruct3,
    };

    const TestStruct = struct {
        field1: TestStruct2,
    };

    const t = TestStruct{
        .field1 = .{ .field2 = &.{ .field3 = 100 } },
    };

    const result =
        \\[field1.field2]
        \\field3 = 100
        \\
    ;

    try serialize(Allocator, t, &writer);
    try testing.expectEqualSlices(u8, result, writer.buffered());
}

test "simple value maps" {
    var hashmap = std.StringHashMap(usize).init(testing.allocator);
    defer hashmap.deinit();
    try hashmap.put("a", 1);
    try hashmap.put("b", 2);
    try hashmap.put("c", 3);
    try hashmap.put("d", 4);
    try hashmap.put("e", 5);

    const result =
        \\a = 1
        \\b = 2
        \\c = 3
        \\d = 4
        \\e = 5
        \\
    ;

    var buf: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try serialize(Allocator, hashmap, &writer);
    try testing.expectEqualSlices(u8, result, writer.buffered());
}

test "maps with structs" {
    const TestStruct = struct {
        field1: usize,
    };

    const t1 = TestStruct{ .field1 = 1 };
    const t2 = TestStruct{ .field1 = 2 };
    const t3 = TestStruct{ .field1 = 3 };

    var hashmap = std.StringHashMap(TestStruct).init(testing.allocator);
    defer hashmap.deinit();
    try hashmap.put("a", t1);
    try hashmap.put("b", t2);
    try hashmap.put("c", t3);

    const result =
        \\[a]
        \\field1 = 1
        \\[b]
        \\field1 = 2
        \\[c]
        \\field1 = 3
        \\
    ;

    var buf: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try serialize(Allocator, hashmap, &writer);
    try testing.expectEqualSlices(u8, result, writer.buffered());
}

test "maps with maps" {
    var hashmap = std.StringHashMap(std.StringHashMap(usize)).init(testing.allocator);
    var hashmap1 = std.StringHashMap(usize).init(testing.allocator);
    var hashmap2 = std.StringHashMap(usize).init(testing.allocator);
    var hashmap3 = std.StringHashMap(usize).init(testing.allocator);
    defer hashmap.deinit();
    defer hashmap1.deinit();
    defer hashmap2.deinit();
    defer hashmap3.deinit();

    try hashmap1.put("a1", 1);
    try hashmap1.put("a2", 2);
    try hashmap1.put("a3", 3);

    try hashmap2.put("b1", 1);
    try hashmap2.put("b2", 2);
    try hashmap2.put("b3", 3);

    try hashmap3.put("c1", 1);
    try hashmap3.put("c2", 2);
    try hashmap3.put("c3", 3);

    try hashmap.put("a", hashmap1);
    try hashmap.put("b", hashmap2);
    try hashmap.put("c", hashmap3);

    const result =
        \\[a]
        \\a1 = 1
        \\a2 = 2
        \\a3 = 3
        \\[b]
        \\b1 = 1
        \\b2 = 2
        \\b3 = 3
        \\[c]
        \\c1 = 1
        \\c2 = 2
        \\c3 = 3
        \\
    ;

    var buf: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try serialize(Allocator, hashmap, &writer);
    try testing.expectEqualSlices(u8, result, writer.buffered());
}

test "structs containing maps" {
    const TestStruct = struct {
        field1: std.StringHashMap(usize) = std.StringHashMap(usize).init(testing.allocator),
        field2: std.StringHashMap(usize) = std.StringHashMap(usize).init(testing.allocator),
        field3: std.StringHashMap(usize) = std.StringHashMap(usize).init(testing.allocator),
    };

    var t = TestStruct{};
    defer t.field1.deinit();
    defer t.field2.deinit();
    defer t.field3.deinit();

    try t.field1.put("a", 1);
    try t.field1.put("b", 2);
    try t.field1.put("c", 3);

    try t.field2.put("a", 1);
    try t.field2.put("b", 2);
    try t.field2.put("c", 3);

    try t.field3.put("a", 1);
    try t.field3.put("b", 2);
    try t.field3.put("c", 3);

    const result =
        \\[field1]
        \\a = 1
        \\b = 2
        \\c = 3
        \\[field2]
        \\a = 1
        \\b = 2
        \\c = 3
        \\[field3]
        \\a = 1
        \\b = 2
        \\c = 3
        \\
    ;

    var buf: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try serialize(Allocator, t, &writer);
    try testing.expectEqualSlices(u8, result, writer.buffered());
}
