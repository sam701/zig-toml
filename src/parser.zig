const std = @import("std");
pub const Source = @import("./Source.zig");

pub const Context = struct {
    src: *Source,
    alloc: std.mem.Allocator,
};
