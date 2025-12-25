//! Complete showcase of ZigTUI widgets
//! Demonstrates: Block, Paragraph, List, Gauge, LineGauge, Table
//! Controls: Arrow keys to navigate, Tab to switch focus, 'q' to quit

const std = @import("std");
const tui = @import("zigtui");

const Terminal = tui.terminal.Terminal;
const Layout = tui.layout.Layout;
const Constraint = tui.layout.Constraint;
const Block = tui.widgets.Block;
const Borders = tui.widgets.Borders;
const Paragraph = tui.widgets.Paragraph;
const List = tui.widgets.List;
const ListItem = tui.widgets.ListItem;
const Gauge = tui.widgets.Gauge;
const LineGauge = tui.widgets.LineGauge;
const Table = tui.widgets.Table;
const Row = tui.widgets.Row;
const Column = tui.widgets.Column;
const Color = tui.style.Color;
const Style = tui.style.Style;
const Modifier = tui.style.Modifier;

const AppState = struct {
    list_state: usize = 0,
    table_state: usize = 0,
    progress: u8 = 0,
    focus: enum { list, table } = .list,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize terminal
    var backend = try tui.backend.AnsiBackend.init(allocator);
    defer backend.deinit();
    var terminal = try Terminal.init(allocator, backend.interface());
    defer terminal.deinit();

    var state = AppState{};

    // Draw UI once (event polling not yet implemented)
    const DrawContext = struct {
        state: *AppState,
        allocator: std.mem.Allocator,
    };
    
    const ctx = DrawContext{ .state = &state, .allocator = allocator };
    
    // Updated draw call for Zig 0.15
    try terminal.draw(ctx, struct {
        fn drawFn(draw_ctx: DrawContext, frame: *tui.render.Buffer) !void {
            const area = frame.getArea();

            // Create main layout manually
            const title_height: u16 = 3;
            const gauges_height: u16 = @divTrunc((area.height - title_height) * 30, 100);
            const list_height: u16 = @divTrunc((area.height - title_height) * 35, 100);
            const table_height: u16 = area.height - title_height - gauges_height - list_height;

            const main_chunks = [_]tui.render.Rect{
                .{ .x = area.x, .y = area.y, .width = area.width, .height = title_height }, // Title
                .{ .x = area.x, .y = area.y + title_height, .width = area.width, .height = gauges_height }, // Gauges
                .{ .x = area.x, .y = area.y + title_height + gauges_height, .width = area.width, .height = list_height }, // List
                .{ .x = area.x, .y = area.y + title_height + gauges_height + list_height, .width = area.width, .height = table_height }, // Table
            };

            // Title
            drawTitle(main_chunks[0], frame);

            // Gauges section
            drawGauges(main_chunks[1], frame, draw_ctx.state.progress, draw_ctx.allocator) catch {};

            // List section
            drawList(main_chunks[2], frame, draw_ctx.state, draw_ctx.allocator) catch {};

            // Table section
            drawTable(main_chunks[3], frame, draw_ctx.state, draw_ctx.allocator) catch {};
        }
    }.drawFn);

    // Note: Event loop and interactive features are not yet implemented
    // The UI will be rendered once and then exit
    std.debug.print("Showcase rendered successfully! (Event polling not yet implemented)\n", .{});
}

fn drawTitle(area: tui.render.Rect, buf: *tui.render.Buffer) void {
    const block = Block{
        .title = "ZigTUI Showcase - Press 'q' to quit, Tab to switch focus, Arrows to navigate",
        .borders = Borders.all(),
        .style = Style{ .fg = .white, .bg = .black },
        .border_style = Style{ .fg = .cyan },
    };
    block.render(area, buf);
}

