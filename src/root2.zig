const std = @import("std");

const parser = @import("./parser2.zig");
// pub const serialize = @import("serialize/root.zig").serialize;

pub const parse = parser.parse;

test {
    _ = @import("./tests2.zig");
}
