const std = @import("std");

pub fn Table(comptime DateTypes: type) type {
    return std.StringHashMapUnmanaged(Value(DateTypes));
}

pub fn Array(comptime DateTypes: type) type {
    return std.ArrayList(Value(DateTypes));
}

pub fn Value(comptime DateTypes: type) type {
    return union(enum) {
        string: []const u8,
        integer: i64,
        float: f64,
        boolean: bool,
        date: DateTypes.Date,
        time: DateTypes.Time,
        datetime: DateTypes.DateTime,
        datetime_local: DateTypes.DateTimeLocal,

        array: Array(DateTypes),
        table: Table(DateTypes),
    };
}