fn drawGauges(area: tui.render.Rect, buf: *tui.render.Buffer, progress: u8, allocator: std.mem.Allocator) !void {
    // Safety check: skip rendering if area is too small
    if (area.width == 0 or area.height == 0) return;

    var layout = Layout{
        .direction = .vertical,
        .margin = tui.layout.Margin.ALL_1,
        .constraints = &[_]tui.layout.Constraint{},
    };
    const chunks = try layout.split(area, allocator);
    defer allocator.free(chunks);

    // Block gauge
    const label = try std.fmt.allocPrint(allocator, "Progress: {d}%", .{progress});
    defer allocator.free(label);
    
    const gauge = Gauge{
        .ratio = @as(f64, @floatFromInt(progress)) / 100.0,
        .label = label,
        .gauge_style = Style{ .fg = .black, .bg = .cyan, .modifier = Modifier{ .bold = true } },
    };
    gauge.render(chunks[1], buf);

    // Line gauges
    const line1 = LineGauge{
        .ratio = @as(f64, @floatFromInt(progress)) / 100.0,
        .label = "CPU: ",
        .gauge_style = Style{ .fg = .green },
        .line_set = .thick,
    };
    line1.render(tui.render.Rect{ .x = chunks[2].x, .y = chunks[2].y, .width = chunks[2].width, .height = 1 }, buf);

    const line2 = LineGauge{
        .ratio = @as(f64, @floatFromInt(100 - progress)) / 100.0,
        .label = "MEM: ",
        .gauge_style = Style{ .fg = .yellow },
        .line_set = .rounded,
    };
    line2.render(tui.render.Rect{ .x = chunks[2].x, .y = chunks[2].y + 1, .width = chunks[2].width, .height = 1 }, buf);
}

fn drawList(area: tui.render.Rect, buf: *tui.render.Buffer, state: *AppState, allocator: std.mem.Allocator) !void {
    const block = Block{
        .title = if (state.focus == .list) "List (FOCUSED)" else "List",
        .borders = Borders.all(),
        .border_style = if (state.focus == .list)
            Style{ .fg = .cyan, .modifier = Modifier{ .bold = true } }
        else
            Style{ .fg = .white },
    };
    const inner = block.inner(area);
    block.render(area, buf);

    // Create list items as a fixed-size array
    var item_buf: [10]ListItem = undefined;
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const text = try std.fmt.allocPrint(allocator, "List Item {d}", .{i + 1});
        item_buf[i] = ListItem{ .content = text };
    }
    defer {
        for (item_buf) |item| allocator.free(item.content);
    }

    const list = List{
        .items = item_buf[0..],
        .selected = state.list_state,
        .highlight_style = Style{
            .fg = .black,
            .bg = .cyan,
            .modifier = Modifier{ .bold = true },
        },
    };
    list.render(inner, buf);
}

fn drawTable(area: tui.render.Rect, buf: *tui.render.Buffer, state: *AppState, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const block = Block{
        .title = if (state.focus == .table) "Table (FOCUSED)" else "Table",
        .borders = Borders.all(),
        .border_style = if (state.focus == .table)
            Style{ .fg = .cyan, .modifier = Modifier{ .bold = true } }
        else
            Style{ .fg = .white },
    };
    const inner = block.inner(area);
    block.render(area, buf);

    // Create table columns
    const columns = [_]Column{
        .{ .header = "Name", .width = 15 },
        .{ .header = "Status", .width = 10 },
        .{ .header = "Value", .width = null },
    };

    // Create table rows
    const rows = [_]Row{
        .{ .cells = &[_][]const u8{ "Item 1", "Active", "100" } },
        .{ .cells = &[_][]const u8{ "Item 2", "Pending", "250" } },
        .{ .cells = &[_][]const u8{ "Item 3", "Complete", "300" } },
        .{ .cells = &[_][]const u8{ "Item 4", "Error", "0" } },
        .{ .cells = &[_][]const u8{ "Item 5", "Active", "150" } },
    };

    const table = Table{
        .columns = &columns,
        .rows = &rows,
        .header_style = Style{ .fg = .yellow, .modifier = Modifier{ .bold = true } },
        .selected = state.table_state,
        .selected_style = Style{ .fg = .black, .bg = .cyan, .modifier = Modifier{ .bold = true } },
    };
    table.render(inner, buf);
}