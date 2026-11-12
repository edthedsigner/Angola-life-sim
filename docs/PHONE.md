# The in-game phone ("Kianda 15")

An original device that follows modern iPhone design: flat aluminium frame, Dynamic Island, side buttons, earpiece slit,
rounded screen and a faint glass reflection. Its software ("KiandaOS") follows iOS conventions. No Apple logo, name or
artwork is used; the app icons, wallpaper (Luanda bay at sunset) and branding are drawn in code.

Screenshots: `docs/screenshots/phone_*.png` (real engine renders: desktop, and an emulated iPhone 13 with touch).

## Files
| File | Contents |
|---|---|
| `client/scripts/Phone.gd` | The system: lock screen, home pages + dock, gestures, Notification Centre, Control Centre, banners, Dynamic Island, alerts, action sheets, context menus, edit mode, app navigation stack |
| `client/scripts/phone/PhoneApps.gd` | The apps and home-screen widgets |
| `client/scripts/phone/PhoneKit.gd` | Light/dark palette, type scale, generated app icons and wallpaper, switch, slider, segmented control, status bar |
| `client/scripts/phone/PhoneFrame.gd` | The physical body (drawn under and over the screen) |

Everything is sized in points of a 393 pt-wide screen and scaled to the device size, so it is the same layout on a desktop
window and on a phone held upright.

## Gestures (mouse or finger)
| Gesture | Effect |
|---|---|
| Swipe up from the bottom edge | unlock / close the app (it shrinks back into its icon) |
| Swipe down from the top, left part | Notification Centre (marks notifications as read) |
| Swipe down from the top, right part | Control Centre |
| Swipe left / right on the home screen | change page |
| Swipe right from the left edge in an app | back |
| Long press an app icon | context menu (quick actions, "Editar ecrã principal") |
| Edit mode | icons jiggle; drag one onto another to swap them (pages or dock); "Concluído" ends it |
| Tap outside the device, `Esc`, `Tab` | close (Esc first closes menus, centres and pages) |

## What is real and what is cosmetic
* All game actions still go through the server (messages, friends, gifts, jobs, renting, privacy, logout).
* Notifications: lock screen, Notification Centre, a banner inside the phone, or a banner over the game when the phone is
  closed. Tapping one does what it says: opens the conversation, accepts or declines a request or invite in an alert, or calls back.
* **Não incomodar** suppresses banners (the notifications still arrive in the Notification Centre).
* Volume sets the game's master volume. Brightness dims the phone screen. The torch lights the area around your character
  (only on your screen).
* Status bar: game clock; "Sem serviço" when disconnected; signal bars from the measured server latency; Wi-Fi inside
  buildings, 4G outside. The battery is cosmetic: it drains while the phone is open, charges inside your rented home and never
  shuts the phone off.
* The Dynamic Island expands with a countdown while an activity runs (cooking, working…).
* Appearance: Automático (dark between 19:00 and 06:00 game time), Claro, Escuro.
* Settings, home-screen layout, battery, brightness and volume are saved per device in `user://phone.cfg`. They are not game state.

## Typing on a phone
When a text field gets focus on a touch screen, the device slides up so the field sits above the on-screen keyboard, and
conversations are anchored to the bottom like iMessage. The web build sends an `Esc` key when the virtual keyboard opens; while
a field is focused, `Esc` does not close the page.

## Known limits
* No real blur (the Godot Compatibility renderer has none); translucent colours are used instead.
* Emoji show as boxes: the engine's default font has no emoji glyphs.
* The `Enter` key of a real phone keyboard was not verified (the emulator's `Enter` does not reach the field); the send button works.
* Checked in Chromium with the iPhone 13 profile, not on a real iPhone.
