const std = @import("std");
const testing = std.testing;
const AnyWriter = std.io.AnyWriter;
const Allocator = std.mem.Allocator;
const datetime = @import("../datetime.zig");
const Date = datetime.Date;
const Time = datetime.Time;
const DateTime = datetime.DateTime;
const StructField = std.builtin.Type.StructField;

const SerializerState = struct {
    allocator: Allocator,
    table_comp: std.ArrayList([]const u8),

    const Self = @This();

    fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .table_comp = std.ArrayList([]const u8).init(allocator),
        };
    }

    fn deinit(self: *Self) void {
        self.table_comp.deinit();
    }
};

pub fn serialize(allocator: Allocator, obj: anytype, writer: *AnyWriter) !void {
    const ttype = @TypeOf(obj);
    const tinfo = @typeInfo(ttype);
    var state = SerializerState.init(allocator);
    defer state.deinit();
    try serializeValue(&state, tinfo, obj, writer);
}

fn serializeStruct(state: *SerializerState, value: anytype, writer: *AnyWriter) !void {
    const ttype = @TypeOf(value);
    const tinfo = @typeInfo(ttype);
    if (tinfo != .@"struct") @panic("non struct type given to serialize");

    switch (@TypeOf(value)) {
        Date => {
            try writer.print("{d}-{d:02}-{d:02}", .{ value.year, value.month, value.day });
            return;
        },
        Time => {
            try writer.print("{d:02}:{d:02}:{d:02}", .{ value.hour, value.minute, value.second });
            if (value.nanosecond != 0)
                try writer.print(".{d}", .{value.nanosecond});
            return;
        },
        DateTime => {
            try serializeStruct(state, value.date, writer);
            try serializeStruct(state, value.time, writer);
            if (value.offset_minutes) |om| {
                if (om == 0) return;
                const mins: u16 = @intCast(@divFloor(om, 60));
                const secs: u16 = @intCast(@mod(om, 60));
                try writer.print("-{d:02}:{d:02}", .{ mins, secs });
            }
            return;
        },
        else => {},
    }

    comptime var fields = tinfo.@"struct".fields[0..tinfo.@"struct".fields.len].*;
    comptime std.mem.sortUnstable(StructField, &fields, {}, cmp_field);

    inline for (fields) |field| {
        const ftype = @typeInfo(field.type);

        if (ftype != .@"struct" and comptime !isPointerToStruct(ftype)) {
            try writer.print("{s} = ", .{field.name});
            try serializeValue(state, ftype, @field(value, field.name), writer);
            _ = try writer.write("\n");
        }
    }

    inline for (fields) |field| {
        const ftype = @typeInfo(field.type);
        if (ftype != .@"struct" and comptime !isPointerToStruct(ftype)) continue;

        try state.table_comp.append(field.name);

        // Check if the struct comprises of fields which are basically other structs
        // If so, we don't write anything for this struct and instead write only the
        // structs that it holds.
        //
        // Also, since we treat pointer to structs same as normal structs, we also need
        // resolve the pointers to check if the current field is a struct.
        comptime var ftype2 = ftype;
        inline while (ftype2 == .pointer) ftype2 = @typeInfo(ftype2.pointer.child);
        var has_basic_field: bool = undefined;
        inline for (ftype2.@"struct".fields) |inner_field| {
            const iftype = @typeInfo(inner_field.type);
            if (iftype != .@"struct" and comptime !isPointerToStruct(iftype)) {
                has_basic_field = true;
                break;
            }
            has_basic_field = false;
        }

        if (has_basic_field) {
            try writer.writeByte('[');
            for (0..state.table_comp.items.len - 1) |i| {
                try writer.print("{s}.", .{state.table_comp.items[i]});
            }
            try writer.print("{s}]\n", .{field.name});
        }

        try serializeValue(state, ftype, @field(value, field.name), writer);
        _ = state.table_comp.pop();
    }
}

fn isPointerToStruct(t: std.builtin.Type) bool {
    if (t != .pointer) return false;

    var child = @typeInfo(t.pointer.child);
    while (child == .pointer) child = @typeInfo(child.pointer.child);

    return child == .@"struct";
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
            const has_string_type = ((t.pointer.child == u8 and t.pointer.size == .slice) or (@typeInfo(t.pointer.child) == .array and @typeInfo(t.pointer.child).array.child == u8));
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
                _ = try writer.writeByte('"');
            } else {
                try serializeValue(state, @typeInfo(t.pointer.child), value.*, writer);
            }
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
        .@"struct" => try serializeStruct(state, value, writer),
        .@"enum" => try writer.print("\"{s}\"", .{@tagName(value)}),
        .@"union" => {
            switch (value) {
                inline else => |s| try serializeValue(state, @typeInfo(@TypeOf(s)), s, writer),
            }
        },
        else => {},
    }
}

fn cmp_field(_: void, lhs: StructField, rhs: StructField) bool {
    return std.mem.order(u8, lhs.name, rhs.name) == .lt;
}
