const std = @import("std");
const Allocator = std.mem.Allocator;
const Reader = std.io.AnyReader;

const test_alloc = std.testing.allocator;
const testing = std.testing;
const expectEqual = std.testing.expectEqual;

pub const Source = union(enum) {
    text: []const u8,
    reader: Reader,
};

pub const Value = struct {
    content: []const u8,
    allocated: bool = false,

    pub fn deinit(self: *@This(), alloc: Allocator) void {
        if (self.allocated) {
            alloc.free(self.content);
            self.content = undefined;
        }
    }

    pub fn popAllocated(self: *@This(), alloc: Allocator) Allocator.Error![]const u8 {
        if (self.allocated) {
            self.allocated = false;
            return self.content;
        } else {
            return alloc.dupe(u8, self.content);
        }
    }
};

test "value pop 1" {
    var v = Value{
        .content = "abc",
        .allocated = true,
    };

    const p = try v.popAllocated(test_alloc);
    try expectEqual(v.content, p);
}

test "value pop 2" {
    var v = Value{
        .content = "abc",
        .allocated = false,
    };

    const p = try v.popAllocated(test_alloc);
    try testing.expectEqualSlices(u8, v.content, p);
    try testing.expect(v.content.ptr != p.ptr);

    test_alloc.free(p);
}

pub const SourceAccessor = struct {
    source: Source,
    buffer: ?[]u8,
    input: []const u8,
    cursor: usize,

    capture_from_ix: ?usize = null,
    capture: ?std.ArrayList(u8) = null,
    allocator: std.mem.Allocator,

    line_number: u64 = 0,
    line_start_position: usize = 0,
    total_byte_position: u64 = 0,

    pub const Error = error{ReaderError} || Allocator.Error;
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

    fn ensureBufferLoaded(self: *Self) Error!void {
        if (self.cursor < self.input.len) return;
        switch (self.source) {
            .text => {},
            .reader => |reader| {
                if (self.capture_from_ix) |ix| {
                    if (self.capture == null)
                        self.capture = std.ArrayList(u8).init(self.allocator);
                    try self.capture.?.appendSlice(self.input[ix..]);
                    self.capture_from_ix = 0;
                }

                const n = reader.read(self.buffer.?) catch return error.ReaderError;
                self.input = self.buffer.?[0..n];
                self.cursor = 0;
            },
        }
    }

    pub fn current(self: *Self) Error!?u8 {
        try self.ensureBufferLoaded();
        if (self.cursor >= self.input.len) return null;
        return self.input[self.cursor];
    }

    pub fn next(self: *Self) Error!?u8 {
        self.cursor += 1;
        const char = try self.current();

        self.total_byte_position += 1;
        if (char == '\n') {
            self.line_number += 1;
            self.line_start_position = self.total_byte_position + 1;
        }
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
            self.capture_from_ix = self.cursor;
        }
    }

    pub fn popCapturedValue(self: *Self, trim_chars: usize) Allocator.Error!Value {
        var val: Value = undefined;
        if (self.capture) |*cap| {
            try cap.appendSlice(self.input[self.capture_from_ix.? .. self.cursor + 1]);
            val = Value{
                .content = try cap.toOwnedSlice(),
                .allocated = true,
            };
        } else if (self.capture_from_ix) |ix| {
            val = Value{
                .content = self.input[ix .. self.cursor + 1],
                .allocated = false,
            };
        } else {
            @panic("startValueCapture was not called");
        }

        val.content = val.content[0 .. val.content.len - trim_chars];

        self.capture_from_ix = null;
        self.capture = null;

        return val;
    }

    /// Starts at 1.
    pub fn getLine(self: *const Self) u64 {
        return self.line_number;
    }
    /// Starts at 1.
    pub fn getColumn(self: *const Self) u64 {
        return self.total_byte_position -% self.line_start_position;
    }
    /// Starts at 0. Measures the byte offset since the start of the input.
    pub fn getByteOffset(self: *const Self) u64 {
        return self.total_byte_position;
    }
};

test "text source: basic" {
    var sa = try SourceAccessor.init(Source{ .text = "ab" }, test_alloc, 4);
    try expectEqual('a', try sa.current());
    try expectEqual('b', try sa.next());
    try expectEqual(null, try sa.next());
}

test "text source: capture in between 1" {
    var sa = try SourceAccessor.init(Source{ .text = "abcd" }, test_alloc, 4);

    try expectEqual('a', try sa.current());
    try expectEqual('b', try sa.next());
    sa.startValueCapture();

    try expectEqual('c', try sa.next());

    const v = try sa.popCapturedValue(0);
    try testing.expectEqualSlices(u8, "bc", v.content);
    try testing.expect(!v.allocated);
}

test "text source: capture in between 2" {
    var sa = try SourceAccessor.init(Source{ .text = "abcdef" }, test_alloc, 3);

    try expectEqual('a', try sa.current());
    try expectEqual('b', try sa.next());
    sa.startValueCapture();

    try expectEqual('c', try sa.next());
    try expectEqual('d', try sa.next());

    const v = try sa.popCapturedValue(0);
    try testing.expectEqualSlices(u8, "bcd", v.content);
    try testing.expect(!v.allocated);
}

