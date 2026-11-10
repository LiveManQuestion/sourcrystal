# mupen64plus-core pull request: CountPerOp=1 for Pokémon Stadium's GB Tower

Opened 2026-11-10 as https://github.com/mupen64plus/mupen64plus-core/pull/1204
(the text below is what was posted). Measurements are in the GB Tower section of `docs/stadium2.md`.

- Base: `mupen64plus/mupen64plus-core` `master` (`a9ca8ec0`).
- Head: `LiveManQuestion/mupen64plus-core` branch `stadium-countperop`
  (`94a382c8`).
- Independent of #1202: the slowdown shows on cxd4 too, once #1202 lets the
  GB Tower boot.

## Title

CountPerOp=1 for Pokémon Stadium's GB Tower

## Body

~~~
The GB Tower in Pokémon Stadium (Pocket Monsters Stadium 2 in Japan) and Pokémon Stadium 2 (Kin Gin) plays Game Boy games through an emulator running on the N64 CPU. With the default CountPerOp of 2, the N64 side still runs at 60 VI/s, but the Game Boy game and its audio run at about 62% speed.

Measured with the in-game clock of Pokémon Crystal (a ROM hack) over 60 s of standing still in the GB Tower (mupen64plus-ui-console, with #1202 so the GB Tower boots):

| CountPerOp | in-game time over 60 s |
|---|---|
| 2 (default) | 37.0 s |
| 1 | 59.97 s |
| default with this PR (no override) | 59.94 s |

The RSP plugin (cxd4, parallel-rsp, HLE with a fallback) and video plugin make no difference.

This sets `CountPerOp=1` on the main entry of every version with a GB Tower: Pokémon Stadium (U) V1.0/V1.1/V1.2, (E) V1.0/V1.1, (F), (G), (I), (S), Pocket Monsters Stadium 2 (J), Pocket Monsters Stadium Kin Gin (J) and Pokémon Stadium 2 (U), (E), (F), (G), (I), (S). The bad dumps and other variants inherit it through RefMD5. The original Pocket Monsters Stadium (J) has no GB Tower, so it's left alone.

Tested in RMG with CountPerOp 1 (US Pokémon Stadium Rev 2 with Pokémon Red, US Pokémon Stadium 2 with Pokémon Crystal): both GB Towers run at full speed, and battles in both games play normally.
~~~
