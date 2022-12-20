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
* [ ] Multi-line string leading space trimming
* [x] Date
* [x] Time
* [x] Date-Time
* [x] Offset Date-Time
* [x] Mapping to structs
* [x] Mapping to slices
* [ ] Mapping to arrays
* [x] Mapping to pointers
* [ ] Mapping to integer and floats with lower bit number than defined by TOML, i.e. `i16`, `f32`.
* [ ] Mapping to optional fields

## Example
See [`example1.zig`](./examples/example1.zig) for the complete code that parses [`example.toml`](./examples/example1.toml)

Run it with `zig build examples`
```zig
// .... 

const Address = struct {
    port: i64,
    host: []const u8,
};

const Config = struct {
    master: bool,
    expires_at: toml.DateTime,
    description: []const u8,

    local: *Address,
    peers: []const Address,
};

pub fn main() anyerror!void {
    var parser = toml.Parser(Config).init(allocator);
    defer parser.deinit();

    var config: Config = undefined;
    try parser.parseFile("./examples/example1.toml", &config);
    defer destroyConfig(&config);

    std.debug.print("{s}\nlocal address: {s}:{}\n", .{ config.description, config.local.host, config.local.port });
    std.debug.print("peer0: {s}:{}\n", .{ config.peers[0].host, config.peers[0].port });
}
```

## Error Handling
TODO

## License
MIT