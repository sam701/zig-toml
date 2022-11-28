const std = @import("std");

const parser = @import("./parser.zig");
const table = @import("./table.zig");
pub const Table = table.Table;
const struct_mapping = @import("./struct_mapping.zig");

pub fn parseIntoTable(input: []const u8, alloc: std.mem.Allocator) !Table {
    var ctx = parser.Context{
        .input = input,
        .alloc = alloc,
    };
    return table.parseRootTable(&ctx);
}

pub fn parseIntoStruct(input: []const u8, ctx: *struct_mapping.Context, comptime T: type, dest: *T) !void {
    var map = try parseIntoTable(input, ctx.alloc);
    try struct_mapping.intoStruct(ctx, T, dest, &map);
}

pub const deinitTable = table.deinitTable;
