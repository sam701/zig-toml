const std = @import("std");
const parser = @import("./parser.zig");
const testing = std.testing;

const kv = @import("./key_value_pair.zig");
const keypkg = @import("./key.zig");
const Value = @import("./value.zig").Value;
const ValueList = @import("./value.zig").ValueList;
const spaces = @import("./spaces.zig");
const comment = @import("./comment.zig");

pub const Table = std.StringHashMap(Value);

fn setValue(ctx: *parser.Context, table: *Table, key: parser.String, value: Value) !void {
    defer key.deinit(ctx.alloc);
    var copiedKey = try ctx.alloc.alloc(u8, key.content.len);
    errdefer ctx.alloc.free(copiedKey);
    std.mem.copy(u8, copiedKey, key.content);
    try table.put(copiedKey, value);
}

fn handleKeyPair(ctx: *parser.Context, table: *Table, pair: *kv.KeyValuePair) !void {
    var buf: [1]parser.String = undefined;
    var chain = pair.key.asChain(&buf);

    var current_table: *Table = table;
    for (chain) |link, ix| {
        if (ix == chain.len - 1) {
            try setValue(ctx, current_table, link, pair.value);
        } else {
            current_table = try tableAdvance(ctx, current_table, link, false);
        }
    }
    if (pair.key == .dotted) {
        ctx.alloc.free(pair.key.dotted);
    }
}

pub fn parseRootTable(ctx: *parser.Context) !Table {
    var table = Table.init(ctx.alloc);
    errdefer deinitTableRecursively(&table);
    try parseTableContent(ctx, &table);
    return table;
}

fn parseTableContent(ctx: *parser.Context, root_table: *Table) !void {
    var current_table = root_table;
    comment.skipSpacesAndComments(ctx);
    while (ctx.current() != null) {
        if (try parseTableHeader(ctx, &table_array_delimiters)) |header_key| {
            // TODO: set path
            current_table = try createTable(ctx, root_table, header_key, LeafType.table_array);
        } else if (try parseTableHeader(ctx, &table_delimiters)) |header_key| {
            // TODO: set path
            current_table = try createTable(ctx, root_table, header_key, LeafType.table);
        } else {
            var pair = try kv.parse(ctx);
            try handleKeyPair(ctx, current_table, &pair);
        }
        comment.skipSpacesAndComments(ctx);
    }
}

fn createTable(ctx: *parser.Context, root_table: *Table, key: keypkg.Key, leaf: LeafType) !*Table {
    var buf: [1]parser.String = undefined;
    var chain = key.asChain(&buf);

    var current_table = root_table;
    for (chain) |ckey, ix| {
        var new_array_item = ix == chain.len - 1 and leaf == LeafType.table_array;
        current_table = try tableAdvance(ctx, current_table, ckey, new_array_item);
    }
    key.deinit(ctx.alloc);
    return current_table;
}

const LeafType = enum(u8) {
    table,
    table_array,
};

fn tableAdvance(ctx: *parser.Context, table: *Table, key: parser.String, new_array_item: bool) !*Table {
    if (table.get(key.content)) |val| {
        switch (val) {
            .table => |tab| return tab,
            .array => |ar| {
                if (new_array_item) {
                    var new_table = try ctx.alloc.create(Table);
                    errdefer ctx.alloc.destroy(new_table);
                    new_table.* = Table.init(ctx.alloc);
                    var new_value = Value{ .table = new_table };
                    try ar.append(new_value);
                    return new_table;
                } else {
                    switch (ar.items[ar.items.len - 1]) {
                        .table => |tab| return tab,
                        else => return error.FieldTypeRedifinition,
                    }
                }
            },
            else => return error.FieldTypeRedifinition,
        }
    } else {
        var new_table = try ctx.alloc.create(Table);
        errdefer ctx.alloc.destroy(new_table);
        new_table.* = Table.init(ctx.alloc);
        var new_value = Value{ .table = new_table };

        if (new_array_item) {
            var list = try ctx.alloc.create(ValueList);
            errdefer ctx.alloc.destroy(list);
            list.* = ValueList.init(ctx.alloc);
            try list.append(new_value);
            new_value = Value{ .array = list };
        }
        try setValue(ctx, table, key, new_value);

        key.deinit(ctx.alloc);
        return new_table;
    }
}

const Delimiters = struct {
    start: []const u8,
    end: []const u8,
};

const table_delimiters = Delimiters{ .start = "[", .end = "]" };
const table_array_delimiters = Delimiters{ .start = "[[", .end = "]]" };

fn parseTableHeader(ctx: *parser.Context, delimiters: *const Delimiters) !?keypkg.Key {
    parser.consumeString(ctx, delimiters.start) catch return null;
    spaces.skipSpaces(ctx);
    var k = try keypkg.parse(ctx);
    spaces.skipSpaces(ctx);
    try parser.consumeString(ctx, delimiters.end);
    spaces.skipSpaces(ctx);
    try spaces.consumeNewLine(ctx);
    return k;
}

test "table header bare" {
    var ctx = parser.testInput("[t1]\n");
    var k = (try parseTableHeader(&ctx, &table_delimiters)).?;

    try testing.expect(std.mem.eql(u8, k.bare.content, "t1"));
    k.deinit(ctx.alloc);
}

test "table header dotted" {
    var ctx = parser.testInput("[ aa. bb ]\n");
    var k = (try parseTableHeader(&ctx, &table_delimiters)).?;

    try testing.expect(k.dotted.len == 2);
    try testing.expect(std.mem.eql(u8, k.dotted[0].content, "aa"));
    try testing.expect(std.mem.eql(u8, k.dotted[1].content, "bb"));
    k.deinit(ctx.alloc);
}

pub fn parseInlineTable(ctx: *parser.Context) !?*Table {
    parser.consumeString(ctx, "{") catch return null;

    var table = try ctx.alloc.create(Table);
    errdefer ctx.alloc.destroy(table);

    table.* = Table.init(ctx.alloc);
    errdefer deinitTableRecursively(table);

    while (true) {
        spaces.skipSpaces(ctx);
        var pair = try kv.parse(ctx);
        errdefer pair.deinit(ctx.alloc);

        try handleKeyPair(ctx, table, &pair);
        spaces.skipSpaces(ctx);
        parser.consumeString(ctx, ",") catch {
            try parser.consumeString(ctx, "}");
            break;
        };
    }

    return table;
}

pub fn deinitTableRecursively(table: *Table) void {
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
    deinitTableRecursively(&m);
}

test "inline table" {
    var ctx = parser.testInput("{ aa = 3, bb.cc = 4 }");
    var m = (try parseInlineTable(&ctx)).?;
    try testing.expect(m.count() == 2);
    try testing.expect(m.get("aa").?.integer == 3);
    try testing.expect(m.get("bb").?.table.get("cc").?.integer == 4);
    deinitTableRecursively(m);
    testing.allocator.destroy(m);
}

test "error in table" {
    var ctx = parser.testInput(
        \\aa = "test"
        \\bb = 4u
    );
    try testing.expectError(error.CannotParseValue, parseRootTable(&ctx));
    try testing.expectEqual(parser.Position{ .line = 2, .pos = 6 }, ctx.position);
}

test "error in inline table" {
    var ctx = parser.testInput(
        \\{aa = 3, bb = 4u}
    );
    try testing.expectError(error.CannotParseValue, parseInlineTable(&ctx));
    try testing.expectEqual(parser.Position{ .line = 1, .pos = 15 }, ctx.position);
}
