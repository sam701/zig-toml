const std = @import("std");
const Allocator = std.mem.Allocator;

/// Tagged union representing a field that can be either an object (inline table) or an array of objects.
pub const AllocatedStructField = union(enum) {
    /// Field contains a nested struct/inline table.
    object: StructField,
    /// Field contains an array of struct/inline table objects.
    array: ArrayField,

    pub fn deinit(self: *AllocatedStructField) void {
        switch (self.*) {
            inline else => |*x| x.deinit(),
        }
    }
};

/// Represents an array of objects during parsing.
/// Holds intermediate allocated structs and a reference to the final typed array list.
pub const ArrayField = struct {
    /// Allocator for creating objects.
    alloc: Allocator,
    /// Intermediate list of allocated struct fields being parsed.
    objects: std.ArrayList(AllocatedStructField),
    /// Opaque pointer to the final typed array list (e.g., ArrayList(T)).
    field_values_array_list: *anyopaque,

    pub fn init(alloc: Allocator, real_values_ptr: *anyopaque) ArrayField {
        return .{
            .objects = std.ArrayList(AllocatedStructField).empty,
            .alloc = alloc,
            .field_values_array_list = real_values_ptr,
        };
    }

    pub fn deinit(self: *ArrayField) void {
        for (self.objects.items) |*obj| {
            obj.deinit();
        }
        self.objects.deinit(self.alloc);
    }
};

/// Represents a struct/inline table during parsing.
/// Maps field names to their allocated values (either nested structs or arrays).
pub const StructField = struct {
    /// Maps field names to their corresponding allocated values.
    fields: std.StringHashMap(AllocatedStructField),

    hashmap_initialized: bool = false,

    /// Opaque pointer to an ArrayList used for dynamic [[key]] array-of-tables accumulation.
    opaque_array_list: ?*anyopaque = null,

    pub fn init(alloc: Allocator) StructField {
        return .{ .fields = std.StringHashMap(AllocatedStructField).init(alloc) };
    }

    pub fn deinit(self: *StructField) void {
        var it = self.fields.valueIterator();
        while (it.next()) |v| v.deinit();

        self.fields.deinit();
    }

    pub fn markAsObject(self: *StructField, field_name: []const u8) error{OutOfMemory}!*StructField {
        const result = try self.fields.getOrPut(field_name);
        if (!result.found_existing) {
            result.value_ptr.* = AllocatedStructField{ .object = StructField.init(self.fields.allocator) };
        }

        return &result.value_ptr.object;
    }

    fn markAsArray(self: *StructField, field_name: []const u8) error{OutOfMemory}!*ArrayField {
        const result = try self.fields.getOrPut(field_name);
        if (!result.found_existing) {
            result.value_ptr.* = AllocatedStructField{ .array = ArrayField.init(self.fields.allocator) };
        }

        return &result.value_ptr.array;
    }
};

/// A type-erased deferred callback that converts an `ArrayList(FieldType)` into an
/// owned slice and assigns it to a named field of a destination struct.
///
/// The parser accumulates TOML array-of-tables entries into typed `ArrayList`s but
/// tracks them as `*anyopaque` for generality. `SliceFinalizer` captures the concrete
/// type information at `init` time (via comptime parameters) and defers the
/// `toOwnedSlice` + field assignment until parsing is complete, at which point the
/// caller iterates all registered finalizers and calls `finalize_fn`.
pub const SliceFinalizer = struct {
    finalize_fn: *const fn (ctx: *anyopaque, Allocator) void,
    context: *anyopaque,

    /// Creates a finalizer that will call `toOwnedSlice` on `array_list_ptr` (cast to
    /// `*ArrayList(FieldType)`) and store the result into `field_name` on `dest`.
    /// The `FinalizerCtx` is heap-allocated via `allocator` and must outlive the call
    /// to `finalize_fn`.
    pub fn init(
        comptime ObjectType: type,
        comptime FieldType: type,
        comptime field_name: []const u8,
        dest: *ObjectType,
        array_list_ptr: *anyopaque,
        allocator: Allocator,
    ) error{OutOfMemory}!SliceFinalizer {
        const FieldValueArrayList = std.ArrayList(FieldType);

        const FinalizerCtx = struct {
            array_list: *FieldValueArrayList,
            dest: *ObjectType,

            fn finalize(ctx: *anyopaque, alloc: Allocator) void {
                const self_ctx: *@This() = @ptrCast(@alignCast(ctx));
                @field(self_ctx.dest, field_name) = self_ctx.array_list.toOwnedSlice(alloc) catch unreachable;
            }
        };

        const finalizer_ctx = try allocator.create(FinalizerCtx);
        finalizer_ctx.* = .{
            .array_list = @ptrCast(@alignCast(array_list_ptr)),
            .dest = dest,
        };

        return .{
            .finalize_fn = FinalizerCtx.finalize,
            .context = @ptrCast(finalizer_ctx),
        };
    }
};
