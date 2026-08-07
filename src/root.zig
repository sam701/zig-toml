const std = @import("std");

const parser = @import("./parser.zig");
const value = @import("./value.zig");
const datetime = @import("./datetime.zig");
// pub const serialize = @import("serialize/root.zig").serialize;

pub const parse = parser.parse;

// TODO: docs
pub const Value = value.Value;
pub const Table = value.Table;
pub const Array = value.Array;
pub const ValueError = value.Error;

pub const DateTimesString = datetime.String;
pub const DateTimesSimple = datetime.Simple;

test {
    // _ = @import("./tests.zig");
    _ = @import("./scanner/string.zig");
}
