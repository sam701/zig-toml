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
    if (std.meta.hasFn(T, "tomlIntoStruct")) {
        dest.* = try T.tomlIntoStruct(ctx, table);
        return;
    }
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            inline for (info.fields) |field_info| {
                try ctx.field_path.append(field_info.name);
                if (table.fetchRemove(field_info.name)) |entry| {
                    try setValue(ctx, field_info.type, &@field(dest.*, field_info.name), &entry.value);
                    ctx.alloc.free(entry.key);
                } else {
                    if (@typeInfo(field_info.type) == .optional)
                        @field(dest.*, field_info.name) = null
                    else if (field_info.default_value_ptr) |defaultValue| {
                        @field(dest.*, field_info.name) = @as(*const field_info.type, @ptrCast(@alignCast(defaultValue))).*;
                    } else return error.MissingRequiredField;
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
        else => unreachable,
    }
}

fn setValue(ctx: *Context, comptime T: type, dest: *T, value: *const Value) !void {
    switch (T) {
        Table => {
            dest.* = value.table.*;
            return;
        },
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
        .int => {
            switch (value.*) {
                .integer => |x| {
                    dest.* = @intCast(x);
                },
                else => return error.InvalidValueType,
            }
        },
        .float => {
            switch (value.*) {
                .float => |x| {
                    dest.* = @floatCast(x);
                },
                .integer => |x| {
                    dest.* = @floatFromInt(x);
                },
                else => return error.InvalidValueType,
            }
        },
        .bool => {
            switch (value.*) {
                .boolean => |b| {
                    dest.* = b;
                },
                else => return error.InvalidValueType,
            }
        },
        .pointer => |tinfo| {
            switch (tinfo.size) {
                .one => {
                    dest.* = try ctx.alloc.create(tinfo.child);
                    errdefer ctx.alloc.destroy(dest.*);
                    return setValue(ctx, tinfo.child, dest.*, value);
                },
                .slice => {},
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
                            for (ar.items, 0..) |_, ix| {
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
        .array => |tinfo| {
            switch (value.*) {
                .array => |b| {
                    if (b.items.len != tinfo.len) return error.InvalidArrayLength;
                    for (dest, 0..b.items.len) |*x, ix| {
                        try setValue(ctx, tinfo.child, x, &b.items[ix]);
                    }
                },
                else => return error.InvalidValueType,
            }
        },
        .@"struct" => {
            switch (value.*) {
                .table => |tab| {
                    try intoStruct(ctx, T, dest, tab);
                    ctx.alloc.destroy(tab);
                },
                else => return error.InvalidValueType,
            }
        },
        .optional => |tinfo| {
            dest.* = @as(tinfo.child, undefined);
            try setValue(ctx, tinfo.child, &dest.*.?, value);
        },
        .@"enum" => |tinfo| {
            switch (value.*) {
                .string => |s| {
                    inline for (tinfo.fields) |field| {
                        if (std.mem.eql(u8, field.name, s)) {
                            dest.* = @enumFromInt(field.value);
                            break;
                        }
                    } else {
                        return error.InvalidValueType;
                    }
                },
                else => return error.InvalidValueType,
            }
        },
        else => return error.NotSupportedFieldType,
    }
}

pub fn HashMap(comptime T: type) type {
    return struct {
        map: std.StringHashMap(T),

        pub fn tomlIntoStruct(ctx: *Context, table: *Table) !@This() {
            var map = std.StringHashMap(T).init(ctx.alloc);
            errdefer map.deinit();

            var it = table.iterator();
            while (it.next()) |entry| {
                var value: T = undefined;
                try setValue(ctx, T, &value, entry.value_ptr);

                const key: []u8 = try ctx.alloc.alloc(u8, entry.key_ptr.len);
                @memcpy(key, entry.key_ptr.*);
                try map.put(key, value);
            }

            return .{ .map = map };
        }
    };
}
