const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = Allocator.Error || error{InvalidDateTime};

pub const String = struct {
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

pub const Simple = struct {
    pub const Date = struct {
        year: u16,
        month: u4,
        day: u5,
    };
    pub const Time = struct {
        hour: u5,
        minute: u6,
        second: u6 = 0,
        nanosecond: u30 = 0,
    };
    pub const DateTime = struct {
        date: Date,
        time: Time,
        offset_minutes: ?i16 = 0,
    };
    pub const DateTimeLocal = DateTime;

    pub fn parseDate(str: []const u8, _: Allocator) Error!Date {
        const d = Date{
            .year = std.fmt.parseInt(u16, str[0..4], 10) catch return error.InvalidDateTime,
            .month = std.fmt.parseInt(u4, str[5..7], 10) catch return error.InvalidDateTime,
            .day = std.fmt.parseInt(u5, str[8..10], 10) catch return error.InvalidDateTime,
        };
        if (d.month < 1 or d.month > 12) return error.InvalidDateTime;
        if (d.day < 1 or d.day > 31) return error.InvalidDateTime;
        if (d.month == 2 and (d.day > 29 or (d.day == 29 and !isLeapYear(d.year)))) return error.InvalidDateTime;
        return d;
    }
    pub fn parseTime(str: []const u8, _: Allocator) Error!Time {
        var t = Time{
            .hour = std.fmt.parseInt(u5, str[0..2], 10) catch return error.InvalidDateTime,
            .minute = std.fmt.parseInt(u6, str[3..5], 10) catch return error.InvalidDateTime,
        };
        if (str.len == 7) return error.InvalidDateTime;
        if (str.len >= 8) {
            t.second = std.fmt.parseInt(u6, str[6..8], 10) catch return error.InvalidDateTime;
        }
        if (str.len == 9) return error.InvalidDateTime;
        if (str.len > 9) {
            t.nanosecond = std.fmt.parseInt(u30, str[9..str.len], 10) catch return error.InvalidDateTime;
        }

        if (t.hour > 23) return error.InvalidDateTime;
        if (t.minute > 59) return error.InvalidDateTime;
        if (t.second > 59) return error.InvalidDateTime;
        return t;
    }
    pub fn parseDatetime(str: []const u8, alloc: Allocator) Error!DateTime {
        const offset_index = getOffsetIndex(str);
        return DateTime{
            .date = try parseDate(str[0..10], alloc),
            .time = try parseTime(str[11..offset_index], alloc),
            .offset_minutes = try parseOffset(str[offset_index..]),
        };
    }
    pub fn parseDatetimeLocal(str: []const u8, alloc: Allocator) Error!DateTimeLocal {
        return DateTimeLocal{
            .date = try parseDate(str[0..10], alloc),
            .time = try parseTime(str[11..str.len], alloc),
        };
    }
};

fn getOffsetIndex(str: []const u8) usize {
    var i: usize = str.len - 1;
    while (i > 0) : (i -= 1) {
        if (str[i] == 'Z' or str[i] == 'z' or str[i] == '+' or str[i] == '-') {
            return i;
        }
    }
    unreachable;
}

fn parseOffset(str: []const u8) Error!i16 {
    if (str[0] == 'Z' or str[0] == 'z') return 0;
    const sign: i16 = if (str[0] == '+') 1 else if (str[0] == '-') -1 else unreachable;

    const hour = std.fmt.parseInt(i16, str[1..3], 10) catch return error.InvalidDateTime;
    const minutes = std.fmt.parseInt(i16, str[4..6], 10) catch return error.InvalidDateTime;

    if (hour < 0 or hour > 23) return error.InvalidDateTime;
    if (minutes < 0 or minutes > 59) return error.InvalidDateTime;

    return sign * (hour * 60 + minutes);
}

fn isLeapYear(year: u16) bool {
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
}
