const std = @import("std");
const testing = std.testing;

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

// test "basic add functionality" {
//     var src = Source.init(" hello ");
// }

test "all tests" {
    _ = @import("./Source.zig");
    _ = @import("./string.zig");
    _ = @import("./key.zig");
    _ = @import("./comment.zig");
}
