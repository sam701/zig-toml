const std = @import("std");
const parser = @import("./parser.zig");
const testing = std.testing;

const string = @import("./string.zig");
const integer = @import("./integer.zig");
const float = @import("./float.zig");
const array = @import("./array.zig");
const tablepkg = @import("./table.zig");
const datetime = @import("./datetime.zig");
const Table = tablepkg.Table;

pub const ValueList = std.ArrayList(Value);

pub const Value = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    date: datetime.Date,
    time: datetime.Time,

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
            .integer, .float => |x| std.debug.print("{}", .{x}),
            .date => |x| std.debug.print("{}-{}-{}", .{ x.year, x.month, x.day }),
            .time => |x| std.debug.print("{}:{}:{}.{}", .{ x.hour, x.minute, x.second, x.nanosecond }),
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
    } else if (try array.parse(ctx)) |ar| {
        return Value{ .array = ar };
    } else if (try parseScalar(ctx)) |x| {
        return x;
    }
    return error.CannotParseValue;
}

fn interpretBool(str: []const u8) ?bool {
    if (std.mem.eql(u8, "true", str)) return true;
    if (std.mem.eql(u8, "false", str)) return false;
    return null;
}

fn isScalarChar(c: u8) bool {
    return switch (c) {
        ' ', ',', '\t', '\r', '\n', ']', '}' => false,
        else => true,
    };
}

fn parseScalar(ctx: *parser.Context) !?Value {
    var sc = ctx.*;
    var txt = parser.takeWhile(&sc, isScalarChar);
    var val: Value = undefined;
    if (integer.interpret(txt)) |x| {
        val = Value{ .integer = x };
    } else if (float.interpret(txt)) |x| {
        val = Value{ .float = x };
    } else if (interpretBool(txt)) |x| {
        val = Value{ .boolean = x };
    } else if (try datetime.interpretDate(txt)) |x| {
        val = Value{ .date = x };
    } else if (try datetime.interpretTime(txt)) |x| {
        val = Value{ .time = x };
    } else {
        return null;
    }
    ctx.advance(ctx.input.len - sc.input.len);
    return val;
}

fn testScalar(txt: []const u8, expected: Value) !void {
    var ctx = parser.testInput(txt);
    var parsed = try parseScalar(&ctx);
    try testing.expect(std.meta.eql(parsed.?, expected));
}

test "scalar" {
    try testScalar("123", Value{ .integer = 123 });
    try testScalar("123.44", Value{ .float = 123.44 });
    try testScalar("true", Value{ .boolean = true });
    try testScalar("false", Value{ .boolean = false });
    try testScalar("2022-07-03", Value{ .date = datetime.Date{ .year = 2022, .month = 7, .day = 3 } });
}

test "value string" {
    var ctx = parser.testInput(
        \\"abc"
    );
    var val = try parse(&ctx);
    try testing.expect(std.mem.eql(u8, val.string, "abc"));
    val.deinit(ctx.alloc);
}

test "bool" {
    try testing.expect(interpretBool("123") == null);
    try testing.expect(interpretBool("true").? == true);
    try testing.expect(interpretBool("false").? == false);

    var ctx = parser.testInput("true");
    var val = try parse(&ctx);
    try testing.expect(val.boolean == true);
}

// TODO: date time
