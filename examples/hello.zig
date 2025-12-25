//! Hello World example for ZigTUI
//! NOTE: Backend implementation is not yet complete, so this won't compile yet.
//! This demonstrates the intended API design.

const std = @import("std");
const tui = @import("zigtui");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // TODO: Initialize backend (platform-specific)
    // var backend = try tui.backend.AnsiBackend.init();
    // defer backend.deinit();

    // TODO: Uncomment when backend is implemented
    // var term = try tui.Terminal.init(allocator, backend.interface());
    // defer term.deinit();

    // try term.hideCursor();
    // defer term.showCursor() catch {};

    // var running = true;
    // while (running) {
    //     // Poll for events (100ms timeout)
    //     const event = try term.backend_impl.pollEvent(100);

    //     // Handle events
    //     switch (event) {
    //         .key => |key| {
    //             if (key.isChar('q')) {
    //                 running = false;
    //             }
    //         },
    //         .resize => |size| {
    //             try term.resize(size);
    //         },
    //         else => {},
    //     }

    //     // Render
    //     try term.draw(render);
    // }

    _ = allocator;
    std.debug.print("Backend not yet implemented. See ARCHITECTURE.md for design.\n", .{});
}

fn render(buf: *tui.Buffer) void {
    const area = buf.getArea();

    // Create a block with border
    const block = tui.widgets.Block{
        .title = "Hello ZigTUI! Press 'q' to quit",
        .borders = tui.widgets.Borders.ALL,
        .style = tui.Style{ .fg = .white, .bg = .blue },
        .border_style = tui.Style{ .fg = .cyan },
        .title_style = tui.Style{ .fg = .yellow, .modifier = .{ .bold = true } },
    };

    // Render the block
    block.render(area, buf);

    // Get inner area
    const inner = block.inner(area);

    // Render text inside
    const text =
        \\Welcome to ZigTUI!
        \\
        \\A Terminal UI library for Zig, inspired by Ratatui.
        \\
        \\Features:
        \\- Cell-based rendering with diff algorithm
        \\- Constraint-based layouts
        \\- Composable widgets
        \\- Explicit memory management
        \\- Cross-platform support
    ;

    const paragraph = tui.widgets.Paragraph{
        .text = text,
        .style = tui.Style{ .fg = .white },
        .wrap = true,
    };

    paragraph.render(inner, buf);
}
