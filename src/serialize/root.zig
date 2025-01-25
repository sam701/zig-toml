const std = @import("std");
const testing = std.testing;
const AnyWriter = std.io.AnyWriter;
const Allocator = std.mem.Allocator;

pub fn serialize(allocator: Allocator, obj: anytype, writer: *AnyWriter) !void {
    const ttype = @TypeOf(obj);
    const tinfo = @typeInfo(ttype);
    try serializeValue(allocator, tinfo, obj, writer);
}

fn serializeStruct(allocator: Allocator, value: anytype, writer: *AnyWriter) !void {
    const ttype = @TypeOf(value);
    const tinfo = @typeInfo(ttype);
    if (tinfo != .@"struct") @panic("non struct type given to serialize");

    inline for (tinfo.@"struct".fields) |field| {
        if (@typeInfo(field.type) == .@"struct")
            try writer.print("[{s}]\n", .{field.name})
        else
            try writer.print("{s} = ", .{field.name});
        try serializeValue(allocator, @typeInfo(field.type), @field(value, field.name), writer);
        _ = try writer.write("\n");
    }
}

fn serializeValue(allocator: Allocator, t: std.builtin.Type, value: anytype, writer: *AnyWriter) !void {
    switch (t) {
        .int, .float, .comptime_int, .comptime_float => try writer.print("{d}", .{value}),
        .bool => if (value) try writer.print("true", .{}) else try writer.print("false", .{}),
        .pointer => {
            const has_string_type = (t.pointer.child == u8 or (@typeInfo(t.pointer.child) == .array and @typeInfo(t.pointer.child).array.child == u8));
            if (has_string_type and t.pointer.is_const) {
                _ = try writer.writeByte('"');
                const string = value;

                var curr_pos: usize = 0;
                while (curr_pos <= string.len) {
                    const new_pos = std.mem.indexOfAnyPos(u8, string, curr_pos, &.{'\"'}) orelse string.len;
                    try writer.print("{s}", .{string[curr_pos..new_pos]});
                    if (new_pos != string.len) {
                        _ = try writer.writeByte('\\');
                        _ = try writer.writeByte(string[new_pos]);
                    }
                    curr_pos = new_pos + 1;
                }
            }
            _ = try writer.writeByte('"');
        },
        .array => {
            try writer.print("[ ", .{});
            if (t.array.len != 0) {
                var i: usize = 0;
                while (i < t.array.len - 1) {
                    const elm = value[i];
                    try serializeValue(allocator, @typeInfo(t.array.child), elm, writer);
                    try writer.print(", ", .{});
                    i += 1;
                }
            }
            const elm = value[t.array.len - 1];
            try serializeValue(allocator, @typeInfo(t.array.child), elm, writer);
            try writer.print(" ]", .{});
        },
        .@"struct" => {
            try serializeStruct(allocator, value, writer);
        },
        else => {},
    }
}
