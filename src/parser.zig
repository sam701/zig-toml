const std = @import("std");
const testing = std.testing;

pub const Position = struct {
    pos: usize,
    line: usize,

    fn next(self: *Position, current_char: u8) void {
        if (current_char == '\n') {
            self.line += 1;
            self.pos = 1;
        } else {
            self.pos += 1;
        }
    }
};

pub const Context = struct {
    input: []const u8,
    alloc: std.mem.Allocator,
    position: Position = Position{ .pos = 1, .line = 1 },

    pub fn current(self: *const Context) ?u8 {
        if (self.input.len == 0) {
            return null;
        } else {
            return self.input[0];
        }
    }

    pub fn next(self: *Context) ?u8 {
        if (self.input.len == 0) return null;
        self.position.next(self.input[0]);
        self.input = self.input[1..];
        if (self.input.len == 0) return null;
        return self.input[0];
    }
};

test "next" {
    var ctx = Context{
        .input = "ab\ncd",
        .alloc = testing.allocator,
    };

    try testing.expect(ctx.position.pos == 1);
    try testing.expect(ctx.position.line == 1);
    try testing.expect(ctx.next().? == 'b');
    try testing.expect(ctx.position.pos == 2);
    try testing.expect(ctx.position.line == 1);
    try testing.expect(ctx.current().? == 'b');
    _ = ctx.next();
    try testing.expect(ctx.position.pos == 3);
    try testing.expect(ctx.position.line == 1);
    try testing.expect(ctx.current().? == '\n');
    _ = ctx.next();
    try testing.expect(ctx.position.pos == 1);
    try testing.expect(ctx.position.line == 2);
    try testing.expect(ctx.current().? == 'c');
}

pub fn takeWhile(ctx: *Context, comptime tester: fn (u8) bool) []const u8 {
    var origin = ctx.input;
    var copt = ctx.current();
    while (copt) |c| {
        if (tester(c)) {
            copt = ctx.next();
        } else {
            break;
        }
    }
    return origin[0 .. origin.len - ctx.input.len];
}

pub fn testInput(input: []const u8) Context {
    return Context{
        .input = input,
        .alloc = testing.allocator,
    };
}

fn isA(x: u8) bool {
    return x == 'a';
}

test "takeWhile 1" {
    var ctx = testInput("aaabc");
    const a3 = takeWhile(&ctx, isA);
    try testing.expect(std.mem.eql(u8, a3, "aaa"));
    try testing.expect(ctx.current().? == 'b');
}

test "takeWhile 2" {
    var ctx = testInput("aaa");
    const a3 = takeWhile(&ctx, isA);
    try testing.expect(std.mem.eql(u8, a3, "aaa"));
    try testing.expect(ctx.current() == null);
}

pub const String = struct {
    content: []const u8,
    allocated: bool,

    pub fn fromSlice(s: []const u8) String {
        return String{
            .content = s,
            .allocated = false,
        };
    }

    pub fn fromList(alloc: std.mem.Allocator, l: *std.ArrayListUnmanaged(u8)) String {
        return String{
            .content = l.toOwnedSlice(alloc),
            .allocated = true,
        };
    }

    pub fn deinit(self: String, alloc: std.mem.Allocator) void {
        if (self.allocated) {
            alloc.free(self.content);
        }
    }
};

pub fn consumeString(ctx: *Context, str: []const u8) !void {
    if (std.mem.startsWith(u8, ctx.input, str)) {
        ctx.position.pos += str.len;
        ctx.input = ctx.input[str.len..];
    } else {
        return error.UnexpectedToken;
    }
}

pub fn takeBuffer(ctx: *Context, buf: []u8) !void {
    var ix: usize = 0;
    while (ix < buf.len) : (ix += 1) {
        buf[ix] = ctx.current() orelse return error.UnexpectedEOF;
        _ = ctx.next();
    }
}
