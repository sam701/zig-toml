const std = @import("std");
const parser = @import("./parser.zig");
const testing = std.testing;

const kv = @import("./key_value_pair.zig");
const value = @import("./value.zig");
const spaces = @import("./spaces.zig");

fn parse(comptime HandlerContext: type, ctx: *parser.Context, handler_context: HandlerContext, comptime handler: fn (*parser.Context, HandlerContext, kv: *kv.KeyValuePair) anyerror!void) !void {
    spaces.skipSpacesAndLineBreaks(ctx);
    while (ctx.current() != null) {
        var pair = try kv.parse(ctx);
        try handler(ctx, handler_context, &pair);
        spaces.skipSpacesAndLineBreaks(ctx);
    }
}

pub const Map = std.StringHashMap(value.Value);

fn kvIntoMapHandler(ctx: *parser.Context, map: *Map, pair: *kv.KeyValuePair) !void {
    var copiedKey = try ctx.alloc.alloc(u8, pair.key.bare.content.len);
    std.mem.copy(u8, copiedKey, pair.key.bare.content);
    try map.put(copiedKey, pair.value);
    pair.key.deinit(ctx.alloc);
}
pub fn parseIntoMap(ctx: *parser.Context) !Map {
    var map = Map.init(ctx.alloc);
    try parse(*Map, ctx, &map, kvIntoMapHandler);
    return map;
}

pub fn deinitMap(map: *Map) void {
    var it = map.iterator();
    while (it.next()) |entry| {
        map.allocator.free(entry.key_ptr.*);
        entry.value_ptr.deinit(map.allocator);
    }
    map.deinit();
}

test "map" {
    var ctx = parser.testInput(
        \\  aa = "a1"
        \\
        \\    bb = 33
    );
    var m = try parseIntoMap(&ctx);
    try testing.expect(m.count() == 2);
    try testing.expect(std.mem.eql(u8, m.get("aa").?.string, "a1"));
    try testing.expect(m.get("bb").?.integer == 33);
    deinitMap(&m);
}

// TODO: handle dotted keys
