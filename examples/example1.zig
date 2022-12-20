const std = @import("std");
const toml = @import("zig-toml");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const Address = struct {
    port: i64,
    host: []const u8,
};

const Config = struct {
    master: bool,
    expires_at: toml.DateTime,

    local: Address,
    peers: []const Address,
};

pub fn main() anyerror!void {
    var parser = toml.Parser(Config).init(allocator);
    defer parser.deinit();

    var config: Config = undefined;
    try parser.parseFile("./examples/example1.toml", &config);
    defer destroyConfig(&config);

    std.debug.print("local address: {s}:{}\n", .{ config.local.host, config.local.port });
    std.debug.print("peer0: {s}:{}\n", .{ config.peers[0].host, config.peers[0].port });
}

fn destroyConfig(c: *Config) void {
    allocator.free(c.local.host);
    allocator.free(c.peers[0].host);
    allocator.free(c.peers[1].host);
    allocator.free(c.peers);
}
