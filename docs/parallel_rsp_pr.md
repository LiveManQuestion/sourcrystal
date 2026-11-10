# parallel-rsp pull request: keep the task running after the SP_STATUS polling timeout

Opened 2026-11-10 as https://github.com/Rosalie241/parallel-rsp/pull/1
(the text below is what was posted). See
the GB Tower section of `docs/stadium2.md` for the investigation.

- Base: `Rosalie241/parallel-rsp` branch `RMG` (`21e1d339`), the copy RMG
  bundles in `Source/3rdParty/mupen64plus-rsp-parallel`.
- Head: `LiveManQuestion/parallel-rsp` branch `gb-tower-status-timeout`
  (`e2f91759`). The same change is RMG commit `878d9487` on
  `LiveManQuestion/RMG` branch `gb-tower-rsp-resume`.
- Patch file: `tools/claude/stadium2/parallel_rsp_timeout.diff` (the same
  commit on libretro master `9ab776a`).
- Depends on mupen64plus-core #1202 to fix the GB Tower; on its own it changes
  nothing visible there.

## Title

Keep the task running after the SP_STATUS polling timeout

## Body

~~~
Pokémon Stadium and Pokémon Stadium 2 hang on a black screen in the GB Tower (their built-in Game Boy emulator) with parallel-rsp, after the Game Pak is chosen. cxd4 runs it once mupen64plus-core has mupen64plus/mupen64plus-core#1202. This is the parallel-rsp side ("parallel-rsp needs changes of its own", as mupen64plus/mupen64plus-core#1202 and the earlier mupen64plus/mupen64plus-core#1153 note).

### Cause

The GB Tower's RSP task never halts: it keeps polling SP_STATUS for work from the CPU. To get out of the run loop, `RSP_MFC0` sets `SP_STATUS_HALT` after `SP_STATUS_TIMEOUT` reads of SP_STATUS. `DoRspCycles` is meant to clear that HALT again before returning (the code from cxd4: "CPU restarts with the correct SIGs"), so the core can resume the task.

Since be05ef71 ("Fixed RSP hang when setting HALT but not BREAK"), `DoRspCycles` returns early whenever HALT is set. That is right for microcode that halts itself, but it also catches the HALT from the polling timeout, so the task stays halted, the core treats it as finished, and the GB Tower waits forever. On hardware the RSP only halts on BREAK, a SET_HALT write to SP_STATUS, or single-step, never while polling.

### Fix

`RSP_MFC0` sets a flag when the polling timeout sets HALT, and the early return skips HALTs from the timeout. Those fall through to the existing code that clears HALT, as before be05ef71. HALTs the microcode sets itself still return early.

### Testing

All with mupen64plus-core + mupen64plus/mupen64plus-core#1202:

- Pokémon Stadium 2 (US), RMG v0.9.1 with this change, parallel-rsp + softrdp: the GB Tower boots Pokémon Crystal (a ROM hack), continues a save, walks around and saves (main save copy's checksum valid). Before: black screen.
- The same with mupen64plus-ui-console and angrylion-rdp-plus. Without mupen64plus/mupen64plus-core#1202 it still hangs, with or without this change.
- Pokémon Stadium (US Rev 2), same RMG setup: the GB Tower boots Pokémon Red, continues a save, walks and saves (checksum valid). Before: black screen.
- Pokémon Stadium 2 outside the GB Tower, same RMG setup: menus, team select and several turns of a Battle Now! battle (moves, animations, a faint and a switch) work.
- n64-systemtest: same output before and after (it stops at "RSP BREAK" either way without the mupen64plus/mupen64plus-core#1153 core changes).
- 74 of PeterLemon's RSP, interrupt and RCP test ROMs with angrylion-rdp-plus: same screenshots before and after (73 pixel-identical, 1 blank in both).
- clang-format reports no changes. The ctest suite needs a mipsel toolchain and doesn't build `PARALLEL_INTEGRATION` code, so it doesn't cover this.

With this and mupen64plus/mupen64plus-core#1202 the GB Tower works but runs at about 62% speed with any RSP plugin; mupen64plus/mupen64plus-core#1204 fixes that in the ROM database (CountPerOp=1).
~~~

## Notes

- Not sent to libretro/parallel-rsp (yet). Its main user is
  mupen64plus-next, whose core also lacks #1202, and its PRs are slow (#16
  took about 15 months).
- Not mentioning be05ef71's author by name with `@`, to avoid notifying them.
