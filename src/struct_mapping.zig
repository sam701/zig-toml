const std = @import("std");
const parser = @import("./parser.zig");
const testing = std.testing;

const Value = @import("./value.zig").Value;
const Table = @import("./table.zig").Table;
const datetime = @import("./datetime.zig");

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
                if (table.fetchRemove(field_info.name)) |entry| {
                    try setValue(ctx, field_info.field_type, &@field(dest.*, field_info.name), &entry.value);
                    ctx.alloc.free(entry.key);
                } else {
                    // TODO: support optional
                    return error.MissingRequiredField;
                }
                _ = ctx.field_path.pop();
            }
            var it = table.iterator();
            while (it.next()) |entry| {
                ctx.alloc.free(entry.key_ptr.*);
                entry.value_ptr.deinit(ctx.alloc);
            }
            table.deinit();
        },
        else => return error.Unimplemented,
    }
}

fn setValue(ctx: *Context, comptime T: type, dest: *T, value: *const Value) !void {
    switch (T) {
        datetime.Date => {
            switch (value.*) {
                .date => |x| {
                    dest.* = x;
                    return;
                },
                else => return error.InvalidValueType,
            }
        },
        datetime.Time => {
            switch (value.*) {
                .time => |x| {
                    dest.* = x;
                    return;
                },
                else => return error.InvalidValueType,
            }
        },
        datetime.DateTime => {
            switch (value.*) {
                .datetime => |x| {
                    dest.* = x;
                    return;
                },
                else => return error.InvalidValueType,
            }
        },
        else => {},
    }
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
        .Float => {
            switch (value.*) {
                .float => |x| {
                    dest.* = x;
                    // TODO: support different float sizes
                },
                .integer => |x| {
                    dest.* = @intToFloat(f64, x);
                    // TODO: support different float sizes
                },
                else => return error.InvalidValueType,
            }
        },
        .Bool => {
            switch (value.*) {
                .boolean => |b| {
                    dest.* = b;
                },
                else => return error.InvalidValueType,
            }
        },
        .Pointer => |tinfo| {
            switch (tinfo.size) {
                .One => {
                    dest.* = try ctx.alloc.create(tinfo.child);
                    errdefer ctx.alloc.destroy(dest.*);
                    return setValue(ctx, tinfo.child, dest.*, value);
                },
                .Slice => {},
                else => return error.NotSupportedFieldType,
            }
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
                            var dest_ar = try ctx.alloc.alloc(tinfo.child, ar.items.len);
                            errdefer ctx.alloc.free(dest_ar);
                            for (ar.items) |_, ix| {
                                try setValue(ctx, tinfo.child, &dest_ar[ix], &ar.items[ix]);
                                // TODO: set path
                            }
                            dest.* = dest_ar;
                            ar.deinit();
                            ctx.alloc.destroy(ar);
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