test "text source: capture beginning" {
    var sa = try SourceAccessor.init(Source{ .text = "abcd" }, test_alloc, 4);

    sa.startValueCapture();
    try expectEqual('a', try sa.current());
    try expectEqual('b', try sa.next());
    const v = try sa.popCapturedValue(0);

    try testing.expectEqualSlices(u8, "ab", v.content);
    try testing.expect(!v.allocated);
}

test "text source: capture ending" {
    var sa = try SourceAccessor.init(Source{ .text = "abcd" }, test_alloc, 4);

    try expectEqual('a', try sa.current());
    try expectEqual('b', try sa.next());
    try expectEqual('c', try sa.next());
    sa.startValueCapture();
    try expectEqual('d', try sa.next());
    const v = try sa.popCapturedValue(0);

    try testing.expectEqualSlices(u8, "cd", v.content);
    try testing.expect(!v.allocated);

    try testing.expect(try sa.next() == null);
}

test "reader source: basic" {
    var s = std.io.fixedBufferStream("abcd");

    var sa = try SourceAccessor.init(Source{ .reader = s.reader().any() }, test_alloc, 2);
    defer sa.deinit();

    try expectEqual('a', try sa.current());
    try expectEqual('b', try sa.next());
    try expectEqual('c', try sa.next());
    try expectEqual('d', try sa.next());
    try expectEqual(null, try sa.next());
}

test "reader source: capture in between" {
    var s = std.io.fixedBufferStream("abcd");

    var sa = try SourceAccessor.init(Source{ .reader = s.reader().any() }, test_alloc, 2);
    defer sa.deinit();

    try expectEqual('a', try sa.current());
    try expectEqual('b', try sa.next());
    sa.startValueCapture();

    try expectEqual('c', try sa.next());

    const v = try sa.popCapturedValue(0);
    try testing.expectEqualSlices(u8, "bc", v.content);
    try testing.expect(v.allocated);
    test_alloc.free(v.content);
}

test "reader source: capture beginning" {
    var s = std.io.fixedBufferStream("abcd");

    var sa = try SourceAccessor.init(Source{ .reader = s.reader().any() }, test_alloc, 2);
    defer sa.deinit();

    sa.startValueCapture();
    try expectEqual('a', try sa.current());
    try expectEqual('b', try sa.next());
    try expectEqual('c', try sa.next());
    const v = try sa.popCapturedValue(0);

    try testing.expectEqualSlices(u8, "abc", v.content);
    try testing.expect(v.allocated);
    test_alloc.free(v.content);
}

test "reader source: capture ending" {
    var s = std.io.fixedBufferStream("abcd");

    var sa = try SourceAccessor.init(Source{ .reader = s.reader().any() }, test_alloc, 2);
    defer sa.deinit();

    try expectEqual('a', try sa.current());
    try expectEqual('b', try sa.next());
    sa.startValueCapture();
    try expectEqual('c', try sa.next());
    try expectEqual('d', try sa.next());
    const v = try sa.popCapturedValue(0);

    try testing.expectEqualSlices(u8, "bcd", v.content);
    try testing.expect(v.allocated);
    test_alloc.free(v.content);
}

test "reader source: capture ending 2" {
    var s = std.io.fixedBufferStream("abcde");

    var sa = try SourceAccessor.init(Source{ .reader = s.reader().any() }, test_alloc, 3);
    defer sa.deinit();

    try expectEqual('a', try sa.current());
    try expectEqual('b', try sa.next());
    try expectEqual('c', try sa.next());
    sa.startValueCapture();
    try expectEqual('d', try sa.next());
    try expectEqual('e', try sa.next());
    const v = try sa.popCapturedValue(0);

    try testing.expectEqualSlices(u8, "cde", v.content);
    try testing.expect(v.allocated);
    test_alloc.free(v.content);
}

test "reader source: current" {
    var s = std.io.fixedBufferStream("abcde");

    var sa = try SourceAccessor.init(Source{ .reader = s.reader().any() }, test_alloc, 3);
    defer sa.deinit();

    try expectEqual('a', try sa.current());
    try expectEqual('b', try sa.next());
    try expectEqual('b', try sa.current());
    try expectEqual('c', try sa.next());
    try expectEqual('c', try sa.current());
    try expectEqual('d', try sa.next());
    try expectEqual('d', try sa.current());
    try expectEqual('e', try sa.next());
    try expectEqual('e', try sa.current());
}

test "diagnostics" {
    var sa = try SourceAccessor.init(Source{ .text = "ab\ncde" }, test_alloc, 3);

    try expectEqual('a', try sa.current());
    try expectEqual('b', try sa.next());
    try expectEqual('\n', try sa.next());
    try expectEqual('\n', try sa.current());
    try expectEqual('c', try sa.next());
    try expectEqual(1, sa.line_number);
    try expectEqual(3, sa.total_byte_position);
    try expectEqual(3, sa.line_start_position);
    try expectEqual(3, sa.cursor);
    try expectEqual(0, sa.getColumn());

    try expectEqual('d', try sa.next());
    try expectEqual('d', try sa.current());
    try expectEqual(1, sa.line_number);
    try expectEqual(4, sa.total_byte_position);
    try expectEqual(3, sa.line_start_position);
    try expectEqual(4, sa.cursor);
    try expectEqual(1, sa.getColumn());
}
