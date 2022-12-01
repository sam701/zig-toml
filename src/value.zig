const std = @import("std");
const parser = @import("./parser.zig");
const testing = std.testing;

const string = @import("./string.zig");
const integer = @import("./integer.zig");
const array = @import("./array.zig");
const tablepkg = @import("./table.zig");
const Table = tablepkg.Table;

pub const ValueList = std.ArrayList(Value);

pub const Value = union(enum) {
    string: []const u8,
    integer: i64,
    boolean: bool,
    array: *ValueList,
    table: *Table,

    pub fn deinit(self: Value, alloc: std.mem.Allocator) void {
        switch (self) {
            .string => |str| alloc.free(str),
            .array => |ar| {
                for (ar.items) |element| {
                    element.deinit(alloc);
                }
                ar.deinit();
                alloc.destroy(ar);
            },
            .table => |table| {
                var it = table.iterator();
                while (it.next()) |entry| {
                    alloc.free(entry.key_ptr.*);
                    entry.value_ptr.deinit(alloc);
                }
                table.deinit();
                alloc.destroy(table);
            },
            else => {},
        }
    }

    pub fn print(self: *const Value) void {
        switch (self.*) {
            .string => |x| std.debug.print("\"{s}\"", .{x}),
            .integer => |x| std.debug.print("{}", .{x}),
            .array => |ar| {
                std.debug.print("[", .{});
                for (ar.items) |x| {
                    x.print();
                    std.debug.print(",", .{});
                }
                std.debug.print("]", .{});
            },
            .table => |tab| {
                std.debug.print("{{", .{});
                var it = tab.iterator();
                while (it.next()) |x| {
                    std.debug.print("{s}:", .{x.key_ptr.*});
                    x.value_ptr.print();
                    std.debug.print(",", .{});
                }
                std.debug.print("}}", .{});
            },
        }
    }
};

pub fn parse(ctx: *parser.Context) anyerror!Value {
    if (try string.parse(ctx)) |str| {
        return Value{ .string = str };
    } else if (try tablepkg.parseInlineTable(ctx)) |table| {
        return Value{ .table = table };
    } else if (parseBool(ctx)) |b| {
        return Value{ .boolean = b };
    } else if (try integer.parse(ctx)) |int| {
        return Value{ .integer = int };
    } else if (try array.parse(ctx)) |ar| {
        return Value{ .array = ar };
    }
    return error.CannotParseValue;
}

fn parseBool(ctx: *parser.Context) ?bool {
    if (parser.consumeString(ctx, "true")) {
        return true;
    } else |_| if (parser.consumeString(ctx, "false")) {
        return false;
    } else |_| {
        return null;
    }
}

test "value string" {
    var ctx = parser.testInput(
        \\"abc"
    );
    var val = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, val.string, "abc"));
    val.deinit(ctx.alloc);
}

test "value integer" {
    var ctx = parser.testInput(
        \\123
    );
    var val = try parse(&ctx);
    try testing.expect(val.integer == 123);
}

test "bool" {
    var ctx = parser.testInput("123");
    try testing.expect(parseBool(&ctx) == null);

    ctx = parser.testInput("true");
    try testing.expect(parseBool(&ctx).? == true);

    ctx = parser.testInput("false");
    try testing.expect(parseBool(&ctx).? == false);

    ctx = parser.testInput("true");
    var val = try parse(&ctx);
    try testing.expect(val.boolean == true);
}

// TODO: floats
// TODO: date
// TODO: date time
