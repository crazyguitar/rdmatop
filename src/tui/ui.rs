use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Cell, Clear, Paragraph, Row, Table, TableState},
    Frame,
};

use super::app::{App, CounterRate, PortThroughput};
use super::theme::ThemeColors;

const HELP_KEYS: &[(&str, &str)] = &[
    ("↑ / k", "Move up"),
    ("↓ / j", "Move down"),
    ("Enter", "Toggle detail panel"),
    ("Esc", "Close detail / quit"),
    ("t", "Cycle theme"),
    ("h", "Toggle this help"),
    ("q", "Quit"),
    ("", ""),
    ("", "── Detail mode ──"),
    ("↑ / k", "Scroll up"),
    ("↓ / j", "Scroll down"),
    ("", "Scroll past end → next device"),
    ("", "Scroll past top  → prev device"),
];

const RDMA_LINK_GBPS: f64 = 100.0;
const BAR_WIDTH: usize = 12;

pub fn draw(frame: &mut Frame, app: &mut App) {
    let tc = app.theme.colors();

    if tc.bg != ratatui::style::Color::Reset {
        frame.render_widget(
            Block::default().style(Style::default().bg(tc.bg)),
            frame.area(),
        );
    }

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(6),
            Constraint::Min(5),
            Constraint::Length(1),
        ])
        .split(frame.area());

    draw_header(frame, app, chunks[0], &tc);
    draw_body(frame, app, chunks[1], &tc);
    draw_status_bar(frame, app, chunks[2], &tc);

    if app.show_help {
        draw_help_popup(frame, &tc);
    }
}

fn draw_body(frame: &mut Frame, app: &mut App, area: Rect, tc: &ThemeColors) {
    if app.show_detail {
        let split = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
            .split(area);
        draw_table(frame, app, split[0], tc);
        draw_detail(frame, app, split[1], tc);
    } else {
        draw_table(frame, app, area, tc);
    }
}

fn header_line1(app: &App, tc: &ThemeColors) -> Line<'static> {
    Line::from(vec![
        styled(" rdmatop ", tc.accent, true),
        styled(
            &format!(
                "- {} │ {} │ load average: {}",
                app.sysinfo.hostname, app.sysinfo.uptime, app.sysinfo.load_avg
            ),
            tc.muted,
            false,
        ),
    ])
}

fn header_line2(app: &App, tc: &ThemeColors) -> Line<'static> {
    let n = app.throughputs.len();
    let total_tx: f64 = app.throughputs.iter().map(|t| t.tx_gbps).sum();
    let total_rx: f64 = app.throughputs.iter().map(|t| t.rx_gbps).sum();
    let total_drops: f64 = app.throughputs.iter().map(|t| t.rx_drops_per_sec).sum();
    let drop_color = if total_drops > 0.0 {
        tc.error
    } else {
        tc.muted
    };

    Line::from(vec![
        styled(
            &format!(" RDMA: {} device{}", n, if n == 1 { "" } else { "s" }),
            tc.fg,
            false,
        ),
        styled(" │ TX: ", tc.muted, false),
        styled(&format!("{:.2} Gbps", total_tx), tc.good, false),
        styled(" │ RX: ", tc.muted, false),
        styled(&format!("{:.2} Gbps", total_rx), tc.good, false),
        styled(" │ Drops: ", tc.muted, false),
        styled(&format!("{:.0}/s", total_drops), drop_color, false),
        styled(
            &format!(" │ {:.1}s │ theme: {}", app.elapsed, app.theme.label()),
            tc.muted,
            false,
        ),
    ])
}

fn cpu_bar(pct: f32, width: usize, tc: &ThemeColors) -> Vec<Span<'static>> {
    let filled = ((pct / 100.0) * width as f32).round() as usize;
    let empty = width.saturating_sub(filled);
    let color = if pct > 80.0 {
        tc.error
    } else if pct > 50.0 {
        tc.warning
    } else {
        tc.good
    };
    vec![
        styled("[", tc.muted, false),
        styled(&"|".repeat(filled), color, false),
        styled(&" ".repeat(empty), tc.muted, false),
        styled(&format!("{:>5.1}%]", pct), color, false),
    ]
}

