//! ANSI escape sequence backend for Unix-like systems

const std = @import("std");
const builtin = @import("builtin");
const Backend = @import("mod.zig").Backend;
const Error = @import("mod.zig").Error;
const events = @import("../events/mod.zig");
const render = @import("../render/mod.zig");
const Allocator = std.mem.Allocator;

const is_windows = builtin.os.tag == .windows;

pub const AnsiBackend = struct {
    allocator: Allocator,
    stdin: std.fs.File,
    stdout: std.fs.File,
    original_termios: if (!is_windows) std.posix.termios else void,
    in_raw_mode: bool = false,
    in_alternate_screen: bool = false,
    write_buffer: std.ArrayListUnmanaged(u8) = .empty,

    pub fn init(allocator: Allocator) !AnsiBackend {
        if (is_windows) {
            return error.UnsupportedTerminal; // Use windows.zig backend instead
        }

        const stdin = std.fs.File.stdin();
        const stdout = std.fs.File.stdout();

        // Save original terminal settings
        const original = try std.posix.tcgetattr(stdin.handle);

        return AnsiBackend{
            .allocator = allocator,
            .stdin = stdin,
            .stdout = stdout,
            .original_termios = original,
        };
    }

    pub fn deinit(self: *AnsiBackend) void {
        if (self.in_alternate_screen) {
            disableAlternateScreen(self) catch {};
        }
        if (self.in_raw_mode) {
            exitRawMode(self) catch {};
        }
        self.write_buffer.deinit(self.allocator);
    }

    pub fn interface(self: *AnsiBackend) Backend {
        return Backend{
            .ptr = self,
            .vtable = &.{
                .enter_raw_mode = enterRawMode,
                .exit_raw_mode = exitRawMode,
                .enable_alternate_screen = enableAlternateScreen,
                .disable_alternate_screen = disableAlternateScreen,
                .clear_screen = clearScreen,
                .write = write,
                .flush = flush,
                .get_size = getSize,
                .poll_event = pollEvent,
                .hide_cursor = hideCursor,
                .show_cursor = showCursor,
                .set_cursor = setCursor,
            },
        };
    }

    fn enterRawMode(ptr: *anyopaque) Error!void {
        const self: *AnsiBackend = @ptrCast(@alignCast(ptr));
        if (self.in_raw_mode) return;

        if (!is_windows) {
            var raw = self.original_termios;

            // Disable canonical mode and echo
            raw.lflag.ECHO = false;
            raw.lflag.ICANON = false;
            raw.lflag.ISIG = false;
            raw.lflag.IEXTEN = false;

            // Disable input processing
            raw.iflag.IXON = false;
            raw.iflag.ICRNL = false;
            raw.iflag.BRKINT = false;
            raw.iflag.INPCK = false;
            raw.iflag.ISTRIP = false;

            // Disable output processing
            raw.oflag.OPOST = false;

            // Set character size to 8 bits
            raw.cflag.CSIZE = .CS8;

            // Set read timeout
            raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
            raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;

            try std.posix.tcsetattr(self.stdin.handle, .FLUSH, raw);
            self.in_raw_mode = true;
        }
    }

    fn exitRawMode(ptr: *anyopaque) Error!void {
        const self: *AnsiBackend = @ptrCast(@alignCast(ptr));
        if (!self.in_raw_mode) return;

        if (!is_windows) {
            try std.posix.tcsetattr(self.stdin.handle, .FLUSH, self.original_termios);
        }
        self.in_raw_mode = false;
    }

    fn enableAlternateScreen(ptr: *anyopaque) Error!void {
        const self: *AnsiBackend = @ptrCast(@alignCast(ptr));
        if (self.in_alternate_screen) return;

        self.stdout.writeAll("\x1b[?1049h") catch return Error.IOError; // Enable alternate screen
        self.stdout.writeAll("\x1b[2J") catch return Error.IOError; // Clear screen
        self.stdout.writeAll("\x1b[H") catch return Error.IOError; // Move cursor to home
        self.in_alternate_screen = true;
    }

    fn disableAlternateScreen(ptr: *anyopaque) Error!void {
        const self: *AnsiBackend = @ptrCast(@alignCast(ptr));
        if (!self.in_alternate_screen) return;

        self.stdout.writeAll("\x1b[?1049l") catch return Error.IOError; // Disable alternate screen
        self.in_alternate_screen = false;
    }

    fn clearScreen(ptr: *anyopaque) Error!void {
        const self: *AnsiBackend = @ptrCast(@alignCast(ptr));
        self.stdout.writeAll("\x1b[2J\x1b[H") catch return Error.IOError;
    }

    fn write(ptr: *anyopaque, data: []const u8) Error!void {
        const self: *AnsiBackend = @ptrCast(@alignCast(ptr));
        self.write_buffer.appendSlice(self.allocator, data) catch return Error.IOError;
    }

    fn flush(ptr: *anyopaque) Error!void {
        const self: *AnsiBackend = @ptrCast(@alignCast(ptr));
        if (self.write_buffer.items.len > 0) {
            self.stdout.writeAll(self.write_buffer.items) catch return Error.IOError;
            self.write_buffer.clearRetainingCapacity();
        }
    }

    fn getSize(ptr: *anyopaque) Error!render.Size {
        const self: *AnsiBackend = @ptrCast(@alignCast(ptr));
        if (builtin.os.tag == .windows) {
            // Windows: fallback to default size
            return .{ .width = 80, .height = 24 };
        } else {
            var size: std.posix.winsize = undefined;
            // Linux syscall returns -errno on error (as usize, so very large value)
            const result = std.posix.system.ioctl(self.stdout.handle, std.posix.T.IOCGWINSZ, @intFromPtr(&size));
            const signed_result: isize = @bitCast(result);
            if (signed_result < 0) {
                // Return default size if ioctl fails (e.g., not a TTY)
                return .{ .width = 80, .height = 24 };
            }
            // Fallback if zero dimensions
            if (size.col == 0 or size.row == 0) {
                return .{ .width = 80, .height = 24 };
            }
            return .{
                .width = size.col,
                .height = size.row,
            };
        }
    }

    fn pollEvent(ptr: *anyopaque, timeout_ms: u32) Error!events.Event {
        const self: *AnsiBackend = @ptrCast(@alignCast(ptr));

        // Simple non-blocking read
        _ = timeout_ms; // TODO: implement proper timeout with poll/select

        var buf: [32]u8 = undefined;
        const n = self.stdin.read(&buf) catch |err| {
            if (err == error.WouldBlock) return events.Event.none;
            return Error.IOError;
        };

        if (n == 0) return events.Event.none;

        // Parse escape sequences
        return parseEvent(buf[0..n]);
    }

    fn hideCursor(ptr: *anyopaque) Error!void {
        const self: *AnsiBackend = @ptrCast(@alignCast(ptr));
        self.stdout.writeAll("\x1b[?25l") catch return Error.IOError;
    }

    fn showCursor(ptr: *anyopaque) Error!void {
        const self: *AnsiBackend = @ptrCast(@alignCast(ptr));
        self.stdout.writeAll("\x1b[?25h") catch return Error.IOError;
    }

    fn setCursor(ptr: *anyopaque, x: u16, y: u16) Error!void {
        const self: *AnsiBackend = @ptrCast(@alignCast(ptr));
        var buffer: [32]u8 = undefined;
        const cmd = std.fmt.bufPrint(&buffer, "\x1b[{d};{d}H", .{ y + 1, x + 1 }) catch return Error.IOError;
        self.stdout.writeAll(cmd) catch return Error.IOError;
    }
};

