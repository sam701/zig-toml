const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = Allocator.Error || error{InvalidDateTime};

pub const DefaultDateTypes = struct {
    pub const Date = []const u8;
    pub const Time = []const u8;
    pub const DateTime = []const u8;
    pub const DateTimeLocal = []const u8;

    pub fn parseDate(str: []const u8, alloc: Allocator) Error!Date {
        return alloc.dupe(u8, str);
    }
    pub fn parseDatetime(str: []const u8, alloc: Allocator) Error!DateTime {
        return alloc.dupe(u8, str);
    }
    pub fn parseDatetimeLocal(str: []const u8, alloc: Allocator) Error!DateTimeLocal {
        return alloc.dupe(u8, str);
    }
    pub fn parseTime(str: []const u8, alloc: Allocator) Error!Time {
        return alloc.dupe(u8, str);
    }
};

pub fn Value(comptime DateTypes: type) type {
    return union(enum) {
        string: []const u8,
        number: f64,
        boolean: bool,
        date: DateTypes.Date,
        time: DateTypes.Time,
        datetime: DateTypes.DateTime,
        datetime_local: DateTypes.DateTimeLocal,

        array: []const Value(DateTypes),
        table: std.StringHashMap(Value(DateTypes)),
    };
}
