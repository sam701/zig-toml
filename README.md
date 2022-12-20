# zig-toml

Zig TOML (v1.0.0) parser package.

## Features
* [x] Integers
* [x] Hexadecimal, octal, and binary numbers
* [x] Floats
* [x] Booleans
* [x] Comments
* [x] Arrays
* [x] Tables
* [x] Array of Tables
* [x] Inline Table
* [x] Basic single-line strings
* [x] Literal single-line strings
* [x] String escapes
* [x] String unicode escapes
* [ ] Multi-line strings
* [ ] Literal multi-line strings
* [ ] Multi-line string trimming
* [x] Date
* [x] Time
* [x] Date-Time
* [x] Offset Date-Time

## Example
See [example1.zig](./examples/example1.zig)
```zig

// .... 

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
    var config: Config = undefined;
    var parser = toml.Parser(Config).init(allocator);
    defer parser.deinit();

    try parser.parseFile("./examples/example1.toml", &config);
    defer destroyConfig(&config);

    std.debug.print("local address: {s}:{}\n", .{ config.local.host, config.local.port });
    std.debug.print("peer0: {s}:{}\n", .{ config.peers[0].host, config.peers[0].port });
}
```