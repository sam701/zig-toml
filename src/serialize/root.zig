const std = @import("std");
const testing = std.testing;
const Allocator = std.testing.allocator;

const MAX_FIELD_COUNT: u8 = 255;

pub fn tomlize(allocator: std.mem.Allocator, obj: anytype, writer: anytype) !void {
    try serialize_struct(allocator, obj, writer);
}

fn serialize_struct(allocator: std.mem.Allocator, value: anytype, writer: anytype) !void {
    const ttype = @TypeOf(value);
    const tinfo = @typeInfo(ttype);
    if (!std.mem.eql(u8, @tagName(tinfo), "Struct")) @panic("non struct type given to serialize");
    const fields = comptime get_fields(tinfo);

    comptime var i: u8 = 0;
    inline while (i < fields.len) {
        const field = fields.buffer[i];
        try serialize_field(allocator, @typeInfo(field.type), field.name, @field(value, field.name), writer);
        _ = try writer.write("\n");
        i += 1;
    }
}

fn serialize_simple_value(allocator: std.mem.Allocator, t: std.builtin.Type, value: anytype, writer: anytype) !void {
    switch (t) {
        .Int, .Float => try writer.print("{d}", .{value}),
        .Bool => if (value) try writer.print("true", .{}) else try writer.print("false", .{}),
        .Pointer => {
            if (t.Pointer.child == u8 and t.Pointer.size == .Slice and t.Pointer.is_const) {
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

fn serialize_field(allocator: std.mem.Allocator, t: std.builtin.Type, key: []const u8, value: anytype, writer: anytype) !void {
    switch (t) {
        .Int, .Float, .Bool => {
            try writer.print("{s} = ", .{key});
            try serialize_simple_value(allocator, t, value, writer);
        },
        .Pointer => {
            try writer.print("{s} = ", .{key});
            if (t.Pointer.child == u8 and t.Pointer.size == .Slice and t.Pointer.is_const)
                try serialize_simple_value(allocator, t, value, writer);
        },
        .Array => {
            try writer.print("{s} = [ ", .{key});
            if (t.Array.len != 0) {
                var i: usize = 0;
                while (i < t.Array.len - 1) {
                    const elm = value[i];
                    try serialize_simple_value(allocator, @typeInfo(t.Array.child), elm, writer);
                    try writer.print(", ", .{});
                    i += 1;
                }
            }
            const elm = value[t.Array.len - 1];
            try serialize_simple_value(allocator, @typeInfo(t.Array.child), elm, writer);
            try writer.print(" ]", .{});
        },
        .Struct => {
            try writer.print("[{s}]\n", .{key});
            try serialize_struct(allocator, value, writer);
        },
        else => {},
    }
}

fn get_fields(tinfo: std.builtin.Type) std.BoundedArray(std.builtin.Type.StructField, MAX_FIELD_COUNT) {
    comptime var field_names = std.BoundedArray(std.builtin.Type.StructField, MAX_FIELD_COUNT).init(0) catch unreachable;
    comptime var i: u8 = 0;
    const fields = tinfo.Struct.fields;
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
    var writer = stream.writer();
    try tomlize(Allocator, t, &writer);
    std.debug.print("\n{s}", .{buf});
}
