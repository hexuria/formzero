//! Default-aligned sensitive heap ownership helpers.
//!
//! Zig 0.16 `Allocator.free` writes `undefined` before calling `rawFree`.
//! Sensitive allocations therefore cross the raw allocator boundary directly
//! after a volatile zero fill. These helpers are only for allocations made
//! with the default alignment of `T`.

const std = @import("std");

pub fn wipeValue(comptime T: type, value: *T) void {
    std.crypto.secureZero(u8, std.mem.asBytes(value));
}

pub fn wipeAndFreeDefaultAligned(
    comptime T: type,
    allocator: std.mem.Allocator,
    items: []T,
) void {
    if (items.len == 0) return;
    const bytes = std.mem.sliceAsBytes(items);
    std.crypto.secureZero(u8, bytes);
    allocator.rawFree(bytes, .of(T), @returnAddress());
}

pub fn wipeAndFreeConstDefaultAligned(
    comptime T: type,
    allocator: std.mem.Allocator,
    items: []const T,
) void {
    wipeAndFreeDefaultAligned(T, allocator, @constCast(items));
}

pub fn wipeAndDestroyDefaultAligned(
    comptime T: type,
    allocator: std.mem.Allocator,
    value: *T,
) void {
    const bytes = std.mem.asBytes(value);
    if (bytes.len == 0) return;
    std.crypto.secureZero(u8, bytes);
    allocator.rawFree(bytes, .of(T), @returnAddress());
}

pub fn wipeAndDeinitArrayList(
    comptime T: type,
    allocator: std.mem.Allocator,
    list: *std.ArrayList(T),
) void {
    wipeAndFreeDefaultAligned(T, allocator, list.allocatedSlice());
    list.* = .empty;
}

/// Ensures capacity without allowing `ArrayList` to ordinarily free a prior
/// sensitive allocation during growth.
pub fn ensureUnusedCapacity(
    comptime T: type,
    allocator: std.mem.Allocator,
    list: *std.ArrayList(T),
    additional: usize,
) std.mem.Allocator.Error!void {
    const required = std.math.add(
        usize,
        list.items.len,
        additional,
    ) catch return error.OutOfMemory;
    if (required <= list.capacity) return;

    const grown = std.math.add(
        usize,
        list.capacity,
        list.capacity / 2 + 8,
    ) catch required;
    const new_capacity = @max(required, grown);
    const replacement = try allocator.alloc(T, new_capacity);
    @memcpy(replacement[0..list.items.len], list.items);
    const old_length = list.items.len;
    wipeAndFreeDefaultAligned(T, allocator, list.allocatedSlice());
    list.* = .{
        .items = replacement[0..old_length],
        .capacity = new_capacity,
    };
}

pub fn append(
    comptime T: type,
    allocator: std.mem.Allocator,
    list: *std.ArrayList(T),
    value: T,
) std.mem.Allocator.Error!void {
    try ensureUnusedCapacity(T, allocator, list, 1);
    list.appendAssumeCapacity(value);
}

pub fn appendSlice(
    comptime T: type,
    allocator: std.mem.Allocator,
    list: *std.ArrayList(T),
    values: []const T,
) std.mem.Allocator.Error!void {
    try ensureUnusedCapacity(T, allocator, list, values.len);
    list.appendSliceAssumeCapacity(values);
}

/// Transfers one exact-length default-aligned allocation to the caller and
/// securely releases any larger backing capacity.
pub fn toOwnedSlice(
    comptime T: type,
    allocator: std.mem.Allocator,
    list: *std.ArrayList(T),
) std.mem.Allocator.Error![]T {
    if (list.items.len == 0) {
        wipeAndDeinitArrayList(T, allocator, list);
        return allocator.alloc(T, 0);
    }
    if (list.items.len == list.capacity) {
        const result = list.items;
        list.* = .empty;
        return result;
    }

    const result = try allocator.alloc(T, list.items.len);
    @memcpy(result, list.items);
    wipeAndDeinitArrayList(T, allocator, list);
    return result;
}

const ZeroCheckingAllocator = struct {
    const Self = @This();

    backing: std.mem.Allocator,
    zero_frees: usize = 0,
    nonzero_frees: usize = 0,
    last_alignment: ?std.mem.Alignment = null,

    fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn alloc(
        context: *anyopaque,
        length: usize,
        alignment: std.mem.Alignment,
        return_address: usize,
    ) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(context));
        return self.backing.rawAlloc(length, alignment, return_address);
    }

    fn resize(
        context: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        new_length: usize,
        return_address: usize,
    ) bool {
        const self: *Self = @ptrCast(@alignCast(context));
        return self.backing.rawResize(
            memory,
            alignment,
            new_length,
            return_address,
        );
    }

    fn remap(
        context: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        new_length: usize,
        return_address: usize,
    ) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(context));
        return self.backing.rawRemap(
            memory,
            alignment,
            new_length,
            return_address,
        );
    }

    fn free(
        context: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        return_address: usize,
    ) void {
        const self: *Self = @ptrCast(@alignCast(context));
        var all_zero = true;
        for (memory) |byte| {
            if (byte != 0) {
                all_zero = false;
                break;
            }
        }
        if (all_zero) {
            self.zero_frees += 1;
        } else {
            self.nonzero_frees += 1;
        }
        self.last_alignment = alignment;
        self.backing.rawFree(memory, alignment, return_address);
    }
};

test "default-aligned release is zero at raw allocator boundary" {
    var checking: ZeroCheckingAllocator = .{
        .backing = std.testing.allocator,
    };
    const allocator = checking.allocator();
    const bytes = try allocator.dupe(u8, "sensitive-value");
    wipeAndFreeDefaultAligned(u8, allocator, bytes);

    try std.testing.expectEqual(@as(usize, 1), checking.zero_frees);
    try std.testing.expectEqual(@as(usize, 0), checking.nonzero_frees);
    try std.testing.expectEqual(
        std.mem.Alignment.of(u8),
        checking.last_alignment.?,
    );
}

test "zero-length release does not call raw free" {
    var checking: ZeroCheckingAllocator = .{
        .backing = std.testing.allocator,
    };
    const allocator = checking.allocator();
    const empty = try allocator.alloc(u8, 0);
    wipeAndFreeDefaultAligned(u8, allocator, empty);
    try std.testing.expectEqual(@as(usize, 0), checking.zero_frees);
    try std.testing.expectEqual(@as(usize, 0), checking.nonzero_frees);
}

test "sensitive ArrayList growth and transfer wipe old capacities" {
    var checking: ZeroCheckingAllocator = .{
        .backing = std.testing.allocator,
    };
    const allocator = checking.allocator();
    var list: std.ArrayList(u8) = .empty;
    errdefer wipeAndDeinitArrayList(u8, allocator, &list);
    try appendSlice(u8, allocator, &list, "first-sensitive-value");
    try appendSlice(
        u8,
        allocator,
        &list,
        "-forces-secure-growth-and-transfer",
    );
    try ensureUnusedCapacity(u8, allocator, &list, 64);
    const owned = try toOwnedSlice(u8, allocator, &list);
    wipeAndFreeDefaultAligned(u8, allocator, owned);

    try std.testing.expect(checking.zero_frees >= 3);
    try std.testing.expectEqual(@as(usize, 0), checking.nonzero_frees);
}