fn mem_bar(used: u64, total: u64, pct: f32, width: usize, tc: &ThemeColors) -> Vec<Span<'static>> {
    let filled = ((pct / 100.0) * width as f32).round() as usize;
    let empty = width.saturating_sub(filled);
    let color = if pct > 80.0 {
        tc.error
    } else if pct > 50.0 {
        tc.warning
    } else {
        tc.good
    };
    let label = if total >= 1024 {
        format!("{:.1}/{:.1}G]", used as f64 / 1024.0, total as f64 / 1024.0)
    } else {
        format!("{}/{}M]", used, total)
    };
    vec![
        styled("[", tc.muted, false),
        styled(&"|".repeat(filled), color, false),
        styled(&" ".repeat(empty), tc.muted, false),
        styled(&label, color, false),
    ]
}

fn header_line3(app: &App, tc: &ThemeColors) -> Line<'static> {
    let s = &app.sysinfo;
    let mut spans = vec![styled(" CPU ", tc.muted, false)];
    spans.extend(cpu_bar(s.cpu_pct, 20, tc));
    spans.push(styled("  Mem ", tc.muted, false));
    spans.extend(mem_bar(s.mem_used_mb, s.mem_total_mb, s.mem_pct, 20, tc));
    spans.push(styled("  Net ", tc.muted, false));
    spans.push(styled(
        &format!(
            "↓{}/s ↑{}/s",
            fmt_bytes_short(s.net.rx_bytes_per_sec),
            fmt_bytes_short(s.net.tx_bytes_per_sec),
        ),
        tc.fg,
        false,
    ));
    Line::from(spans)
}

fn draw_header(frame: &mut Frame, app: &App, area: Rect, tc: &ThemeColors) {
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(tc.border));
    let lines = vec![
        header_line1(app, tc),
        header_line2(app, tc),
        header_line3(app, tc),
    ];
    frame.render_widget(Paragraph::new(lines).block(block), area);
}

fn gbps_bar(gbps: f64) -> String {
    let ratio = (gbps / RDMA_LINK_GBPS).clamp(0.0, 1.0);
    let filled = (ratio * BAR_WIDTH as f64).round() as usize;
    format!("{}{}", "█".repeat(filled), "░".repeat(BAR_WIDTH - filled))
}

fn throughput_to_row(t: &PortThroughput, tc: &ThemeColors) -> Row<'static> {
    let tx_c = gbps_color(t.tx_gbps, tc);
    let rx_c = gbps_color(t.rx_gbps, tc);
    let drop_c = if t.rx_drops_per_sec > 0.0 {
        tc.error
    } else {
        tc.muted
    };

    Row::new(vec![
        Cell::from(t.dev_name.clone()).style(Style::default().fg(tc.fg)),
        Cell::from(t.port.to_string()).style(Style::default().fg(tc.muted)),
        Cell::from(gbps_bar(t.tx_gbps)).style(Style::default().fg(tx_c)),
        Cell::from(format!("{:.2}", t.tx_gbps)).style(Style::default().fg(tx_c)),
        Cell::from(gbps_bar(t.rx_gbps)).style(Style::default().fg(rx_c)),
        Cell::from(format!("{:.2}", t.rx_gbps)).style(Style::default().fg(rx_c)),
        Cell::from(format_pps(t.tx_pkts_per_sec)).style(Style::default().fg(tc.fg)),
        Cell::from(format_pps(t.rx_pkts_per_sec)).style(Style::default().fg(tc.fg)),
        Cell::from(format!("{:.0}", t.rx_drops_per_sec)).style(Style::default().fg(drop_c)),
    ])
}

