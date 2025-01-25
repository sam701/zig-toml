const std = @import("std");
const testing = std.testing;
const Allocator = std.testing.allocator;
const AnyWriter = std.io.AnyWriter;

const MAX_FIELD_COUNT: u8 = 255;

pub fn serialize(allocator: std.mem.Allocator, obj: anytype, writer: *AnyWriter) !void {
    try serializeStruct(allocator, obj, writer);
}

fn serializeStruct(allocator: std.mem.Allocator, value: anytype, writer: *AnyWriter) !void {
    const ttype = @TypeOf(value);
    const tinfo = @typeInfo(ttype);
    if (tinfo != .@"struct") @panic("non struct type given to serialize");

    inline for (tinfo.@"struct".fields) |field| {
        try serializeField(allocator, @typeInfo(field.type), field.name, @field(value, field.name), writer);
        _ = try writer.write("\n");
    }
}

fn serializeSimpleValue(allocator: std.mem.Allocator, t: std.builtin.Type, value: anytype, writer: *AnyWriter) !void {
    switch (t) {
        .int, .float => try writer.print("{d}", .{value}),
        .bool => if (value) try writer.print("true", .{}) else try writer.print("false", .{}),
        .pointer => {
            if (t.pointer.child == u8 and t.pointer.size == .slice and t.pointer.is_const) {
                var esc_string = std.ArrayList(u8).init(allocator);
                defer esc_string.deinit();
                const string = value;

                var curr_pos: usize = 0;
                while (curr_pos <= string.len) {
                    const new_pos = std.mem.indexOfAnyPos(u8, string, curr_pos, &.{ '\\', '\"' }) orelse string.len;

                    if (new_pos >= curr_pos) {
                        try esc_string.appendSlice(string[curr_pos..new_pos]);
                        if (new_pos != string.len) {
                            try esc_string.append('\\');
                            try esc_string.append(string[new_pos]);
                        }
                        curr_pos = new_pos + 1;
                    }
                }
                try writer.print("\"{s}\"", .{esc_string.items});
            } else @panic("given type is not a simple type and cannot be serialized directly");
        },
        else => @panic("given type is not a simple type and cannot be serialized directly"),
    }
}

fn serializeField(allocator: std.mem.Allocator, t: std.builtin.Type, key: []const u8, value: anytype, writer: *AnyWriter) !void {
    switch (t) {
        .int, .float, .bool => {
            try writer.print("{s} = ", .{key});
            try serializeSimpleValue(allocator, t, value, writer);
        },
        .pointer => {
            try writer.print("{s} = ", .{key});
            if (t.pointer.child == u8 and t.pointer.size == .slice and t.pointer.is_const)
                try serializeSimpleValue(allocator, t, value, writer);
        },
        .array => {
            try writer.print("{s} = [ ", .{key});
            if (t.array.len != 0) {
                var i: usize = 0;
                while (i < t.array.len - 1) {
                    const elm = value[i];
                    try serializeSimpleValue(allocator, @typeInfo(t.array.child), elm, writer);
                    try writer.print(", ", .{});
                    i += 1;
                }
            }
            const elm = value[t.array.len - 1];
            try serializeSimpleValue(allocator, @typeInfo(t.array.child), elm, writer);
            try writer.print(" ]", .{});
        },
        .@"struct" => {
            try writer.print("[{s}]\n", .{key});
            try serializeStruct(allocator, value, writer);
        },
        else => {},
    }
}

fn getFields(tinfo: std.builtin.Type) std.BoundedArray(std.builtin.Type.StructField, MAX_FIELD_COUNT) {
    comptime var field_names = std.BoundedArray(std.builtin.Type.StructField, MAX_FIELD_COUNT).init(0) catch unreachable;
    comptime var i: u8 = 0;
    const fields = tinfo.@"struct".fields;
    if (fields.len > MAX_FIELD_COUNT) @panic("struct field count exceeded MAX_FIELD_COUNT");
    inline while (i < fields.len) {
        const f = fields.ptr[i];
        field_names.append(f) catch unreachable;
        i += 1;
    }
    return field_names;
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
