mod netlink;
mod rdma;
mod stat;
mod tui;

use std::io;
use std::time::{Duration, Instant};

fn run_tui() -> io::Result<()> {
    crossterm::terminal::enable_raw_mode()?;
    let mut stdout = io::stdout();
    crossterm::execute!(stdout, crossterm::terminal::EnterAlternateScreen)?;

    let backend = ratatui::backend::CrosstermBackend::new(stdout);
    let mut terminal = ratatui::Terminal::new(backend)?;
    let mut app = tui::app::App::new();

    let interval = Duration::from_secs(1);
    let mut last_refresh = Instant::now() - interval;

    loop {
        if last_refresh.elapsed() >= interval {
            app.refresh_stats();
            last_refresh = Instant::now();
        }

        terminal.draw(|frame| tui::ui::draw(frame, &mut app))?;
        tui::events::handle_events(&mut app)?;

        if app.should_quit {
            break;
        }
    }

    crossterm::terminal::disable_raw_mode()?;
    crossterm::execute!(
        terminal.backend_mut(),
        crossterm::terminal::LeaveAlternateScreen
    )?;
    Ok(())
}

fn main() -> io::Result<()> {
    run_tui()
}
