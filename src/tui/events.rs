use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use std::time::Duration;

use super::app::App;

pub fn handle_events(app: &mut App) -> std::io::Result<bool> {
    if !event::poll(Duration::from_millis(200))? {
        return Ok(false);
    }
    if let Event::Key(key) = event::read()? {
        if key.kind != KeyEventKind::Press {
            return Ok(false);
        }
        // Help toggle from any mode
        if key.code == KeyCode::Char('h') {
            app.show_help = !app.show_help;
            return Ok(true);
        }
        // Dismiss help with Esc
        if app.show_help {
            if key.code == KeyCode::Esc {
                app.show_help = false;
            }
            return Ok(true);
        }
        if app.show_detail {
            handle_detail_mode(app, key.code);
        } else {
            handle_normal_mode(app, key.code);
        }
        return Ok(true);
    }
    Ok(false)
}

fn handle_normal_mode(app: &mut App, key: KeyCode) {
    match key {
        KeyCode::Char('q') | KeyCode::Esc => app.should_quit = true,
        KeyCode::Up | KeyCode::Char('k') => app.move_up(),
        KeyCode::Down | KeyCode::Char('j') => app.move_down(),
        KeyCode::Enter => app.toggle_detail(),
        KeyCode::Char('t') => app.cycle_theme(),
        _ => {}
    }
}

fn handle_detail_mode(app: &mut App, key: KeyCode) {
    match key {
        KeyCode::Char('q') => app.should_quit = true,
        KeyCode::Esc | KeyCode::Enter => app.toggle_detail(),
        KeyCode::Up | KeyCode::Char('k') => app.detail_scroll_up(),
        KeyCode::Down | KeyCode::Char('j') => app.detail_scroll_down(app.detail_max_scroll),
        KeyCode::Char('t') => app.cycle_theme(),
        _ => {}
    }
}
