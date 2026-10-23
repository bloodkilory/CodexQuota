use quotanest_windows::tray_visual::{self, Action, BoxRect, Hover};
#[test]
fn ring_progress_and_brand_color_change_without_faking_unknown() {
    let full = tray_visual::render("82", Some(82.0), [204, 120, 92], false);
    let empty = tray_visual::render("0", Some(0.0), [204, 120, 92], false);
    let unknown = tray_visual::render("—", None, [204, 120, 92], false);
    assert_eq!(full.len(), 32 * 32 * 4);
    assert_ne!(full, empty);
    assert_ne!(empty, unknown);
    assert!(full
        .chunks(4)
        .any(|p| p[0] == 204 && p[1] == 120 && p[2] == 92 && p[3] > 240));
    assert_ne!(
        full,
        tray_visual::render("82", Some(82.0), [37, 99, 235], false)
    );
    assert_ne!(
        full,
        tray_visual::render("82", Some(82.0), [204, 120, 92], true)
    );
}
#[test]
fn hovering_into_card_stays_open_and_leaving_waits() {
    let mut hover = Hover::default();
    let icon = BoxRect {
        x: 900.,
        y: 730.,
        w: 20.,
        h: 20.,
    };
    let card = BoxRect {
        x: 680.,
        y: 250.,
        w: 340.,
        h: 470.,
    };
    hover.enter(icon, 0);
    assert_eq!(hover.tick((910., 740.), card, 200), Action::None);
    assert_eq!(hover.tick((910., 740.), card, 250), Action::Show);
    assert_eq!(hover.tick((900., 700.), card, 400), Action::None);
    assert_eq!(hover.tick((500., 500.), card, 500), Action::None);
    assert_eq!(hover.tick((500., 500.), card, 849), Action::None);
    assert_eq!(hover.tick((500., 500.), card, 850), Action::Hide);
    hover.enter(icon, 900);
    hover.dismiss();
    assert_eq!(hover.tick((910., 740.), card, 1500), Action::None);
}
#[test]
fn hover_placement_respects_work_area_and_negative_monitor_coordinates() {
    let work = BoxRect {
        x: -1920.,
        y: 0.,
        w: 1920.,
        h: 1040.,
    };
    let icon = BoxRect {
        x: -20.,
        y: 1040.,
        w: 20.,
        h: 20.,
    };
    let (x, y) = tray_visual::position(icon, work, (340., 470.));
    assert!(x >= work.x && x + 340. <= work.x + work.w);
    assert!(y >= 0. && y + 470. <= 1040.);
}
