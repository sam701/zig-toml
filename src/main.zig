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
            if (self.error_info) |einfo| {
                switch (einfo) {
                    .struct_mapping => |field_path| {
                        self.alloc.free(field_path);
                    },
                    else => {},
                }
            }
        }

        pub fn parseFile(self: *Self, filename: []const u8, dest: *Target) !void {
            const file = try std.fs.cwd().openFile(filename, .{});
            defer file.close();

            var content = try file.readToEndAlloc(self.alloc, 1024 * 1024 * 1024);
            defer self.alloc.free(content);

            return self.parseString(content, dest);
        }

        pub fn parseString(self: *Self, input: []const u8, dest: *Target) !void {
            var ctx = parser.Context{
                .input = input,
                .alloc = self.alloc,
            };
            var tab = table.parseRootTable(&ctx) catch |err| {
                self.error_info = ErrorInfo{ .parse = ctx.position };
                return err;
            };
            if (Target == Table) {
                dest.* = tab;
                return;
            }

            var mapping_ctx = struct_mapping.Context.init(self.alloc);
            defer mapping_ctx.deinit();

            struct_mapping.intoStruct(&mapping_ctx, Target, dest, &tab) catch |err| {
                self.error_info = ErrorInfo{ .struct_mapping = mapping_ctx.field_path.toOwnedSlice() };
                deinitTableRecursively(&tab);
                return err;
            };
        }
    };
}

pub const deinitTableRecursively = table.deinitTableRecursively;
