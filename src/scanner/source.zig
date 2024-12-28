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
                input.len = 0;
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
        if (self.cursor == 0) {
            // This is the case if this function is called before next().
            self.capture_from_ix = 0;
        } else if (self.input.len == 0) {
            // If this function is called before the buffer has been populated.
            self.capture_from_ix = 0;
        } else {
            self.capture_from_ix = self.cursor - 1;
        }
    }

    pub fn popCapturedValue(self: *Self) Allocator.Error!?Value {
        var val: ?Value = null;
        if (self.capture) |*cap| {
            try cap.appendSlice(self.input[self.capture_from_ix.?..self.cursor]);
            val = Value{
                .content = try cap.toOwnedSlice(),
                .allocated = true,
            };
        } else if (self.capture_from_ix) |ix| {
            val = Value{
                .content = self.input[ix..self.cursor],
                .allocated = false,
            };
        }

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

test "text source: capture in between 1" {
    var sa = try SourceAccessor.init(Source{ .text = "abcd" }, test_alloc, 4);

    try testing.expectEqual('a', try sa.next());
    try testing.expectEqual('b', try sa.next());
    sa.startValueCapture();

    try testing.expectEqual('c', try sa.next());

    var v = try sa.popCapturedValue();
    try testing.expectEqualSlices(u8, "bc", v.?.content);
    try testing.expect(!v.?.allocated);

    v = try sa.popCapturedValue();
    try testing.expect(v == null);
}

test "text source: capture in between 2" {
    var sa = try SourceAccessor.init(Source{ .text = "abcdef" }, test_alloc, 3);

    try testing.expectEqual('a', try sa.next());
    try testing.expectEqual('b', try sa.next());
    sa.startValueCapture();

    try testing.expectEqual('c', try sa.next());
    try testing.expectEqual('d', try sa.next());

    var v = try sa.popCapturedValue();
    try testing.expectEqualSlices(u8, "bcd", v.?.content);
    try testing.expect(!v.?.allocated);

    v = try sa.popCapturedValue();
    try testing.expect(v == null);
}

test "text source: capture beginning" {
    var sa = try SourceAccessor.init(Source{ .text = "abcd" }, test_alloc, 4);

    sa.startValueCapture();
    try testing.expectEqual('a', try sa.next());
    try testing.expectEqual('b', try sa.next());
    const v = try sa.popCapturedValue();

    try testing.expectEqualSlices(u8, "ab", v.?.content);
    try testing.expect(!v.?.allocated);
}

test "text source: capture ending" {
    var sa = try SourceAccessor.init(Source{ .text = "abcd" }, test_alloc, 4);

    try testing.expectEqual('a', try sa.next());
    try testing.expectEqual('b', try sa.next());
    try testing.expectEqual('c', try sa.next());
    sa.startValueCapture();
    try testing.expectEqual('d', try sa.next());
    const v = try sa.popCapturedValue();

    try testing.expectEqualSlices(u8, "cd", v.?.content);
    try testing.expect(!v.?.allocated);

    try testing.expect(try sa.next() == null);
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

test "reader source: capture in between" {
    var s = std.io.fixedBufferStream("abcd");

    var sa = try SourceAccessor.init(Source{ .reader = s.reader().any() }, test_alloc, 2);
    defer sa.deinit();

    try testing.expectEqual('a', try sa.next());
    try testing.expectEqual('b', try sa.next());
    sa.startValueCapture();

    try testing.expectEqual('c', try sa.next());

    var v = try sa.popCapturedValue();
    try testing.expectEqualSlices(u8, "bc", v.?.content);
    try testing.expect(v.?.allocated);
    test_alloc.free(v.?.content);

    v = try sa.popCapturedValue();
    try testing.expect(v == null);
}

test "reader source: capture beginning" {
    var s = std.io.fixedBufferStream("abcd");

    var sa = try SourceAccessor.init(Source{ .reader = s.reader().any() }, test_alloc, 2);
    defer sa.deinit();

    sa.startValueCapture();
    try testing.expectEqual('a', try sa.next());
    try testing.expectEqual('b', try sa.next());
    try testing.expectEqual('c', try sa.next());
    const v = try sa.popCapturedValue();

    try testing.expectEqualSlices(u8, "abc", v.?.content);
    try testing.expect(v.?.allocated);
    test_alloc.free(v.?.content);
}

test "reader source: capture ending" {
    var s = std.io.fixedBufferStream("abcd");

    var sa = try SourceAccessor.init(Source{ .reader = s.reader().any() }, test_alloc, 2);
    defer sa.deinit();

    try testing.expectEqual('a', try sa.next());
    try testing.expectEqual('b', try sa.next());
    sa.startValueCapture();
    try testing.expectEqual('c', try sa.next());
    try testing.expectEqual('d', try sa.next());
    const v = try sa.popCapturedValue();

    try testing.expectEqualSlices(u8, "bcd", v.?.content);
    try testing.expect(v.?.allocated);
    test_alloc.free(v.?.content);
}

test "reader source: capture ending 2" {
    var s = std.io.fixedBufferStream("abcde");

    var sa = try SourceAccessor.init(Source{ .reader = s.reader().any() }, test_alloc, 3);
    defer sa.deinit();

    try testing.expectEqual('a', try sa.next());
    try testing.expectEqual('b', try sa.next());
    try testing.expectEqual('c', try sa.next());
    sa.startValueCapture();
    try testing.expectEqual('d', try sa.next());
    try testing.expectEqual('e', try sa.next());
    const v = try sa.popCapturedValue();

    try testing.expectEqualSlices(u8, "cde", v.?.content);
    try testing.expect(v.?.allocated);
    test_alloc.free(v.?.content);
}
