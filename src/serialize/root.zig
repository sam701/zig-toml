const std = @import("std");
const testing = std.testing;
const AnyWriter = std.io.AnyWriter;
const Allocator = std.mem.Allocator;

const SerializerState = struct {
    allocator: Allocator,
    table_level: std.ArrayList([]const u8),

    const Self = @This();

    fn deinit(self: *Self) void {
        self.table_level.deinit();
    }
};

pub fn serialize(allocator: Allocator, obj: anytype, writer: *AnyWriter) !void {
    const ttype = @TypeOf(obj);
    const tinfo = @typeInfo(ttype);
    var state = SerializerState{
        .allocator = allocator,
        .table_level = std.ArrayList([]const u8).init(allocator),
    };
    defer state.deinit();
    try serializeValue(&state, tinfo, obj, writer);
}

fn serializeStruct(state: *SerializerState, value: anytype, writer: *AnyWriter) !void {
    const ttype = @TypeOf(value);
    const tinfo = @typeInfo(ttype);
    if (tinfo != .@"struct") @panic("non struct type given to serialize");

    inline for (tinfo.@"struct".fields) |field| {
        const ftype = @typeInfo(field.type);

        if (ftype == .@"struct") {
            try state.table_level.append(field.name);
            try writer.writeByte('[');
            for (0..state.table_level.items.len - 1) |i| {
                try writer.print("{s}.", .{state.table_level.items[i]});
            }
            try writer.print("{s}]\n", .{field.name});
            try serializeValue(state, ftype, @field(value, field.name), writer);
            _ = state.table_level.popOrNull();
        } else {
            try writer.print("{s} = ", .{field.name});
            try serializeValue(state, ftype, @field(value, field.name), writer);
            _ = try writer.write("\n");
        }
    }
}

fn serializeValue(state: *SerializerState, t: std.builtin.Type, value: anytype, writer: *AnyWriter) !void {
    switch (t) {
        .int, .float, .comptime_int, .comptime_float => {
            if (t == .float) {
                if (value == std.math.inf(@TypeOf(value))) {
                    try writer.print("inf", .{});
                    return;
                } else if (value == -std.math.inf(@TypeOf(value))) {
                    try writer.print("-inf", .{});
                    return;
                }
            }
            try writer.print("{d}", .{value});
        },
        .bool => if (value) try writer.print("true", .{}) else try writer.print("false", .{}),
        .pointer => {
            const has_string_type = (t.pointer.child == u8 or (@typeInfo(t.pointer.child) == .array and @typeInfo(t.pointer.child).array.child == u8));
            if (has_string_type and t.pointer.is_const) {
                _ = try writer.writeByte('"');
                const string = value;

                var curr_pos: usize = 0;
                while (curr_pos <= string.len) {
                    const new_pos = std.mem.indexOfAnyPos(u8, string, curr_pos, &.{ '"', '\n', '\t', '\r', '\\', 0x0C, 0x08 }) orelse string.len;
                    try writer.print("{s}", .{string[curr_pos..new_pos]});
                    if (new_pos != string.len) {
                        _ = try writer.writeByte('\\');
                        switch (string[new_pos]) {
                            '"' => _ = try writer.writeByte('"'),
                            '\n' => _ = try writer.writeByte('n'),
                            '\t' => _ = try writer.writeByte('t'),
                            '\r' => _ = try writer.writeByte('r'),
                            '\\' => _ = try writer.writeByte('\\'),
                            0x0C => _ = try writer.writeByte('f'),
                            0x08 => _ = try writer.writeByte('b'),
                            else => unreachable,
                        }
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
                    try serializeValue(state, @typeInfo(t.array.child), elm, writer);
                    try writer.print(", ", .{});
                    i += 1;
                }
            }
            const elm = value[t.array.len - 1];
            try serializeValue(state, @typeInfo(t.array.child), elm, writer);
            try writer.print(" ]", .{});
        },
        .@"struct" => {
            try serializeStruct(state, value, writer);
        },
        else => {},
    }
}
