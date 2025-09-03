const std = @import("std");
const Allocator = std.mem.Allocator;
const Reader = std.Io.Reader;

const test_alloc = std.testing.allocator;
const testing = std.testing;
const expectEqual = std.testing.expectEqual;

pub const SourceLocation = struct {
    line: usize = 0,
    column: usize = 0,
    offset: usize = 0,

    fn update(self: *SourceLocation, char: u8) void {
        self.offset += 1;
        if (char == '\n') {
            self.line += 1;
            self.column = 0;
        } else {
            self.column += 1;
        }
    }
};

pub const Source = struct {
    reader: *std.Io.Reader,
    advance: bool = true,
    current: ?u8 = null,

    location: SourceLocation,

    pub const Error = Reader.Error || std.Io.Writer.Error || error{UnexpectedEndOfStream};

    const Self = @This();

    pub fn init(reader: *std.Io.Reader) error{OutOfMemory}!Self {
        return .{
            .reader = reader,
            .location = .{},
        };
    }

    pub fn next(self: *Self) Error!?u8 {
        if (!self.advance) {
            self.advance = true;
            return self.current;
        }

        if (self.reader.takeByte()) |v| {
            if (self.current) |pr| {
                self.location.update(pr);
            }

            self.current = v;

            return v;
        } else |err| {
            return if (err == error.EndOfStream) null else err;
        }
    }

    pub fn mustNext(self: *Self) Error!u8 {
        if (try self.next()) |v| {
            return v;
        } else {
            return error.UnexpectedEndOfStream;
        }
    }

    pub fn prev(self: *Self) void {
        self.advance = false;
    }
};

pub const FixedInput = struct {
    reader: Reader,
    source: Source,

    pub fn init(content: []const u8) *FixedInput {
        var sb = test_alloc.create(FixedInput) catch unreachable;
        sb.reader = Reader.fixed(content);
        sb.source = Source.init(&sb.reader) catch unreachable;
        return sb;
    }
    pub fn deinit(self: *FixedInput) void {
        std.testing.allocator.destroy(self);
    }
};

test "basic" {
    var sb = FixedInput.init("ab");
    defer sb.deinit();
    var source = &sb.source;
    try expectEqual('a', try source.next());
    try expectEqual('b', try source.next());
    try expectEqual(null, try source.next());
}

test SourceLocation {
    var sb = FixedInput.init("ab\ncdef");
    defer sb.deinit();

    try expectEqual('a', try sb.source.next());
    try expectEqual('b', try sb.source.next());
    try expectEqual('\n', try sb.source.next());
    try expectEqual('c', try sb.source.next());
    try std.testing.expectEqual(SourceLocation{ .offset = 3, .line = 1, .column = 0 }, sb.source.location);

    try expectEqual('d', try sb.source.next());
    try expectEqual('e', try sb.source.next());
    try std.testing.expectEqual(SourceLocation{ .offset = 5, .line = 1, .column = 2 }, sb.source.location);
}