fn draw_table(frame: &mut Frame, app: &mut App, area: Rect, tc: &ThemeColors) {
    let header = Row::new([
        "Device", "Port", "TX ▏", "TX Gbps", "RX ▏", "RX Gbps", "TX pps", "RX pps", "Drops/s",
    ])
    .style(
        Style::default()
            .fg(tc.header_fg)
            .add_modifier(Modifier::BOLD),
    )
    .height(1);

    let rows: Vec<Row> = app
        .throughputs
        .iter()
        .map(|t| throughput_to_row(t, tc))
        .collect();

    let widths = [
        Constraint::Length(16),
        Constraint::Length(6),
        Constraint::Length(BAR_WIDTH as u16),
        Constraint::Length(9),
        Constraint::Length(BAR_WIDTH as u16),
        Constraint::Length(9),
        Constraint::Length(10),
        Constraint::Length(10),
        Constraint::Length(9),
    ];

    let table = Table::new(rows, widths)
        .header(header)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(tc.border))
                .title(" RDMA Throughput ")
                .title_style(Style::default().fg(tc.accent)),
        )
        .row_highlight_style(
            Style::default()
                .bg(tc.highlight_bg)
                .add_modifier(Modifier::BOLD),
        )
        .highlight_symbol("▶ ");

    let mut state = TableState::default();
    if !app.throughputs.is_empty() {
        state.select(Some(app.selected_row));
    }
    frame.render_stateful_widget(table, area, &mut state);
}

const DETAIL_COUNTERS: &[&str] = &[
    "send_bytes",
    "send_wrs",
    "recv_bytes",
    "recv_wrs",
    "rdma_write_bytes",
    "rdma_write_wrs",
    "rdma_write_wr_err",
    "rdma_write_recv_bytes",
    "rdma_read_bytes",
    "rdma_read_wrs",
    "rdma_read_wr_err",
    "rdma_read_resp_bytes",
    "retrans_bytes",
    "retrans_pkts",
    "retrans_timeout_events",
    "unresponsive_remote_events",
    "impaired_remote_conn_events",
];

fn sparkline_str(data: &[f64], width: usize) -> String {
    const BARS: &[char] = &[' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];
    let max = data.iter().cloned().fold(0.0f64, f64::max).max(0.01);
    let start = data.len().saturating_sub(width);
    let mut s = String::with_capacity(width);
    for &v in &data[start..] {
        let idx = ((v / max) * 8.0).round() as usize;
        s.push(BARS[idx.min(8)]);
    }
    // Pad if not enough data
    while s.chars().count() < width {
        s.insert(0, ' ');
    }
    s
}

fn build_detail_lines(
    t: &PortThroughput,
    procs: &[&crate::stat::ProcessRdmaInfo],
    history: Option<&super::app::DeviceHistory>,
    tc: &ThemeColors,
) -> Vec<Line<'static>> {
    let mut lines = build_device_header(t, history, tc);
    append_active_counters(&mut lines, t, tc);
    append_process_table(&mut lines, procs, tc);
    lines
}

fn build_device_header(
    t: &PortThroughput,
    history: Option<&super::app::DeviceHistory>,
    tc: &ThemeColors,
) -> Vec<Line<'static>> {
    let spark_w = 30;
    let (tx_spark, rx_spark) = match history {
        Some(h) => (sparkline_str(&h.tx, spark_w), sparkline_str(&h.rx, spark_w)),
        None => (" ".repeat(spark_w), " ".repeat(spark_w)),
    };
    vec![
        Line::from(vec![
            styled(" Device: ", tc.muted, false),
            styled(&format!("{}/{}", t.dev_name, t.port), tc.accent, true),
        ]),
        Line::from(vec![
            styled(" TX: ", tc.muted, false),
            styled(&format!("{:.2} Gbps ", t.tx_gbps), tc.good, false),
            styled(&tx_spark, tc.good, false),
        ]),
        Line::from(vec![
            styled(" RX: ", tc.muted, false),
            styled(&format!("{:.2} Gbps ", t.rx_gbps), tc.accent, false),
            styled(&rx_spark, tc.accent, false),
        ]),
        Line::from(""),
    ]
}

fn append_active_counters(lines: &mut Vec<Line<'static>>, t: &PortThroughput, tc: &ThemeColors) {
    let counters: Vec<_> = t
        .counter_rates
        .iter()
        .filter(|r| DETAIL_COUNTERS.contains(&r.name.as_str()))
        .collect();
    if !counters.is_empty() {
        for r in &counters {
            lines.push(counter_rate_line(r, tc));
        }
        lines.push(Line::from(""));
    }
}

const PROC_HEADER: &str =
    "  PID     USER     NI S     VIRT      RES    SHR  MEM%   QPs  THR COMMAND";

