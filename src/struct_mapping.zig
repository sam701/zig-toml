const std = @import("std");
const parser = @import("./parser.zig");
const testing = std.testing;

const Value = @import("./value.zig").Value;
const Table = @import("./table.zig").Table;

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

pub fn intoStruct(ctx: *Context, comptime T: type, dest: *T, table: *Table) !void {
    switch (@typeInfo(T)) {
        .Struct => |info| {
            inline for (info.fields) |field_info| {
                try ctx.field_path.append(field_info.name);
                if (table.getPtr(field_info.name)) |val| {
                    try setValue(ctx, field_info.field_type, &@field(dest.*, field_info.name), val);
                } else {
                    // TODO: support optional
                    return error.MissingRequiredField;
                }
                _ = ctx.field_path.pop();
            }
            var it = table.keyIterator();
            while (it.next()) |key| ctx.alloc.free(key.*);
            table.deinit();
        },
        else => return error.Unimplemented,
    }
}

fn setValue(ctx: *Context, comptime T: type, dest: *T, value: *Value) !void {
    switch (@typeInfo(T)) {
        .Int => {
            switch (value.*) {
                .integer => |x| {
                    dest.* = x;
                    // TODO: support different integer sizes
                },
                else => return error.InvalidValueType,
            }
        },
        .Pointer => |tinfo| {
            if (tinfo.size != .Slice) return error.NotSupportedFieldType;
            switch (tinfo.child) {
                u8 => {
                    switch (value.*) {
                        .string => |x| {
                            dest.* = x;
                        },
                        else => return error.InvalidValueType,
                    }
                },
                else => {
                    switch (value.*) {
                        .array => |ar| {
                            var dest_ar = try ctx.alloc.alloc(tinfo.child, ar.len);
                            for (ar) |_, ix| {
                                try setValue(ctx, tinfo.child, &dest_ar[ix], &ar[ix]);
                                // TODO: set path
                            }
                            dest.* = dest_ar;
                            ctx.alloc.free(ar);
                        },
                        else => return error.InvalidValueType,
                    }
                },
            }
        },
        .Struct => {
            switch (value.*) {
                .table => |tab| {
                    try intoStruct(ctx, T, dest, tab);
                    ctx.alloc.destroy(tab);
                },
                else => return error.InvalidValueType,
            }
        },
        else => return error.NotSupportedFieldType,
    }
}
