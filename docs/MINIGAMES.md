# Multiplayer minigames

Implemented so far: **Jogo do Galo** (Tic-Tac-Toe, 1v1). Rock Paper Scissors and Memory come later, one at a time.

## How a match starts
1. Pick a game and an **online friend**, in either place:
   * Phone → **Jogos** → the game → **Convidar**;
   * a player's profile → **Jogar um jogo**.
2. The friend gets a notification with **Aceitar / Recusar**: as a banner, in the bell list, and in the phone.
3. Game invites **expire after 2 minutes** (`ANGOLA_GAME_INVITE_TTL`).
4. When the invite is accepted, the server creates the match and both players see the match panel. Whoever invited is X
   and moves first.

The server checks that:
* the players are friends and both are online;
* neither player is already in a match;
* the game exists.

These checks run again at the moment of acceptance: if the inviter has gone offline by then, the invite is cancelled.

## Server (authoritative)
`server_python/minigames.py`:
* **Shared infrastructure:**
  * matches, seats, turns and results;
  * rematch voting, forfeit, and disconnect grace (`ANGOLA_GAME_RECONNECT`, 60 s);
  * idle expiry (15 min) and clean-up.
* **Per-game rules:** the `TicTacToe` class. A new game is a new rules class added to `GAMES`, plus an entry in
  `shared/data/world.json` → `games`.
* **Every move is checked:**
  * the player belongs to the match;
  * the match is active;
  * it is the player's turn;
  * the cell is a valid, free 0–8;
  * the `seq` matches. Duplicate or stale moves are rejected.
* **State sent to players:** each participant receives `game_state` with public data only (`pub`, name, appearance),
  never internal ids. Other players never receive it.
* **Messages:** `game_move {mid, cell, seq}`, `game_leave {mid}`, `game_rematch {mid}`, `game_state_request`. The
  server replies with `game_state` and `game_error`.
* **Disconnects:**
  * the opponent sees "desligou · Ns";
  * coming back within the grace period restores the board;
  * otherwise the player who left loses by forfeit.
* **Rematch:** both players vote. The new match swaps seats (O becomes X) and keeps the series score.
* **Persistence:** matches live in memory. A server restart (deploy) ends any match in progress; nothing is saved to the
  database.

## Client
* **`client/scripts/MatchPanel.gd`:**
  * dark translucent panel with the world visible around it;
  * player cards with marks and a turn highlight, a status line, the 3×3 board (56–96 px cells) and the winning line;
  * Revanche, Sair and Desistir (Desistir asks for confirmation).
  * **Esc**, the "–" button or tapping the world **minimises** it to a pill at the top. This never forfeits.
* **Phone:** **Jogos** app. **Profile:** "Jogar um jogo".

## Tests
`tests/run_integration.py` → `minigame_tests` (32 checks): invites (success, decline, expiry, non-friend, unknown game,
busy, offline inviter), same board for both players, turn enforcement, occupied/invalid/stale moves, unauthorised
third player, win line, draw, rematch with swapped marks, disconnect/reconnect, forfeit by timeout, giving up, and
no rematch after the other player leaves.
