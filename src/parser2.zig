const std = @import("std");
const Scanner = @import("./scanner/root.zig").Scanner;
const Token = @import("./scanner/root.zig").Token;
const Reader = std.Io.Reader;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const SourceLocation = @import("./scanner/source.zig").SourceLocation;

pub const Parsed = std.json.Parsed;
pub const Error = Scanner.Error || std.fmt.ParseIntError || std.fmt.ParseFloatError || std.mem.Allocator.Error || error{
    UnexpectedToken,
    NotStruct,
    InvalidValueType,
};

pub fn parse(comptime T: type, reader: *Reader, alloc: Allocator) Error!Parsed(T) {
    var p = try Parser.init(reader, alloc);
    defer p.deinit();
    return Parsed(T){
        .arena = p.arena,
        .value = try p.parseStruct(T),
    };
}

// const StructTree = std.StringHashMap(*StructTree);

const Parser = struct {
    arena: *ArenaAllocator,
    scanner: Scanner,
    token_location: ?SourceLocation = null,
    // struct_init_map: StructTree,

    pub fn init(reader: *Reader, alloc: Allocator) error{OutOfMemory}!Parser {
        const arena = try alloc.create(ArenaAllocator);
        arena.* = ArenaAllocator.init(alloc);
        return .{
            .arena = arena,
            .scanner = try Scanner.init(reader, alloc),
            // .struct_init_map = StructTree.init(alloc),
        };
    }

    pub fn deinit(self: *Parser) void {
        self.scanner.deinit();
    }

    fn nextToken(self: *Parser, expect_value: bool) Error!Token {
        const t = try self.scanner.nextRaw(expect_value);
        self.token_location = t.location;
        return t;
    }

    fn parseStruct(self: *Parser, comptime T: type) Error!T {
        const ti = @typeInfo(T);
        if (ti != .@"struct") return error.NotStruct;

        var result: T = undefined;

        while (true) {
            const token = try self.nextToken(false);

            switch (token.kind) {
                .bare_key, .string => {
                    inline for (ti.@"struct".fields) |field| {
                        if (std.mem.eql(u8, field.name, token.content)) {
                            @field(result, field.name) = try self.parseAfterBareKey(field.type);
                            break;
                        }
                    }
                },
                .left_bracket => {},
                .double_left_bracket => {},
                .line_break => {},
                .end_of_document => break,
                else => return error.UnexpectedToken,
            }
        }

        return result;
    }

    fn parseValue(self: *Parser, comptime T: type) Error!T {
        const ti = @typeInfo(T);

        const token = try self.nextToken(true);
        // std.debug.print("kind = {}, context = {s} loc = {any}\n", .{ token.kind, token.content, token.location });
        switch (ti) {
            .int => {
                if (token.kind != .number) return error.InvalidValueType;
                return std.fmt.parseInt(T, token.content, 0);
            },
            .float => {
                if (token.kind != .number) return error.InvalidValueType;
                return std.fmt.parseFloat(T, token.content);
            },

            else => {},
        }

        unreachable;
    }

    // fn parseKeyField(self: *Parser, comptime T: type, dest: *T, field_name: []const u8, init_map: *StructTree) Error!void {
    //     const ti = @typeInfo(T);
    //     if (ti != .@"struct") return error.NotStruct;

    //     inline for (ti.@"struct".fields) |field| {
    //         if (std.mem.eql(u8, field.name, field_name)) {

    //             // ===

    //             // ===
    //             var token = try self.nextToken(false);
    //             switch (token.kind) {
    //                 .dot => {
    //                     token = try self.nextToken(false);
    //                     switch (token.kind) {
    //                         .bare_key, .string => {},
    //                         else => return error.UnexpectedToken,
    //                     }
    //                 },
    //                 .equal => return self.parseInnerTable(T),
    //                 else => return error.UnexpectedToken,
    //             }

    //             // @field(result, field.name) = try self.parseAfterBareKey(field.type);
    //             return;
    //         }
    //     }
    //     // TODO handle unmatched field
    // }

    fn parseAfterBareKey(self: *Parser, comptime T: type) Error!T {
        // const ti = @typeInfo(T);
        // if (ti == .@"struct") {
        const token = try self.nextToken(false);
        switch (token.kind) {
            .dot => {},
            .equal => return self.parseValue(T),
            else => return error.UnexpectedToken,
        }
        // }
        unreachable;
    }

    // fn parseInnerTable(self: *Parser, comptime T: type) Error!T {
    //     var token = try self.scanner.next();
    //     if (token.kind != .left_brace) return error.UnexpectedToken;

    //     token = try self.nextToken(false);
    //     switch (token.kind) {
    //         .bare_key, .string => {},
    //         else => return error.UnexpectedToken,
    //     }
    // }
};
