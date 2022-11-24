const std = @import("std");
const parser = @import("./parser.zig");
const testing = std.testing;

const kv = @import("./key_value_pair.zig");
const keypkg = @import("./key.zig");
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

pub fn parseRootTable(ctx: *parser.Context) !Table {
    var table = Table.init(ctx.alloc);
    try parseTableContent(ctx, &table);
    return table;
}

fn parseTableContent(ctx: *parser.Context, root_table: *Table) !void {
    var current_table = root_table;
    while (ctx.current() != null) {
        spaces.skipSpacesAndLineBreaks(ctx);
        if (try parseTableHeader(ctx)) |header_key| {
            // TODO: set path
            current_table = try createTable(ctx, root_table, header_key);
        } else {
            var pair = try kv.parse(ctx);
            try handleKeyPair(ctx, current_table, &pair);
        }
    }
}

fn createTable(ctx: *parser.Context, root_table: *Table, key: keypkg.Key) !*Table {
    var buf: [1]parser.String = undefined;
    var chain = key.asChain(&buf);

    var current_table = root_table;
    for (chain) |ckey| {
        if (current_table.get(ckey.content)) |value| {
            switch (value) {
                .table => |tab| {
                    current_table = tab;
                },
                else => return error.FieldTypeRedifinition,
            }
        } else {
            var new_table = try ctx.alloc.create(Table);
            new_table.* = Table.init(ctx.alloc);

            var tab_key = try ctx.alloc.alloc(u8, ckey.content.len);
            std.mem.copy(u8, tab_key, ckey.content);
            try current_table.put(tab_key, Value{ .table = new_table });
            current_table = new_table;
        }
    }
    return current_table;
}

fn parseTableHeader(ctx: *parser.Context) !?keypkg.Key {
    parser.consumeString(ctx, "[") catch return null;
    spaces.skipSpaces(ctx);
    var k = try keypkg.parse(ctx);
    spaces.skipSpaces(ctx);
    try parser.consumeString(ctx, "]");
    spaces.skipSpaces(ctx);
    try spaces.consumeNewLine(ctx);
    return k;
}

test "table header bare" {
    var ctx = parser.testInput("[t1]\n");
    var k = (try parseTableHeader(&ctx)).?;

    try testing.expect(std.mem.eql(u8, k.bare.content, "t1"));
    k.deinit(ctx.alloc);
}

test "table header dotted" {
    var ctx = parser.testInput("[ aa. bb ]\n");
    var k = (try parseTableHeader(&ctx)).?;

    try testing.expect(k.dotted.len == 2);
    try testing.expect(std.mem.eql(u8, k.dotted[0].content, "aa"));
    try testing.expect(std.mem.eql(u8, k.dotted[1].content, "bb"));
    k.deinit(ctx.alloc);
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

test "table content" {
    var ctx = parser.testInput(
        \\  aa = "a1"
        \\
        \\    bb = 33
    );
    var m = try parseRootTable(&ctx);
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
