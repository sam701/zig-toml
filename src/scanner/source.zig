const std = @import("std");
const Allocator = std.mem.Allocator;
const Reader = std.io.AnyReader;

pub const Source = union(enum) {
    text: []const u8,
    reader: Reader,
};

pub const Value = struct {
    content: []const u8,
    allocated: bool = false,
};

pub const SourceAccessor = struct {
    source: Source,
    buffer: ?[]u8,
    input: []const u8,
    cursor: usize,

    capture_from_ix: ?usize = null,
    capture: ?std.ArrayList(u8) = null,
    allocator: std.mem.Allocator,

    pub const Error = Reader.Error;
    const Self = @This();

    pub fn init(source: Source, alloc: Allocator, buffer_size: usize) Allocator.Error!Self {
        var buffer: ?[]u8 = null;
        var input: []const u8 = undefined;
        var cursor: usize = undefined;
        switch (source) {
            .text => |txt| {
                input = txt;
                cursor = 0;
            },
            .reader => {
                buffer = try alloc.alloc(u8, buffer_size);
                input = buffer.?;
                cursor = buffer_size;
            },
        }
        return .{
            .source = source,
            .allocator = alloc,
            .buffer = buffer,
            .input = input,
            .cursor = cursor,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.buffer) |buf| {
            self.allocator.free(buf);
            self.buffer = null;
        }

        if (self.capture) |cap| {
            cap.deinit();
            self.capture = null;
            self.capture_from_ix = null;
        }
    }

    pub fn next(self: *Self) Error!?u8 {
        if (self.cursor >= self.input.len) {
            switch (self.source) {
                .text => return null,
                .reader => |reader| {
                    if (self.capture_from_ix) |ix| {
                        if (self.capture == null)
                            self.capture = std.ArrayList(u8).init(self.allocator);
                        try self.capture.?.appendSlice(self.input[ix..]);
                        self.capture_from_ix = 0;
                    }

                    const n = try reader.read(self.buffer.?);
                    if (n == 0) return null;
                    self.input = self.buffer.?[0..n];
                    self.cursor = 0;
                },
            }
        }

        std.debug.assert(self.cursor >= 0 and self.cursor < self.input.len);
        const char = self.input[self.cursor];
        self.cursor += 1;
        return char;
    }

    pub fn startValueCapture(self: *Self) void {
        self.capture_from_ix = self.cursor;
    }

    pub fn popCapturedValue(self: *Self) ?Value {
        const val = if (self.capture) |cap| {
            try cap.appendSlice(self.input[self.capture_from_ix.?..self.cursor]);
            Value{
                .content = try cap.toOwnedSlice(),
                .allocated = true,
            };
        } else if (self.capture_from_ix) |ix| {
            Value{
                .content = self.input[ix..self.cursor],
                .allocated = false,
            };
        } else {
            null;
        };

        self.capture_from_ix = null;
        self.capture = null;

        return val;
    }

    pub fn putBack(self: *Self) void {
        self.cursor -= 1;
    }
};

const test_alloc = std.testing.allocator;
const testing = std.testing;
test "text source: basic" {
    var sa = try SourceAccessor.init(Source{ .text = "ab" }, test_alloc, 4);
    try testing.expectEqual('a', try sa.next());
    try testing.expectEqual('b', try sa.next());
    try testing.expectEqual(null, try sa.next());
}

test "reader source: basic" {
    var s = std.io.fixedBufferStream("abcd");

    var sa = try SourceAccessor.init(Source{ .reader = s.reader().any() }, test_alloc, 2);
    defer sa.deinit();

    try testing.expectEqual('a', try sa.next());
    try testing.expectEqual('b', try sa.next());
    try testing.expectEqual('c', try sa.next());
    try testing.expectEqual('d', try sa.next());
    try testing.expectEqual(null, try sa.next());
}
