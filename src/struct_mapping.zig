const std = @import("std");
const parser = @import("./parser.zig");
const testing = std.testing;

const Map = @import("./table_content.zig").Map;
const Value = @import("./value.zig").Value;

pub const Context = struct {
    alloc: std.mem.Allocator,
    field_path: std.ArrayList([]const u8),

    pub fn init(alloc: std.mem.Allocator) Context {
        return .{
            .alloc = alloc,
            .field_path = std.ArrayList([]const u8).init(alloc),
        };
    }

    pub fn deinit(self: *Context) void {
        self.field_path.deinit();
    }
};

pub fn intoStruct(ctx: *Context, comptime T: type, dest: *T, map: *Map) !void {
    switch (@typeInfo(T)) {
        .Struct => |info| {
            inline for (info.fields) |field_info| {
                try ctx.field_path.append(field_info.name);
                if (map.getPtr(field_info.name)) |val| {
                    try setValue(ctx, field_info.field_type, &@field(dest.*, field_info.name), val);
                } else {
                    // TODO: support optional
                    return error.MissingRequiredField;
                }
                _ = ctx.field_path.pop();
            }
            var it = map.keyIterator();
            while (it.next()) |key| ctx.alloc.free(key.*);
            map.deinit();
        },
        else => return error.Unimplemented,
    }
}

fn setValue(_: *Context, comptime T: type, dest: *T, value: *Value) !void {
    switch (value.*) {
        .integer => |x| {
            if (T != i64) return error.InvalidValueType;
            dest.* = x;
        },
        .string => |x| {
            switch (@typeInfo(T)) {
                .Pointer => |pinfo| {
                    if (pinfo.child != u8) return error.InvalidValueType;
                    dest.* = x;
                },
                else => return error.InvalidValueType,
            }
        },
        .array => |ar| {
            // todo
        },
    }
}