fn append_process_table(
    lines: &mut Vec<Line<'static>>,
    procs: &[&crate::stat::ProcessRdmaInfo],
    tc: &ThemeColors,
) {
    lines.push(Line::from(vec![styled(PROC_HEADER, tc.header_fg, true)]));
    if procs.is_empty() {
        lines.push(Line::from(styled("  (no RDMA processes)", tc.muted, false)));
    } else {
        for p in procs {
            lines.push(process_line(p, tc));
        }
    }
}

fn process_line(p: &crate::stat::ProcessRdmaInfo, tc: &ThemeColors) -> Line<'static> {
    let state_color = match p.state {
        'R' => tc.good,
        'S' | 'I' => tc.muted,
        'D' => tc.warning,
        'Z' | 'T' => tc.error,
        _ => tc.fg,
    };
    Line::from(vec![
        styled(&format!("  {:<7}", p.pid), tc.accent, false),
        styled(&format!(" {:<8}", truncate(&p.user, 8)), tc.fg, false),
        styled(&format!(" {:<2}", p.nice), tc.muted, false),
        styled(&format!(" {:>1}", p.state), state_color, false),
        styled(&format!(" {:>8}", fmt_mem_kb(p.virt_kb)), tc.fg, false),
        styled(&format!(" {:>8}", fmt_mem_kb(p.res_kb)), tc.good, false),
        styled(&format!(" {:>6}", fmt_mem_kb(p.shr_kb)), tc.fg, false),
        styled(&format!(" {:>4.1}", p.mem_pct), tc.fg, false),
        styled(&format!(" {:>5}", p.qp_count), tc.accent, false),
        styled(&format!(" {:>4}", p.threads), tc.muted, false),
        styled(&format!(" {}", truncate(&p.cmdline, 40)), tc.fg, false),
    ])
}

fn draw_detail(frame: &mut Frame, app: &mut App, area: Rect, tc: &ThemeColors) {
    let Some(t) = app.selected_throughput().cloned() else {
        frame.render_widget(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(tc.border))
                .title(" Detail "),
            area,
        );
        return;
    };

    let history = app.history.get(&t.dev_name);
    let procs = app.selected_device_processes();
    let lines = build_detail_lines(&t, &procs, history, tc);

    let visible = area.height.saturating_sub(2);
    app.detail_max_scroll = (lines.len() as u16).saturating_sub(visible);

    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(tc.border))
        .title(format!(" {} ", t.dev_name))
        .title_style(Style::default().fg(tc.accent).add_modifier(Modifier::BOLD));

    frame.render_widget(
        Paragraph::new(lines)
            .block(block)
            .scroll((app.detail_scroll, 0)),
        area,
    );
}

fn counter_rate_line(r: &CounterRate, tc: &ThemeColors) -> Line<'static> {
    let rate_str = if r.is_bytes {
        format_bytes(r.rate)
    } else {
        format_rate(r.rate)
    };
    let color = counter_color(r, tc);

    Line::from(vec![
        Span::styled(format!("  {:<35}", r.name), Style::default().fg(tc.fg)),
        Span::styled(format!("{:>12}", rate_str), Style::default().fg(color)),
        Span::styled(format!("  Δ {}", r.delta), Style::default().fg(tc.muted)),
    ])
}

fn counter_color(r: &CounterRate, tc: &ThemeColors) -> ratatui::style::Color {
    let is_error = r.name.contains("err") || r.name.contains("drop");
    let is_warn = r.name.contains("retrans")
        || r.name.contains("unresponsive")
        || r.name.contains("impaired");

    match (r.delta > 0, is_error, is_warn) {
        (true, true, _) => tc.error,
        (true, _, true) => tc.warning,
        (true, _, _) => tc.good,
        _ => tc.muted,
    }
}

fn draw_status_bar(frame: &mut Frame, app: &App, area: Rect, tc: &ThemeColors) {
    let hint = if app.show_detail {
        "Enter/Esc:close"
    } else {
        "Enter:detail"
    };
    let line = Line::from(vec![
        Span::styled(
            " NORMAL ",
            Style::default()
                .fg(tc.status_fg)
                .bg(tc.status_bg)
                .add_modifier(Modifier::BOLD),
        ),
        Span::styled(
            format!(" ↑↓/jk:nav  {}  t:theme  h:help  q:quit", hint),
            Style::default().fg(tc.muted),
        ),
    ]);
    frame.render_widget(Paragraph::new(line), area);
}

