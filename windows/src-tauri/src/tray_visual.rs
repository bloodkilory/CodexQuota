use std::sync::OnceLock;
const SIZE: usize = 32;
fn font() -> &'static fontdue::Font {
    static FONT: OnceLock<fontdue::Font> = OnceLock::new();
    FONT.get_or_init(|| {
        fontdue::Font::from_bytes(
            include_bytes!("../assets/Inter.ttf") as &[u8],
            fontdue::FontSettings::default(),
        )
        .expect("embedded Inter font")
    })
}
pub fn color(source: &str) -> [u8; 3] {
    match source {
        "codex" => [51, 143, 116],
        "claude" => [204, 120, 92],
        _ => [77, 107, 254],
    }
}
pub fn render(text: &str, progress: Option<f64>, color: [u8; 3], stale: bool) -> Vec<u8> {
    let mut rgba = vec![0; SIZE * SIZE * 4];
    let blend = |rgba: &mut [u8], x: usize, y: usize, alpha: u8| {
        if x >= SIZE || y >= SIZE {
            return;
        }
        let p = &mut rgba[(y * SIZE + x) * 4..][..4];
        p[..3].copy_from_slice(&color);
        p[3] = p[3].max(alpha);
    };
    for y in 0..SIZE {
        for x in 0..SIZE {
            let mut alpha = 0.;
            for sy in 0..4 {
                for sx in 0..4 {
                    let dx = x as f64 + (sx as f64 + 0.5) / 4. - 16.;
                    let dy = y as f64 + (sy as f64 + 0.5) / 4. - 16.;
                    let radius = dx.hypot(dy);
                    if (13.2..=15.2).contains(&radius) {
                        let angle = dx.atan2(-dy).rem_euclid(std::f64::consts::TAU);
                        alpha += if progress.is_some_and(|p| {
                            angle <= p.clamp(0., 100.) / 100. * std::f64::consts::TAU
                        }) {
                            255.
                        } else {
                            46.
                        };
                    }
                }
            }
            blend(
                &mut rgba,
                x,
                y,
                (alpha / 16. * if stale { 0.5 } else { 1. }) as u8,
            );
        }
    }
    let px = if text.chars().count() >= 3 { 12.5 } else { 16. };
    let glyphs = text
        .chars()
        .map(|c| font().rasterize(c, px))
        .collect::<Vec<_>>();
    let width = glyphs.iter().map(|(m, _)| m.advance_width).sum::<f32>();
    let mut cursor = (32. - width) / 2.;
    for (metrics, bitmap) in glyphs {
        let top = (32 - metrics.height as i32) / 2;
        for y in 0..metrics.height {
            for x in 0..metrics.width {
                let dx = (cursor + metrics.xmin as f32).round() as i32 + x as i32;
                let dy = top + y as i32;
                if dx >= 0 && dy >= 0 {
                    blend(
                        &mut rgba,
                        dx as usize,
                        dy as usize,
                        (bitmap[y * metrics.width + x] as f32 * if stale { 0.55 } else { 1. })
                            as u8,
                    );
                }
            }
        }
        cursor += metrics.advance_width;
    }
    if stale {
        for y in 1..11 {
            for x in 23..32 {
                if (x as f64 - 27.).hypot(y as f64 - 5.5) < 4.3 {
                    let p = &mut rgba[(y * 32 + x) * 4..][..4];
                    p.copy_from_slice(&[24, 29, 34, 255]);
                }
            }
        }
        for y in [2, 3, 4, 5, 8] {
            blend(&mut rgba, 27, y, 255);
        }
    }
    rgba
}
#[derive(Clone, Copy, Debug, Default)]
pub struct BoxRect {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}
impl BoxRect {
    pub fn contains(&self, p: (f64, f64)) -> bool {
        p.0 >= self.x && p.1 >= self.y && p.0 <= self.x + self.w && p.1 <= self.y + self.h
    }
}
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Action {
    None,
    Show,
    Hide,
}
#[derive(Default)]
pub struct Hover {
    pub anchor: Option<BoxRect>,
    started: u64,
    pub visible: bool,
    outside: Option<u64>,
}
impl Hover {
    pub fn enter(&mut self, anchor: BoxRect, now: u64) {
        if self.anchor.is_none() {
            self.started = now;
        }
        self.anchor = Some(anchor);
        self.outside = None;
    }
    pub fn dismiss(&mut self) {
        self.anchor = None;
        self.visible = false;
        self.outside = None;
    }
    pub fn tick(&mut self, cursor: (f64, f64), card: BoxRect, now: u64) -> Action {
        let Some(anchor) = self.anchor else {
            return Action::None;
        };
        if anchor.contains(cursor) || (self.visible && card.contains(cursor)) {
            self.outside = None;
            if !self.visible && now.saturating_sub(self.started) >= 250 {
                self.visible = true;
                return Action::Show;
            }
        } else if self.visible {
            if now.saturating_sub(*self.outside.get_or_insert(now)) >= 350 {
                self.dismiss();
                return Action::Hide;
            }
        } else {
            self.dismiss();
        }
        Action::None
    }
}
pub fn position(anchor: BoxRect, work: BoxRect, size: (f64, f64)) -> (f64, f64) {
    let x = (anchor.x + anchor.w / 2. - size.0 / 2.)
        .clamp(work.x, (work.x + work.w - size.0).max(work.x));
    let y = if anchor.y - size.1 - 8. >= work.y {
        anchor.y - size.1 - 8.
    } else {
        anchor.y + anchor.h + 8.
    };
    (x, y.clamp(work.y, (work.y + work.h - size.1).max(work.y)))
}
