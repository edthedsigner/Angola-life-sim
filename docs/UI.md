# Game UI — design system and interface map

Everything except the phone (which keeps its own iPhone-style system, see `docs/PHONE.md`) and the F3 debug overlay.
Principle: **the world stays alive in the background.** Interfaces float above the game on dark translucent surfaces; nothing
ordinary replaces the world with a solid screen.

Screenshots (real engine renders): `docs/screenshots/ui_*.png`.

## Design system
| Piece | Where | Notes |
|---|---|---|
| Tokens: colours, radii, touch size, type weights | `client/scripts/UIStyle.gd` | charcoal surfaces at 78–94 % opacity, 1 px light stroke, soft shadow, gold accent `GOLD`, need colours |
| Theme | `UIStyle.make_theme()` | applied to the HUD and to the menus (`Main.gd`); button variations `PrimaryButton` (gold), default (secondary), `GhostButton`, `DangerButton`; rounded fields, thin scrollbars, tooltips |
| Components | `client/scripts/ui/UIKit.gd` | label/title/caption, icon, button, round icon button, badge, chip, progress bar, card, avatar (the real character layers in a rounded frame, optional online dot), empty state, item icons and item descriptions |

Type: the engine's sans-serif with weights (medium, semibold, bold). Touch targets ≥ 44 px. Sizes stay in pixels; on phones the
game already uses 1 UI px = 1 CSS px.

## Interface map (audit → presentation → data and actions)
| Interface | Presentation | Data | Actions (all sent to the server) |
|---|---|---|---|
| Player card (always visible) | top-left floating card | name, appearance, level and XP (`self_state.level`), mood/activity, 4 needs, location on phones | — |
| World strip (always visible) | top-right card (under the card on narrow screens) | day and time (game clock), balance, location | — |
| Dock | bottom-right capsule | unread notifications and messages (badges) | chat, backpack, notifications, phone |
| Zoom | bottom-left capsule, + / − | — | camera zoom (also wheel, pinch, `+`/`-`) |
| Floor picker (multi-floor buildings) | left capsule, gold = current floor | floors of the building | change floor |
| Context prompt | gold pill, bottom centre | nearest door/exit/furniture | interact |
| Activity in progress | compact card, bottom centre | label, progress, % | cancel |
| Object actions | compact popover above the prompt | activities of the object, cost / "casa arrendada" / "emprego aqui" chips, effects in tooltip | start activity, open shop / sell |
| Shop / Sell | floating sheet above the dock (bottom sheet on phones) | item icons, descriptions from the item data, prices, balance | buy (disabled with reason if no money), sell 1 |
| Backpack | same sheet; 4-column item grid + detail card | quantities, total, balance, item description | consume (disabled with reason if not edible), offer to a friend (confirmation) |
| Notifications | same sheet | "Novas"/"Anteriores", unread dots, relative times, kind icons | accept/decline requests and invites, open conversation, call back |
| Quick chat (nearby) | card above the bottom controls | last 4 nearby messages | send; "Conversas" opens the phone's Mensagens |
| Player profile | floating panel on the right (bottom sheet on phones) | avatar, level, relationship chip, online status, public status, since, friend count | add / accept / decline / cancel friend; message; call (disabled with reason); invite home or to a public place; gift money (presets + amount) or an item; play (disabled until games exist); remove friend and block in a separate danger zone with confirmation; unblock |
| Voice call | floating card, top centre | name, state, timer, mic level | answer / decline / cancel / mute / hang up |
| Confirmation dialog | centred, light dim | — | used for remove friend, block, gifts |
| Toasts | small card, top centre | server notices, errors (red outline) | — |
| Menus (login, register, story, character, overlays) | translucent cards over the live menu world | — | unchanged |

Dismissing: every sheet and panel has a close button; `Esc` closes the top layer only (dialog → profile → phone → sheet →
chat); tapping the world closes open sheets. Sheets never cover the player card, the world strip, the dock or the zoom; on phones
they become bottom sheets between them and scroll.

## Decisions to review
* **Thirst:** the brief lists Hunger, Thirst, Health and Energy, but the game has no thirst mechanic. Its four needs are
  Fome, Energia, Higiene and Saúde (water restores hunger and health). The HUD shows the four that exist; adding thirst would be
  a new mechanic (server needs, decay, items), so it is left for your decision.
* **Camera recentring:** the camera always follows the player, so there is nothing to recentre; no button was added.
* The phone's own banners and the phone are unchanged.

## Not verified
* The voice-call card was not exercised in this pass (it needs two browsers with microphones); it uses the same components.
* Checked on desktop Chromium and the emulated iPhone 13, not on a physical phone.
