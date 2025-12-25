//! Terminal module - High-level terminal interface

const std = @import("std");
const backend = @import("../backend/mod.zig");
const render = @import("../render/mod.zig");
const style = @import("../style/mod.zig");
const Allocator = std.mem.Allocator;
const Backend = backend.Backend;
const Buffer = render.Buffer;

pub const Error = backend.Error;

/// Terminal - manages terminal state and rendering
pub const Terminal = struct {
    backend_impl: Backend,
    current_buffer: Buffer,
    next_buffer: Buffer,
    hidden_cursor: bool = false,

    /// Initialize terminal with backend
    pub fn init(allocator: Allocator, backend_impl: Backend) !Terminal {
        // Get initial size
        const size = try backend_impl.getSize();

        // Create buffers
        var current = try Buffer.init(allocator, size.width, size.height);
        errdefer current.deinit();

        var next = try Buffer.init(allocator, size.width, size.height);
        errdefer next.deinit();

        // Setup terminal
        try backend_impl.enterRawMode();
        errdefer backend_impl.exitRawMode() catch {};

        try backend_impl.enableAlternateScreen();
        errdefer backend_impl.disableAlternateScreen() catch {};

        try backend_impl.clearScreen();

        return Terminal{
            .backend_impl = backend_impl,
            .current_buffer = current,
            .next_buffer = next,
        };
    }

    /// Deinitialize terminal
    pub fn deinit(self: *Terminal) void {
        self.backend_impl.disableAlternateScreen() catch {};
        self.backend_impl.exitRawMode() catch {};
        if (self.hidden_cursor) {
            self.backend_impl.showCursor() catch {};
        }
        self.current_buffer.deinit();
        self.next_buffer.deinit();
    }

    /// Draw frame using render function
    pub fn draw(self: *Terminal, ctx: anytype, renderFn: fn (@TypeOf(ctx), *Buffer) anyerror!void) !void {
        // Clear next buffer
        self.next_buffer.clear();

        // Call user render function
        try renderFn(ctx, &self.next_buffer);

        // Flush changes to terminal
        try self.flush();
    }

    /// Flush buffered changes to terminal
    pub fn flush(self: *Terminal) !void {
        // Calculate diff
        var diff = try self.current_buffer.diff(self.next_buffer, self.current_buffer.allocator);
        defer diff.deinit();

        // Write changes
        var output: std.ArrayListUnmanaged(u8) = .empty;
        defer output.deinit(self.current_buffer.allocator);
        const alloc = self.current_buffer.allocator;

        for (diff.updates.items) |update| {
            // Move cursor
            try output.print(alloc, "\x1b[{d};{d}H", .{ update.y + 1, update.x + 1 });

            // Apply style
            const cell = update.cell;
            if (cell.fg != .reset) {
                if (cell.fg == .rgb) {
                    const rgb = cell.fg.rgb;
                    try output.print(alloc, "\x1b[38;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b });
                } else {
                    try output.appendSlice(alloc, cell.fg.toFg());
                }
            }
            if (cell.bg != .reset) {
                if (cell.bg == .rgb) {
                    const rgb = cell.bg.rgb;
                    try output.print(alloc, "\x1b[48;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b });
                } else {
                    try output.appendSlice(alloc, cell.bg.toBg());
                }
            }

            // Write modifiers (simplified - skip for now as toAnsi expects a writer)
            // TODO: Update modifier.toAnsi to work with ArrayListUnmanaged

            // Write character
            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(cell.char, &buf) catch continue;
            try output.appendSlice(alloc, buf[0..len]);

            // Reset style
            try output.appendSlice(alloc, "\x1b[0m");
        }

        // Write to backend
        if (output.items.len > 0) {
            try self.backend_impl.write(output.items);
            try self.backend_impl.flush();
        }

        // Swap buffers
        std.mem.swap(Buffer, &self.current_buffer, &self.next_buffer);
    }

    /// Clear terminal
    pub fn clear(self: *Terminal) !void {
        self.current_buffer.clear();
        self.next_buffer.clear();
        try self.backend_impl.clearScreen();
    }

    /// Hide cursor
    pub fn hideCursor(self: *Terminal) !void {
        try self.backend_impl.hideCursor();
        self.hidden_cursor = true;
    }

    /// Show cursor
    pub fn showCursor(self: *Terminal) !void {
        try self.backend_impl.showCursor();
        self.hidden_cursor = false;
    }

    /// Set cursor position
    pub fn setCursor(self: *Terminal, x: u16, y: u16) !void {
        try self.backend_impl.setCursor(x, y);
    }

    /// Get terminal size
    pub fn getSize(self: *Terminal) !render.Size {
        return try self.backend_impl.getSize();
    }

    /// Resize terminal buffers
    pub fn resize(self: *Terminal, size: render.Size) !void {
        try self.current_buffer.resize(size.width, size.height);
        try self.next_buffer.resize(size.width, size.height);
    }
};
