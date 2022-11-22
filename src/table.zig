const std = @import("std");
const parser = @import("./parser.zig");
const testing = std.testing;

const kv = @import("./key_value_pair.zig");
const Value = @import("./value.zig").Value;
const spaces = @import("./spaces.zig");

pub const Table = std.StringHashMap(Value);

fn setValue(ctx: *parser.Context, table: *Table, key: parser.String, value: Value) !void {
    var copiedKey = try ctx.alloc.alloc(u8, key.content.len);
    std.mem.copy(u8, copiedKey, key.content);
    try table.put(copiedKey, value);
    key.deinit(ctx.alloc);
}

fn handleKeyPair(ctx: *parser.Context, table: *Table, pair: *kv.KeyValuePair) !void {
    switch (pair.key) {
        .bare => |key| {
            try setValue(ctx, table, key, pair.value);
        },
        .dotted => |ar| {
            var current_table: *Table = table;
            for (ar) |key, ix| {
                if (ix == ar.len - 1) {
                    try setValue(ctx, current_table, key, pair.value);
                } else {
                    if (current_table.get(key.content)) |val| {
                        switch (val) {
                            .table => |tab| {
                                current_table = tab;
                            },
                            else => return error.FieldTypeRedifinition,
                        }
                    } else {
                        var new_table = try ctx.alloc.create(Table);
                        new_table.* = Table.init(ctx.alloc);

                        var new_value = Value{ .table = new_table };
                        try setValue(ctx, current_table, key, new_value);
                        current_table = new_table;
                    }
                }
            }
            ctx.alloc.free(ar);
        },
    }
}

pub fn parseTableContent(ctx: *parser.Context) !Table {
    var table = Table.init(ctx.alloc);

    spaces.skipSpacesAndLineBreaks(ctx);
    while (ctx.current() != null) {
        var pair = try kv.parse(ctx);
        try handleKeyPair(ctx, &table, &pair);
        spaces.skipSpacesAndLineBreaks(ctx);
    }

    return table;
}

pub fn parseInlineTable(ctx: *parser.Context) !?*Table {
    parser.consumeString(ctx, "{") catch return null;

    var table = try ctx.alloc.create(Table);
    table.* = Table.init(ctx.alloc);

    while (true) {
        spaces.skipSpaces(ctx);
        var pair = try kv.parse(ctx);
        try handleKeyPair(ctx, table, &pair);
        spaces.skipSpaces(ctx);
        parser.consumeString(ctx, ",") catch {
            try parser.consumeString(ctx, "}");
            break;
        };
    }

    return table;
}

pub fn deinitTable(table: *Table) void {
    var it = table.iterator();
    while (it.next()) |entry| {
        table.allocator.free(entry.key_ptr.*);
        entry.value_ptr.deinit(table.allocator);
    }
    table.deinit();
}

test "map" {
    var ctx = parser.testInput(
        \\  aa = "a1"
        \\
        \\    bb = 33
    );
    var m = try parseTableContent(&ctx);
    try testing.expect(m.count() == 2);
    try testing.expect(std.mem.eql(u8, m.get("aa").?.string, "a1"));
    try testing.expect(m.get("bb").?.integer == 33);
    deinitTable(&m);
}

test "inline table" {
    var ctx = parser.testInput("{ aa = 3, bb.cc = 4 }");
    var m = (try parseInlineTable(&ctx)).?;
    try testing.expect(m.count() == 2);
    try testing.expect(m.get("aa").?.integer == 3);
    try testing.expect(m.get("bb").?.table.get("cc").?.integer == 4);
    deinitTable(m);
    testing.allocator.destroy(m);
}