fn draw_help_popup(frame: &mut Frame, tc: &ThemeColors) {
    let area = frame.area();
    let w = 50.min(area.width.saturating_sub(4));
    let h = 18.min(area.height.saturating_sub(4));
    let popup = centered_rect(area, w, h);

    frame.render_widget(Clear, popup);

    let lines: Vec<Line> = HELP_KEYS
        .iter()
        .map(|(key, desc)| help_line(key, desc, tc))
        .collect();

    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(tc.accent))
        .title(" Help (h/Esc to close) ")
        .title_style(Style::default().fg(tc.accent).add_modifier(Modifier::BOLD));

    frame.render_widget(Paragraph::new(lines).block(block), popup);
}

fn help_line(key: &str, desc: &str, tc: &ThemeColors) -> Line<'static> {
    if key.is_empty() {
        Line::from(styled(&format!("  {}", desc), tc.group_title, false))
    } else {
        Line::from(vec![
            styled(&format!("  {:<14}", key), tc.accent, false),
            styled(desc, tc.fg, false),
        ])
    }
}

fn centered_rect(area: Rect, w: u16, h: u16) -> Rect {
    Rect::new(
        area.x + (area.width.saturating_sub(w)) / 2,
        area.y + (area.height.saturating_sub(h)) / 2,
        w,
        h,
    )
}

fn styled(text: &str, color: ratatui::style::Color, bold: bool) -> Span<'static> {
    let s = Style::default().fg(color);
    Span::styled(
        text.to_string(),
        if bold {
            s.add_modifier(Modifier::BOLD)
        } else {
            s
        },
    )
}

fn fmt_bytes_short(bps: f64) -> String {
    if bps >= 1_000_000_000.0 {
        format!("{:.1}G", bps / 1_000_000_000.0)
    } else if bps >= 1_000_000.0 {
        format!("{:.1}M", bps / 1_000_000.0)
    } else if bps >= 1_000.0 {
        format!("{:.1}K", bps / 1_000.0)
    } else {
        format!("{:.0}B", bps)
    }
}

fn format_bytes(bps: f64) -> String {
    if bps >= 1_073_741_824.0 {
        format!("{:.2} GB/s", bps / 1_073_741_824.0)
    } else if bps >= 1_048_576.0 {
        format!("{:.2} MB/s", bps / 1_048_576.0)
    } else if bps >= 1024.0 {
        format!("{:.2} KB/s", bps / 1024.0)
    } else {
        format!("{:.0} B/s", bps)
    }
}

fn format_pps(pps: f64) -> String {
    if pps >= 1_000_000.0 {
        format!("{:.2}M", pps / 1_000_000.0)
    } else if pps >= 1_000.0 {
        format!("{:.1}K", pps / 1_000.0)
    } else {
        format!("{:.0}", pps)
    }
}

fn format_rate(rate: f64) -> String {
    if rate >= 1_000_000.0 {
        format!("{:.2}M/s", rate / 1_000_000.0)
    } else if rate >= 1_000.0 {
        format!("{:.1}K/s", rate / 1_000.0)
    } else {
        format!("{:.1}/s", rate)
    }
}

fn gbps_color(gbps: f64, tc: &ThemeColors) -> ratatui::style::Color {
    if gbps >= 10.0 {
        tc.good
    } else if gbps >= 1.0 {
        tc.warning
    } else {
        tc.muted
    }
}

fn fmt_mem_kb(kb: u64) -> String {
    if kb >= 1_048_576 {
        format!("{:.1}G", kb as f64 / 1_048_576.0)
    } else if kb >= 1024 {
        format!("{:.0}M", kb as f64 / 1024.0)
    } else {
        format!("{}K", kb)
    }
}

fn truncate(s: &str, max: usize) -> String {
    if s.len() <= max {
        s.to_string()
    } else {
        format!("{}…", &s[..max - 1])
    }
}
