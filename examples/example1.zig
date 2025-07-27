const std = @import("std");
const toml = @import("toml");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const Address = struct {
    port: i64,
    host: []const u8,
};

const Config = struct {
    master: bool,
    expires_at: toml.DateTime,
    description: ?[]const u8 = null,

    local: *Address,
    peers: []const Address,
};

pub fn main() anyerror!void {
    var parser = toml.Parser(Config).init(allocator);
    defer parser.deinit();

    var result = try parser.parseFile("./examples/example1.toml");
    defer result.deinit();

    const config = result.value;
    if (config.description) |desc| {
        std.debug.print("{s}\nlocal address: {s}:{}\n", .{ desc, config.local.host, config.local.port });
    }
    std.debug.print("peer0: {s}:{}\n", .{ config.peers[0].host, config.peers[0].port });
}
