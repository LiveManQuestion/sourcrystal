# mupen64plus-core pull request: keep the Game Boy save's clock footer

Notes for revisiting the fix sent to mupen64plus (started 2026-10-18). See
also the "GB Tower" section of `docs/stadium2.md`.

## The bug

After using a Gold/Silver/Crystal save in Stadium 2's Transfer Pak, the game
asks to reset the clock when it's next played in a Game Boy emulator.

Game Boy emulators save an MBC3 cartridge that has a clock as the 32 KB of
cartridge RAM followed by a 48-byte RTC footer (clock registers, latched
registers and a Unix timestamp), so a Crystal `.sav` is 32816 bytes.
mupen64plus-core's `file_storage_save()` (`src/backends/file_storage.c`)
writes the whole storage with `write_to_file()` (`fopen "wb"`) on its first
access, which truncates the file to 32768 bytes. Later writes use
`write_chunk_to_file()` (`"rb+"`), which doesn't. The core doesn't use the
footer itself: its MBC3 RTC runs from the host clock.

Pokémon Red (cartridge type `$13`, no RTC) isn't affected: its saves are
exactly 32 KB.

## The fix

`tools/claude/stadium2/keep_save_footer.diff` (in this repo): a
`keep_trailing_data` flag in `struct file_storage`, set only by
`init_gb_ram()` (`src/main/main.c`). With it, the first access calls
`write_chunk_to_file(..., 0)` instead of `write_to_file()`, so data past the
storage size is kept. Other storages (EEPROM, SRAM, FlashRAM, mempak, 64DD)
still get truncated as before: the first version changed them all, and the
maintainer (Rosalie241) agreed limiting it to Game Boy RAM was safer.
`tools/claude/stadium2/build_core.sh` applies the diff to the core that
`play.sh` uses (an existing `.stadium2/core` needs the old diff reversed and
the new one applied by hand, then a rebuild).

## Where things are

- Upstream: https://github.com/mupen64plus/mupen64plus-core (patch made
  against master `ba95bab9`).
- The user's fork: https://github.com/LiveManQuestion/mupen64plus-core,
  cloned at `~/mupen64plus-core`. The fix is commit `ce8e90fb` "Don't
  truncate save files on their first write" on branch `keep-gb-save-footer`
  (pushed), then `883771ea` "Only keep trailing save data for Game Boy RAM"
for the review. Local `master` also has that commit; reset it with
  `git branch -f master origin/master` (from another branch) before syncing.
- Pull request: https://github.com/mupen64plus/mupen64plus-core/pull/1194,
  opened 2026-10-18 from `LiveManQuestion:keep-gb-save-footer`. Check its
  status and comments with
  `gh pr view 1194 --repo mupen64plus/mupen64plus-core --comments`. Changes asked for in review go on that branch.
- RMG (the GUI the user plays with) bundles its own core
  (`/usr/lib/RMG/Core/libmupen64plus.so`); RMG 0.9.0's copy
  (`Source/3rdParty/mupen64plus-core`) still has the bug. RMG picks up
  upstream core changes, so the fix reaches the GUI after an RMG release.
  Until then: `tail -c 48 X.sav > clock.bin` before, `cat clock.bin >> X.sav`
  after (only if the file is then 32768 bytes). RMG's config
  (`~/.config/RMG/mupen64plus.cfg`) points the Transfer Pak at
  `~/Desktop/sourcrystal/sourcrystal.sav`.

## Testing

Tested headlessly with the patched core, Stadium 2 (US) and vanilla Crystal
(`pokecrystal-master/pokecrystal.gbc` and `.sav`): run Stadium 2 until its
Game Pak check, quit with Escape, compare the save. The file stayed 32816
bytes and the footer was byte-identical. Also tested with `sourcrystal.gbc`
and with Red plus 48 appended bytes. Not run: the unpatched core on vanilla
Crystal (RMG's core can't open a window under Xvfb from the mupen64plus
console frontend: "SDL video subsystem init failed"), so the "before" size
comes from earlier runs with Sour Crystal.

The test script (in the session's scratchpad, may be gone):
`tools/claude/stadium2/run.sh OUT stadium2.z64 GBROM COPY.sav --corelib CORE
--rsp /usr/lib/RMG/Plugin/RSP/mupen64plus-rsp-cxd4.so --set
'rsp-cxd4[DisplayListToGraphicsPlugin]=True'` in the background, then
`snap.sh OUT a wait:35000 Return:300 wait:15000` and `xkey.py Escape`
(`DISPLAY=:77`, Xvfb running).

Stadium 2's Game Pak check also writes a 32-byte counting pattern
(`b5 c7 d9 eb ...`) to SRAM bank 0 `$A000-$A01F`. That's scratch space in Red
and Crystal, so it's harmless and unrelated to the clock.

## The PR description sent

Title: `Don't truncate save files on their first write`. Body: the bug
(first access uses `"wb"`, which truncates; a 32816-byte Crystal save loses
its 48-byte RTC footer and the game asks to reset its clock), the fix
(`write_chunk_to_file()` at offset 0), the test (Crystal US + Stadium 2 US:
32768 bytes before, 32816 and identical footer after), and the scope note
(all file storages; offered to limit it to Game Boy RAM).

## Review

- Rosalie241 (member) replied to the scope note: limiting it to Game Boy
  RAM "would be safer". Done in `883771ea`, retested (footer kept, only the
  32-byte Game Pak check pattern changed).
- Pushed 2026-10-18, PR retitled "Don't truncate Game Boy RAM files on
  their first write", and replied on the PR. Kept as two commits: upstream
  squash-merges.
- Merged 2026-10-18 as `902bc60f`. CI's "Windows x64 / MSYS2 MINGW64 GCC"
  job failed on the PR and after the merge, before building anything: its
  MSYS2 setup asks for `mingw-w64-x86_64-ntldd`, which MSYS2 no longer has
  (MINGW64 is deprecated). The other nine jobs passed.

## Follow-up pull requests (opened 2026-10-18)

Both made against upstream master `902bc60f`, one commit each, from the
fork's branches of the same name (local clone `~/mupen64plus-core`, remote
`upstream` = mupen64plus). `build_core.sh` applies both as diffs.

- https://github.com/mupen64plus/mupen64plus-core/pull/1195 "Mirror Game Boy
  cartridge banks past the end of ROM and RAM" (`gb-ram-mirroring`,
  `gb_ram_mirroring.diff`): out-of-range ROM/RAM banks mirror the start
  instead of returning nothing (Stadium 2's Game Pak check reads RAM bank 4).
- https://github.com/mupen64plus/mupen64plus-core/pull/1196 "Start the MBC3
  RTC at power on, not in 1970" (`gb-rtc-start-time`,
  `gb_rtc_start_time.diff`): `poweron_mbc3_rtc` set `last_time` to 0, which
  set the day carry bit, so Crystal in the GB Tower said the clock may be
  wrong.

Tests: `tools/claude/stadium2/gb_cart_test.c` (build line in its header;
upstream fails 10 mirroring and 5 RTC checks), plus Stadium 2 headless runs
(see `docs/stadium2.md`). Check status with
`gh pr view 1195 --repo mupen64plus/mupen64plus-core --comments` (and 1196).
Possible next change: load the RTC from the `.sav` footer so the clock
carries over from Game Boy emulators.
