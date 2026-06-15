const std = @import("std");

pub fn Table(comptime DateTypes: type) type {
    return struct {
        definition: Definition,
        data: std.StringHashMapUnmanaged(Value(DateTypes)),

        const Self = @This();

        pub fn init(def: Definition) Self {
            return Self{
                .definition = def,
                .data = .empty,
            };
        }

        pub const GetOrPutResult = std.StringHashMapUnmanaged(Value(DateTypes)).GetOrPutResult;
    };
}

pub fn Array(comptime DateTypes: type) type {
    return struct {
        definition: Definition,
        data: std.ArrayList(Value(DateTypes)),

        const Self = @This();

        pub fn init(def: Definition) Self {
            return Self{
                .definition = def,
                .data = .empty,
            };
        }
    };
}

pub const Definition = enum { header, inlined, implicit };

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
