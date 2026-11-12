# The in-game phone ("Kianda 15")

It looks like a modern iPhone and works like a simple in-game menu. It's an original device: no Apple logo, names or
artwork. The app icons, wallpaper (Luanda bay at sunset) and branding are drawn in code.

Screenshots: `docs/screenshots/phone_*.png`. These are real engine renders on desktop and on an emulated iPhone 13 with touch.

## How it works
* **Opening:** goes straight to the home screen, with no lock screen or unlocking. Open it with `Tab` or the phone button in the HUD.
* **Home screen:** a widget (day, place, time, money) and four apps (Emprego, Imóveis, Negócios, Governo). Below them is a
  needs widget (rings), and the dock holds Mensagens, Amigos, Banco and Definições. Red badges show unread messages and friend requests.
* **Apps:** a tap opens one (it zooms out of its icon). Every page has a back button at the top left; on an app's first
  page it reads "‹ Início".
* **Home:** the bar at the bottom of the screen (the iPhone home indicator, with a large tap area) always returns to the
  home screen. On the home screen it closes the phone.
* **Closing:** tap outside the phone, `Esc` (it first closes an alert, then a page, then the app), or `Tab`.
* **Moving between apps:** contacts have Mensagem / Ligar / Perfil, and notification banners open the right conversation or ask
  to accept a request or invite.
* **Gestures:** the only one is dragging lists to scroll, with mouse or finger. There are no swipe-to-close, app switcher,
  Control Centre or Notification Centre.

## What each app is for
| App | Gameplay |
|---|---|
| Mensagens | private conversations (iMessage-style bubbles) and "Perto de ti", the proximity chat |
| Amigos | friend requests, online/offline friends, contact page (message, call, profile, remove, block) |
| Banco | balance and transactions (open one for details) |
| Emprego | current job, quit, apply for vacancies |
| Imóveis | housing status and renting (with confirmation) |
| Negócios | "coming soon" |
| Governo | ID card and life story |
| Definições | Não incomodar, appearance (automatic dark at night in game time), call privacy, blocked players, volume (game master volume), brightness, technical info (F3), log out |

Every game action goes through the server; the phone never changes game state locally. Notifications appear as a banner
inside the phone, or over the game when the phone is closed, unless Não incomodar is on. The full list stays in the HUD bell.

## Details
* The status bar shows the game clock and signal bars from the measured server latency. It shows Wi-Fi inside buildings and 4G
  outside, and "Sem serviço" when disconnected.
* The Dynamic Island expands with a countdown while an activity runs (cooking, working…).
* Typing on a touch screen: the phone slides up so the text field sits above the on-screen keyboard. Conversations stay
  anchored to the bottom. The web build sends an `Esc` when the virtual keyboard opens; while a field is focused, `Esc` does
  not close the page.
* Preferences (appearance, Não incomodar, brightness, volume) are saved per device in `user://phone.cfg`; they are not game state.

## Files
| File | Contents |
|---|---|
| `client/scripts/Phone.gd` | home screen, dock, status bar, Dynamic Island, app window and page navigation, alerts and action sheets, banners, tap and scroll |
| `client/scripts/phone/PhoneApps.gd` | the apps and the two widgets |
| `client/scripts/phone/PhoneKit.gd` | light/dark palette, type scale, generated icons and wallpaper, switch, slider, status bar |
| `client/scripts/phone/PhoneFrame.gd` | the physical body (frame, side buttons, glass, rounded screen, reflection) |

## Known limits
* Emoji show as boxes: the engine's default font has no emoji glyphs.
* There is no real blur (the Compatibility renderer has none), so translucent colours are used instead.
* Checked in Chromium with the iPhone 13 profile, not on a physical iPhone. The keyboard's Return key was not verified; the send button works.