/// Parse input bytes into events
fn parseEvent(input: []const u8) events.Event {
    if (input.len == 0) return .none;

    // Single character
    if (input.len == 1) {
        const c = input[0];
        return switch (c) {
            '\r', '\n' => .{ .key = .{ .code = .enter } },
            '\t' => .{ .key = .{ .code = .tab } },
            127 => .{ .key = .{ .code = .backspace } }, // DEL
            27 => .{ .key = .{ .code = .esc } },
            1...8, 11...12, 14...26 => |ctrl| .{ .key = .{ // Ctrl+A to Ctrl+Z (excluding tab=9, newline=10, enter=13)
                .code = .{ .char = @as(u21, ctrl - 1 + 'a') },
                .modifiers = .{ .ctrl = true },
            } },
            else => .{ .key = .{ .code = .{ .char = c } } },
        };
    }

    // Escape sequences
    if (input[0] == 27) {
        if (input.len == 1) return .{ .key = .{ .code = .esc } };

        // CSI sequences: ESC [
        if (input.len >= 3 and input[1] == '[') {
            return switch (input[2]) {
                'A' => .{ .key = .{ .code = .up } },
                'B' => .{ .key = .{ .code = .down } },
                'C' => .{ .key = .{ .code = .right } },
                'D' => .{ .key = .{ .code = .left } },
                'H' => .{ .key = .{ .code = .home } },
                'F' => .{ .key = .{ .code = .end } },
                '3' => if (input.len >= 4 and input[3] == '~')
                    .{ .key = .{ .code = .delete } }
                else
                    .none,
                '5' => if (input.len >= 4 and input[3] == '~')
                    .{ .key = .{ .code = .page_up } }
                else
                    .none,
                '6' => if (input.len >= 4 and input[3] == '~')
                    .{ .key = .{ .code = .page_down } }
                else
                    .none,
                else => .none,
            };
        }
    }

    return .none;
}

test "AnsiBackend basic" {
    if (is_windows) return error.SkipZigTest;
    // Basic smoke test - actual functionality requires a real terminal
    const allocator = std.testing.allocator;
    _ = allocator;
    // Cannot fully test without a TTY
}
