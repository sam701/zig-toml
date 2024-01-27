const std = @import("std");

const parser = @import("./parser.zig");
const table = @import("./table.zig");
const struct_mapping = @import("./struct_mapping.zig");
const datetime = @import("./datetime.zig");
const value = @import("./value.zig");

pub const Table = table.Table;
pub const Date = datetime.Date;
pub const Time = datetime.Time;
pub const DateTime = datetime.DateTime;
pub const Value = value.Value;
pub const ValueList = value.ValueList;

pub const Position = parser.Position;
pub const FieldPath = []const []const u8;

pub const ErrorInfo = union(enum) {
    parse: Position,
    struct_mapping: FieldPath,
};

pub fn Parsed(comptime T: type) type {
    return struct {
        arena: std.heap.ArenaAllocator,
        value: T,

        pub fn deinit(self: @This()) void {
            self.arena.deinit();
        }
    };
}

pub fn Parser(comptime Target: type) type {
    return struct {
        const Self = @This();

        alloc: std.mem.Allocator,
        error_info: ?ErrorInfo = null,

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{
                .alloc = alloc,
            };
        }

        pub fn deinit(self: *Self) void {
            self.free_error_info();
        }

        fn free_error_info(self: *Self) void {
            if (self.error_info) |einfo| {
                switch (einfo) {
                    .struct_mapping => |field_path| {
                        self.alloc.free(field_path);
                    },
                    else => {},
                }
            }
        }

        pub fn parseFile(self: *Self, filename: []const u8) !Parsed(Target) {
            const file = try std.fs.cwd().openFile(filename, .{});
            defer file.close();

            const content = try file.readToEndAlloc(self.alloc, 1024 * 1024 * 1024);
            defer self.alloc.free(content);

            return self.parseString(content);
        }

        pub fn parseString(self: *Self, input: []const u8) !Parsed(Target) {
            self.free_error_info();

            var arena = std.heap.ArenaAllocator.init(self.alloc);
            errdefer arena.deinit();
            const alloc = arena.allocator();
            var ctx = parser.Context{
                .input = input,
                .alloc = alloc,
            };
            var tab = table.parseRootTable(&ctx) catch |err| {
                self.free_error_info();
                self.error_info = ErrorInfo{ .parse = ctx.position };
                return err;
            };
            if (Target == Table) {
                return .{ .arena = arena, .value = tab };
            }

            var mapping_ctx = struct_mapping.Context.init(alloc);

            var dest: Target = undefined;
            struct_mapping.intoStruct(&mapping_ctx, Target, &dest, &tab) catch |err| {
                self.free_error_info();
                self.error_info = ErrorInfo{ .struct_mapping = try self.alloc.dupe([]const u8, mapping_ctx.field_path.items) }; // i suspect this might leak memory (the outer array is copied, but not inner ones). But it doesn't seem to leak. Strange.
                return err;
            };
            return .{ .arena = arena, .value = dest };
        }
    };
}
