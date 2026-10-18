CheckCurPartyMonFainted:
	ld hl, wPartyMon1HP
	ld de, PARTYMON_STRUCT_LENGTH
	ld b, $0
.loop
	ld a, [wCurPartyMon]
	cp b
	jr z, .skip
	ld a, [hli]
	or [hl]
	jr nz, .notfainted
	dec hl

.skip
	inc b
	ld a, [wPartyCount]
	cp b
	jr z, .done
	add hl, de
	jr .loop

.done
	scf
	ret

.notfainted
	and a
	ret

SwapStorageBoxSlots:
; Swaps slots from de to bc. Preserves de, while bc is changed to a proper slot
; if c is 0, otherwise preserved. Equivalent to bc->de except c may be 0 to mean
; "put anywhere in the party/box". Returns the following in a:
; 0: Successful swap
; 1: Save is required to perform the swap
; 2: The party is full
; 3: The box is full
; 4: Doing this would remove the last healthy mon in party
; 5: Can't move partymon to Box, because they're holding Mail.
	; Compare source->dest to see if we're "moving" something with itself.
	ld h, -1
	ld a, b
	cp d
	ld a, c
	jr nz, .not_equal
	ld h, e
	cp e
	jr nz, .not_equal
.done
	xor a
	ret
.not_equal
	; Convert destination slot 0 to a real destination, if we can.
	push de
	; a is c from beforehand.
	and a
	jr nz, .got_dest

	ld e, PARTY_LENGTH
	ld a, b
	and a
	jr z, .dest_loop
	ld e, MONS_PER_BOX
.dest_loop
	inc c
	call GetStorageBoxMon
	jr z, .got_dest
	ld a, c
	cp h
	jr nz, .dest_next

	; We encountered our current entry while seeking for blank entries. This
	; basically makes this a no-op (since there's no earlier blank entry), so
	; return early.
	pop de
	jr .done

.dest_next
	cp e
	jr nz, .dest_loop

	; Party (or Box) is full
	pop de
	cp MONS_PER_BOX
	ld a, 2
	ret c
	inc a
	ret

.got_dest
	pop de

	; Now that we have proper slots, preserve bcde from this point.
	push de
	push bc
	call .do_it
	pop bc
	pop de
	ret

.do_it
	; If d<b, swap bc and de. The reason for this is that we want to handle
	; party->box movement the same way as box->party.
	ld a, d
	cp b
	jr nc, .dont_swap
	push bc
	ld b, d
	ld c, e
	pop de
.dont_swap
	; At this point, b<=d. So if d is party, we're swapping party members, and
	; if b is nonparty (i.e. >0), we're swapping between box slots.
	; Otherwise, we're swapping a party slot bc to box slot de.
	ld a, d
	and a
	jr z, .party_swap
	ld a, b
	and a
	jr nz, .box_swap

	; We're swapping a party and box slot. First, verify that we're not losing
	; our last healthy mon and that the partymon isn't holding Mail.
	push de
	push bc
	ld a, c

	; This is required for CheckCurPartyMonFainted
	dec a
	ld [wCurPartyMon], a

	; Is the party slot occupied? Also writes the partymon to wBufferMon.
	call GetStorageBoxMon
	jr z, .not_last_healthy

	; Check if the partymon is holding Mail. We can't store Mail in a Box.
	ld a, [wBufferMonItem]
	call ItemIsMail_a
	ld a, 5
	jr c, .pop_bcde_and_return

	; Otherwise, check if it is our last healthy mon.
	newfarcall CheckCurPartyMonFainted
	jr nc, .not_last_healthy

	; Doing this would lose us our last healthy mon, so abort.
	ld a, 4
.pop_bcde_and_return
	pop bc
	pop de
	ret

.not_last_healthy
	pop bc
	pop de

	; If we can't change the box yet, we need to save first.
	push bc
	ld b, d
	call CanWriteStorageBox
	pop bc
	ld a, 1
	ret nz

	; Keep the box mon (if any) for the party slot.
	push bc
	ld b, d
	ld c, e
	ld hl, wBoxTempEntry2
	call ReadStorageBoxEntry
	pop bc
	push af

	; Move the partymon (still in wBufferMon) to the box slot.
	push bc
	ld b, d
	ld c, e
	ld a, [wBufferMonSlot]
	and a
	jr z, .empty_box_slot
	call PutStorageBoxMon
	jr .got_box_slot
.empty_box_slot
	call RemoveStorageBoxMon
.got_box_slot
	pop bc

	; Then move the box mon to the party slot.
	pop af
	jr z, .empty_party_slot
	ld hl, wBoxTempEntry2
	call BoxEntryToBufferMon
	call PutStorageBoxMon
	xor a
	ret

.empty_party_slot
	call RemoveStorageBoxMon
	xor a
	ret

.party_swap
	; Check if we're placing a mon in a blank party slot. This means we're
	; shifting every other party member upwards, placing the held mon last.
	ld a, [wPartyCount]
	cp c
	jr c, .shift
	call SwapPartyMons
	xor a
	ret

.shift
	; Shift the held mon until it's last in the party.
	ld c, e
	call ShiftPartySlotToEnd
	xor a
	ret

.box_swap
	; Swaps box slots bc and de. If we can't change both boxes yet, we need to
	; save first.
	call CanWriteStorageBoxes
	ld a, 1
	ret nz

	; Read both mons, then write each of them to the other slot.
	ld hl, wBoxTempEntry
	call ReadStorageBoxEntry
	push af
	push bc
	ld b, d
	ld c, e
	ld hl, wBoxTempEntry2
	call ReadStorageBoxEntry
	pop bc
	ld hl, wBoxTempEntry2
	call SetStorageBoxEntry
	pop af
	ld b, d
	ld c, e
	ld hl, wBoxTempEntry
	call SetStorageBoxEntry
	xor a
	ret

SwapPartyMonMail:
	push hl
	push de
	push bc
	dec c
	dec e
	ld d, c
	jr DoMailSwap

SwapPartyMons:
; Swap 1-indexed partymon c and e. Preserves bc, de, hl.
; TODO: this is more efficient than SwitchPartyMons, maybe make it use this.
	push hl
	push de
	push bc
	dec c
	dec e
	ld d, c

	; Swap partymon struct
	ld hl, wPartyMon1
	ld c, PARTYMON_STRUCT_LENGTH
	call DoPartySwap

	; Swap nickname
	ld hl, wPartyMonNicknames
	ld c, MON_NAME_LENGTH
	call DoPartySwap

	; Swap OT name
	ld hl, wPartyMonOTs
	ld c, NAME_LENGTH
	call DoPartySwap

	; Swap alt species
	ld hl, wPartySpecies
	ld c, 1
	call DoPartySwap

	; fallthrough
DoMailSwap:
	; Swap Mail
	ld a, BANK(sPartyMon1Mail)
	call OpenSRAM
	ld hl, sPartyMon1Mail
	ld bc, MAIL_STRUCT_LENGTH
	call DoPartySwap
	call CloseSRAM
	jp PopBCDEHL

DoPartySwap:
; Swaps bc bytes between hl+d*bc and hl+e*bc
	; Get pointers to swap
	push de
	push hl
	ld a, d
	call AddNTimes
	ld a, e
	ld d, h
	ld e, l
	pop hl
	call AddNTimes

	; Now hl and de points to which bytes to swap
	push de
	ld de, wSwitchMonBuffer
	push bc
	push hl
	call CopyBytes
	pop de
	pop bc
	pop hl
	push hl
	push bc
	call CopyBytes
	pop bc
	pop de
	ld hl, wSwitchMonBuffer
	call CopyBytes
	pop de
	ret

; The Storage System keeps vanilla's box layout in SRAM (sBox1 - sBox14, plus a
; copy of the current box in sBox), so Pokemon Stadium 2 and other tools can
; read and change the boxes. A slot map per box lets mons sit in any of its
; slots.

; Changing a box copies it to one of the WRAM box buffers. Buffers are only
; written to SRAM when saving, so resetting without saving leaves the saved
; boxes as they were. When every buffer is in use, the game must be saved
; before changing another box.

MACRO in_box_bank
; Calls \1 with WRAM bank BANK(wBoxBuffers), then returns its a and flags,
; with bc, de and hl preserved.
	push hl
	push de
	push bc
	ldh a, [rSVBK]
	push af
	ld a, BANK(wBoxBuffers)
	ldh [rSVBK], a
	call \1
	jp _ReturnFromBoxBank
ENDM

_ReturnFromBoxBank:
; Restores the WRAM bank that in_box_bank pushed, and its registers.
	push af
	ld hl, sp + 3
	ld a, [hl]
	ldh [rSVBK], a
	call CloseSRAM
	pop af
	inc sp
	inc sp
	pop bc
	pop de
	pop hl
	ret

NewStorageBoxSlot:
; Finds an empty box slot for a new mon, starting with the current box, and
; returns it in bc. Preserves wBufferMon. Returns:
; nc|z: Active box has free space
; nc|nz: Active box full, space found elsewhere
; c|z: Storage System filled completely.
; c|nz: Storage System has space, but the game must be saved to use it.
	call GetCurBoxNumber
	call .Find
	push af
	ld a, [wStorageFoundSlot]
	ld b, a
	ld a, [wStorageFoundSlot + 1]
	ld c, a
	pop af
	ret

.Find:
	in_box_bank _NewStorageBoxSlot

GetCurBoxNumber:
; Returns b = [wCurBox] + 1, or 1 if [wCurBox] isn't a box.
	ld a, [wCurBox]
	cp NUM_BOXES
	jr c, .got_box
	xor a
.got_box
	inc a
	ld b, a
	ret

CanWriteStorageBox:
; Returns z if box b can be changed without saving first. b = 0 is the party,
; which always can.
	push de
	ld d, 0
	call CanWriteStorageBoxes
	pop de
	ret

CanWriteStorageBoxes:
; Returns z if boxes b and d (0 for the party, bit 7 of d ignored) can be
; changed without saving first.
	in_box_bank _CanWriteBoxes

CountFreeBoxSlots:
; Returns the number of empty box slots that can be filled without saving
; first, or 255 if there are more.
	in_box_bank _CountFreeBoxSlots

ReadStorageBoxEntry:
; Copies box b slot c to the box entry at hl (in BANK(wBoxBuffers)).
; Returns z if the slot is empty.
	call _SetStorageEntryPointer
	in_box_bank _ReadStorageBoxEntry

SetStorageBoxEntry:
; Copies the box entry at hl (in BANK(wBoxBuffers)) to box b slot c, or
; empties the slot if a is 0. Returns z on success, or nz if the game must be
; saved first.
	and a
	jr z, RemoveStorageBoxMon
	call _SetStorageEntryPointer
	in_box_bank _WriteStorageBoxEntry

_SetStorageEntryPointer:
	ld a, l
	ld [wStorageEntryPointer], a
	ld a, h
	ld [wStorageEntryPointer + 1], a
	ret

PutStorageBoxMon:
; Writes wBufferMon to box b slot c. If b is 0 and slot c is past the end of
; the party, adds it to the end instead. Returns z on success, or nz if the
; game must be saved first.
	ld a, b
	and a
	jr z, .party
	push hl
	ld hl, wBoxTempEntry
	call BufferMonToBoxEntry
	ld a, TRUE
	call SetStorageBoxEntry
	pop hl
	ret

.party
	push hl
	push de
	push bc
	ld a, [wPartyCount]
	cp c
	jr nc, .got_slot
	; Add it to the end of the party.
	inc a
	ld c, a
	ld [wPartyCount], a
	ld b, 0
	ld hl, wPartySpecies
	add hl, bc
	ld [hl], -1
.got_slot
	ld b, 0
	call CopyBetweenPartyAndTemp
	pop bc
	pop de
	pop hl
	xor a
	ret

RemoveStorageBoxMon:
; Empties box b slot c. Emptying a party slot moves the later partymons up.
; Returns z on success, or nz if the game must be saved first.
	ld a, b
	and a
	jr z, .party
	in_box_bank _RemoveStorageBoxEntry

.party
	ld a, [wPartyCount]
	cp c
	jr c, .done
	push hl
	push de
	push bc
	; First, shift this partymon to the end, effectively shifting everything
	; past it upwards.
	call ShiftPartySlotToEnd

	; Then delete the partymon.
	ld hl, wPartyCount
	dec [hl]
	ld c, [hl]
	ld b, 0
	ld hl, wPartySpecies
	add hl, bc
	ld [hl], -1
	pop bc
	pop de
	pop hl
.done
	xor a
	ret

UpdateStorageBoxMonFromTemp:
; Updates storage pointed to by wBufferMonBox+wBufferMonSlot with content in
; wBufferMon. Returns z if successful.
	ld a, [wBufferMonSlot]
	ld c, a
	ld a, [wBufferMonBox]
	ld b, a
	jr PutStorageBoxMon

BufferMonToBoxEntry:
; Copies wBufferMon to the box entry at hl (in BANK(wBoxBuffers)).
	push hl
	push de
	push bc
	ld d, h
	ld e, l
	ld hl, wBufferMonAltSpecies
	ld c, 1
	call CopyToBoxBank
	ld hl, wBufferMon
	ld c, BOXMON_STRUCT_LENGTH
	call CopyToBoxBank
	ld hl, wBufferMonOT
	ld c, NAME_LENGTH
	call CopyToBoxBank
	ld hl, wBufferMonNickname
	ld c, MON_NAME_LENGTH
	call CopyToBoxBank
	jp PopBCDEHL

BoxEntryToBufferMon:
; Copies the box entry at hl (in BANK(wBoxBuffers)) to wBufferMon, healing it
; and calculating its stats. Returns nz|nc.
	push hl
	push de
	push bc
	ld de, wBufferMonAltSpecies
	ld c, 1
	call CopyFromBoxBank
	ld de, wBufferMon
	ld c, BOXMON_STRUCT_LENGTH
	call CopyFromBoxBank
	ld de, wBufferMonOT
	ld c, NAME_LENGTH
	call CopyFromBoxBank
	ld de, wBufferMonNickname
	ld c, MON_NAME_LENGTH
	call CopyFromBoxBank
	call SetTempPartyMonData
	jp PopBCDEHL

CopyToBoxBank:
; Copies c bytes from hl in BANK(wBufferMon) to de in BANK(wBoxBuffers).
	ld b, [hl]
	inc hl
	ld a, BANK(wBoxBuffers)
	ldh [rSVBK], a
	ld a, b
	ld [de], a
	inc de
	ld a, BANK(wBufferMon)
	ldh [rSVBK], a
	dec c
	jr nz, CopyToBoxBank
	ret

CopyFromBoxBank:
; Copies c bytes from hl in BANK(wBoxBuffers) to de in BANK(wBufferMon).
	ld a, BANK(wBoxBuffers)
	ldh [rSVBK], a
	ld b, [hl]
	inc hl
	ld a, BANK(wBufferMon)
	ldh [rSVBK], a
	ld a, b
	ld [de], a
	inc de
	dec c
	jr nz, CopyFromBoxBank
	ret

StageStorageBoxes:
; Before saving, copies the box buffers to their staging areas in SRAM, so
; CommitStorageBoxes can still write them to the saved boxes if the save is
; interrupted after the main save data is written (see WriteBackupSave).
	in_box_bank _StageStorageBoxes

CommitStorageBoxes:
; Writes the staged box buffers to the saved boxes, and copies the current box
; to sBox.
	call GetCurBoxNumber
	in_box_bank _CommitStorageBoxes

LoadStorageBoxes:
; After loading a save, discards anything staged by an unfinished save, and
; fixes the slot maps of boxes Pokemon Stadium 2 changed.
	call GetCurBoxNumber
	ld a, b
	dec a
	ld [wCurBox], a
	in_box_bank _LoadStorageBoxes

InitializeSavedBoxes:
; Empties every saved box, for a save whose boxes can't be converted.
	ld b, 1
.loop
	call _EraseSavedBox
	inc b
	ld a, b
	cp NUM_BOXES + 1
	jr nz, .loop
	ld a, BANK(sBox)
	call OpenSRAM
	ld hl, sBox
	call _EraseBox
	ld a, BANK(sStagedBoxes)
	call OpenSRAM
	xor a
	ld [sStagedBoxes], a
	ld [sWritingBackup], a
	jp CloseSRAM

; The functions below run with WRAM bank BANK(wBoxBuffers) (see in_box_bank).

_NewStorageBoxSlot:
; See NewStorageBoxSlot. b = the box to start with. Returns the slot in
; wStorageFoundSlot.
	ld d, NUM_BOXES
	; e = whether we found space in a box that can't be changed yet
	ld e, FALSE
.box_loop
	push de
	call _OpenBox
	ld c, 1
	jr z, .found_slot
.slot_loop
	call _GetSlotIndex
	and a
	jr z, .found_slot
	inc c
	ld a, c
	cp MONS_PER_BOX + 1
	jr nz, .slot_loop
	pop de
	jr .next_box

.found_slot
	pop de
	call _CanWriteBox
	jr z, .done
	ld e, TRUE
.next_box
	ld a, b
	inc b
	cp NUM_BOXES
	jr nz, .no_wrap
	ld b, 1
.no_wrap
	dec d
	jr nz, .box_loop

	; c|z if the Storage System is full, c|nz if saving would free space.
	ld a, e
	and a
	scf
	ret

.done
	ld a, b
	ld [wStorageFoundSlot], a
	ld a, c
	ld [wStorageFoundSlot + 1], a
	; Return z if this is the box we started with. Always nc.
	ld a, d
	xor NUM_BOXES
	ret

_CanWriteBoxes:
; See CanWriteStorageBoxes.
	; e = boxes that need a buffer
	ld e, 0
	call .Check
	ld a, d
	and $7f
	cp b
	jr z, .counted
	ld b, a
	call .Check
.counted
	; Each unused buffer covers one of them.
	ld hl, wBoxBufferBoxes
	ld c, NUM_BOX_BUFFERS
.loop
	ld a, [hli]
	and a
	jr nz, .next
	ld a, e
	and a
	jr z, .next
	dec e
.next
	dec c
	jr nz, .loop
	ld a, e
	and a
	ret

.Check:
	ld a, b
	and a
	ret z
	call _FindBoxBuffer
	ret nz
	inc e
	ret

_CanWriteBox:
; Returns z if box b is buffered or can be. Preserves bc, de and hl.
	push hl
	push bc
	call _FindBoxBuffer
	jr nz, .yes
	; Is there an unused buffer?
	ld b, 0
	call _FindBoxBuffer
	jr nz, .yes
	pop bc
	pop hl
	or 1
	ret

.yes
	pop bc
	pop hl
	xor a
	ret

_CountFreeBoxSlots:
; See CountFreeBoxSlots.
	ld b, 1
	ld e, 0
.loop
	call _CanWriteBox
	jr nz, .next
	push de
	call _OpenBox
	ld a, MONS_PER_BOX
	jr z, .got_free_slots
	sub [hl]
.got_free_slots
	pop de
	add e
	jr nc, .no_overflow
	ld a, 255
.no_overflow
	ld e, a
.next
	inc b
	ld a, b
	cp NUM_BOXES + 1
	jr nz, .loop
	ld a, e
	ret

_ReadStorageBoxEntry:
; See ReadStorageBoxEntry.
	call _OpenBox
	ret z
	call _GetSlotIndex
	and a
	ret z
	dec a
	ld [wStorageSlotIndex], a
	call _CopyEntryToTemp
	ld a, TRUE
	and a
	ret

_WriteStorageBoxEntry:
; Copies the box entry at [wStorageEntryPointer] to box b slot c.
; Returns z on success, or nz if every buffer is in use.
	call _AllocateBoxBuffer
	ret nz
	call _OpenBox
	call _GetSlotIndex
	and a
	jr z, .new_entry
	dec a
	ld [wStorageSlotIndex], a
	call _CopyTempToEntry
	xor a
	ret

.new_entry
	; It goes after the mons in earlier slots, so later ones move up.
	call _CountSlotsBefore
	call _InsertEntry
	ld a, 1
	call _AdjustSlotMap
	ld a, [wStorageSlotIndex]
	inc a
	call _SetSlotIndex
	xor a
	ret

_RemoveStorageBoxEntry:
; Empties box b slot c. Returns z on success, or nz if every buffer is in use.
	call _AllocateBoxBuffer
	ret nz
	call _OpenBox
	call _GetSlotIndex
	and a
	ret z
	ld [wStorageSlotIndex], a
	xor a
	call _SetSlotIndex
	; The mons after it move down.
	ld a, -1
	call _AdjustSlotMap
	ld a, [wStorageSlotIndex]
	dec a
	call _RemoveEntry
	xor a
	ret

_FindBoxBuffer:
; Returns hl = the buffer holding box b and nz, or z if box b isn't buffered.
; With b = 0, finds an unused buffer instead. Preserves bc and de.
	push de
	push bc
	ld hl, wBoxBufferBoxes
	ld e, 0
.loop
	ld a, [hli]
	cp b
	jr z, .found
	inc e
	ld a, e
	cp NUM_BOX_BUFFERS
	jr nz, .loop
	pop bc
	pop de
	xor a
	ret

.found
	ld a, e
	call _GetBoxBuffer
	pop bc
	pop de
	ld a, TRUE
	and a
	ret

_GetBoxBuffer:
; Returns hl = box buffer a (0-indexed).
	ld hl, wBoxBuffer1
	ld bc, wBoxBuffer2 - wBoxBuffer1
	jp AddNTimes

_AllocateBoxBuffer:
; Buffers box b so it can be changed, unless it already is.
; Returns z, or nz if every buffer is in use. Preserves bc and de.
	call _FindBoxBuffer
	jr nz, .done
	push de
	push bc
	ld hl, wBoxBufferBoxes
	ld e, 0
.loop
	ld a, [hl]
	and a
	jr z, .found_unused
	inc hl
	inc e
	ld a, e
	cp NUM_BOX_BUFFERS
	jr nz, .loop
	pop bc
	pop de
	or 1
	ret

.found_unused
	ld [hl], b
	ld a, e
	call _GetBoxBuffer
	pop bc
	push bc
	ld a, [wStorageNewGame]
	and a
	jr nz, .new_game
	call _CopySavedBoxToBuffer
	jr .allocated

.new_game
	; The saved boxes belong to the previous game, so start with an empty one.
	inc hl
	ld bc, MONS_PER_BOX
	xor a
	call ByteFill
	call _EraseBox
.allocated
	pop bc
	pop de
.done
	xor a
	ret

_OpenBox:
; Returns hl = box b and de = its slot map, either buffered or in an open SRAM
; bank, and nz. Returns z if the box is empty because a new game hasn't been
; saved yet. Preserves bc.
	call _FindBoxBuffer
	jr z, .saved_box
	inc hl
	ld d, h
	ld e, l
	push bc
	ld bc, wBoxBuffer1Box - wBoxBuffer1SlotMap
	add hl, bc
	pop bc
	ld a, TRUE
	and a
	ret

.saved_box
	ld a, [wStorageNewGame]
	and a
	jr nz, .empty
	call _OpenSavedBox
	ld a, TRUE
	and a
	ret

.empty
	xor a
	ret

_OpenSavedBox:
; Opens saved box b's SRAM bank. Returns hl = the box and de = its slot map.
; Preserves bc.
	push bc
	ld a, b
	dec a
	ld c, BANK(sBox1)
	cp BOXES_PER_SRAM_BANK
	jr c, .got_bank
	sub BOXES_PER_SRAM_BANK
	ld c, BANK(sBox8)
.got_bank
	ld b, a
	ld a, c
	call OpenSRAM
	ld a, b
	push af
	ld hl, sBoxSlotMaps1
	ld bc, MONS_PER_BOX
	call AddNTimes
	ld d, h
	ld e, l
	pop af
	ld hl, sBox1
	ld bc, sBox2 - sBox1
	call AddNTimes
	pop bc
	ret

	assert sBox8 == sBox1 && sBoxSlotMaps8 == sBoxSlotMaps1
	assert BANK(sBoxSlotMaps1) == BANK(sBox1) && BANK(sBoxSlotMaps8) == BANK(sBox8)

_CopySavedBoxToBuffer:
; Copies saved box b and its slot map to the buffer at hl. Preserves bc.
	push bc
	push hl
	call _OpenSavedBox
	pop bc
	push hl
	; slot map
	ld h, d
	ld l, e
	ld d, b
	ld e, c
	inc de
	ld bc, MONS_PER_BOX
	call CopyBytes
	; box
	pop hl
	ld bc, BOX_LENGTH
	call CopyBytes
	pop bc
	ret

	assert wBoxBuffer1Box == wBoxBuffer1SlotMap + MONS_PER_BOX

_CopyBufferToSavedBox:
; Copies the buffer at hl to its saved box and slot map.
	ld b, [hl]
	inc hl
	push hl
	call _OpenSavedBox
	pop hl
	push bc
	ld bc, MONS_PER_BOX
	call CopyBytes
	pop bc
	push hl
	call _OpenSavedBox
	ld d, h
	ld e, l
	pop hl
	ld bc, BOX_LENGTH
	jp CopyBytes

_EraseSavedBox:
; Empties saved box b. Preserves bc.
	push bc
	call _OpenSavedBox
	push hl
	ld h, d
	ld l, e
	ld bc, MONS_PER_BOX
	xor a
	call ByteFill
	pop hl
	call _EraseBox
	pop bc
	ret

_EraseBox:
; Empties the box at hl.
	push hl
	ld bc, BOX_LENGTH
	xor a
	call ByteFill
	pop hl
	inc hl
	ld [hl], -1
	ret

	assert BOX_SPECIES == 1

_NormalizeSavedBox:
; Makes saved box b's species list and slot map match its count, e.g. after
; Pokemon Stadium 2 changed the box. Preserves bc.
	push bc
	call _OpenSavedBox
	ld a, [hl]
	cp MONS_PER_BOX + 1
	jr c, .count_ok
	xor a
	ld [hl], a
.count_ok
	ld c, a
	call _TerminateSpeciesList

	; The slot map must hold list positions 1 to the count, in order.
	push de
	ld h, d
	ld l, e
	ld b, 1
	ld e, MONS_PER_BOX
.check_loop
	ld a, [hli]
	and a
	jr z, .check_next
	cp b
	jr nz, .reset
	inc b
.check_next
	dec e
	jr nz, .check_loop
	ld a, b
	dec a
	cp c
	jr z, .done

.reset
	; Otherwise, put the mons in the first slots.
	pop hl
	push hl
	ld b, 1
	ld e, MONS_PER_BOX
.reset_loop
	ld a, b
	dec a
	cp c
	ld a, b
	jr c, .got_position
	xor a
.got_position
	ld [hli], a
	inc b
	dec e
	jr nz, .reset_loop

.done
	pop de
	pop bc
	ret

_GetSlotIndex:
; Returns a = the list position + 1 of slot c in the slot map at de, or 0 if
; the slot is empty. Preserves bc, de and hl.
	push hl
	call _PointSlot
	ld a, [hl]
	pop hl
	ret

_SetSlotIndex:
; Sets the list position + 1 of slot c in the slot map at de to a.
; Preserves bc, de and hl.
	push hl
	push af
	call _PointSlot
	pop af
	ld [hl], a
	pop hl
	ret

_PointSlot:
; Returns hl = slot c in the slot map at de.
	ld h, 0
	ld l, c
	dec l
	add hl, de
	ret

_CountSlotsBefore:
; Returns a = the number of filled slots before slot c in the slot map at de.
; Preserves bc, de and hl.
	push hl
	push bc
	ld h, d
	ld l, e
	ld b, 0
.loop
	dec c
	jr z, .done
	ld a, [hli]
	and a
	jr z, .loop
	inc b
	jr .loop

.done
	ld a, b
	pop bc
	pop hl
	ret

_AdjustSlotMap:
; Adds a to each list position + 1 in the slot map at de that's greater than
; [wStorageSlotIndex]. Preserves bc, de and hl.
	push hl
	push bc
	ld b, a
	ld h, d
	ld l, e
	ld c, MONS_PER_BOX
.loop
	ld a, [wStorageSlotIndex]
	cp [hl]
	jr nc, .next
	ld a, [hl]
	add b
	ld [hl], a
.next
	inc hl
	dec c
	jr nz, .loop
	pop bc
	pop hl
	ret

_InsertEntry:
; Inserts the box entry at [wStorageEntryPointer] at list position a of the
; box at hl, and sets [wStorageSlotIndex] to a. Preserves bc, de and hl.
	push de
	push bc
	ld b, a
	; Add it to the end of the lists, then move it up.
	ld a, [hl]
	ld [wStorageSlotIndex], a
	inc a
	ld [hl], a
	call _CopyTempToEntry
	ld a, [hl]
	call _TerminateSpeciesList
.loop
	ld a, [wStorageSlotIndex]
	cp b
	jr z, .done
	dec a
	ld [wStorageSlotIndex], a
	call _SwapAdjacentEntries
	jr .loop

.done
	pop bc
	pop de
	ret

_RemoveEntry:
; Removes list position a of the box at hl. Preserves bc, de and hl.
	push bc
	ld [wStorageSlotIndex], a
	ld a, [hl]
	dec a
	ld [hl], a
	ld b, a
	; Move it to the end of the lists, then drop it.
.loop
	ld a, [wStorageSlotIndex]
	cp b
	jr z, .done
	call _SwapAdjacentEntries
	ld a, [wStorageSlotIndex]
	inc a
	ld [wStorageSlotIndex], a
	jr .loop

.done
	ld a, b
	call _TerminateSpeciesList
	pop bc
	ret

_TerminateSpeciesList:
; Ends the species list of the box at hl after a mons.
; Preserves bc, de and hl.
	push hl
	push bc
	ld c, a
	ld b, 0
	add hl, bc
	ld bc, BOX_SPECIES
	add hl, bc
	ld [hl], -1
	pop bc
	pop hl
	ret

_SwapAdjacentEntries:
; Swaps list positions [wStorageSlotIndex] and [wStorageSlotIndex] + 1 of the
; box at hl. Preserves bc, de and hl.
	push hl
	push de
	push bc
	ld bc, BoxEntryFields
.loop
	ld a, [bc]
	inc a
	jr z, .done
	push hl
	call _GetEntryField
	push bc
	ld c, a
	ld b, 0
	; de = the same part of the next entry
	ld a, l
	add c
	ld e, a
	ld a, h
	adc b
	ld d, a
	call SwapBytes
	pop bc
	pop hl
	jr .loop

.done
	pop bc
	pop de
	pop hl
	ret

_CopyEntryToTemp:
; Copies list position [wStorageSlotIndex] of the box at hl to the box entry
; at [wStorageEntryPointer]. Preserves bc, de and hl.
	xor a
	jr _CopyBoxEntry

_CopyTempToEntry:
; Copies the box entry at [wStorageEntryPointer] to list position
; [wStorageSlotIndex] of the box at hl. Preserves bc, de and hl.
	ld a, TRUE
_CopyBoxEntry:
	ld [wStorageCopyMode], a
	push hl
	push de
	push bc
	ld a, [wStorageEntryPointer]
	ld e, a
	ld a, [wStorageEntryPointer + 1]
	ld d, a
	ld bc, BoxEntryFields
.loop
	ld a, [bc]
	inc a
	jr z, .done
	push hl
	call _GetEntryField
	push bc
	ld c, a
	ld b, 0
	ld a, [wStorageCopyMode]
	and a
	call nz, SwapHLDE
	call CopyBytes
	ld a, [wStorageCopyMode]
	and a
	call nz, SwapHLDE
	pop bc
	pop hl
	jr .loop

.done
	jp PopBCDEHL

_GetEntryField:
; Returns hl = the part at bc (in BoxEntryFields) of list position
; [wStorageSlotIndex] of the box at hl, and a = its size. Advances bc to the
; next part. Preserves de.
	ld a, [bc]
	inc bc
	add l
	ld l, a
	ld a, [bc]
	inc bc
	adc h
	ld h, a
	ld a, [bc]
	inc bc
	push bc
	push af
	ld c, a
	ld b, 0
	ld a, [wStorageSlotIndex]
	call AddNTimes
	pop af
	pop bc
	ret

BoxEntryFields:
; offset in a box and size of each part of a box entry, in box_entry order
	dw BOX_SPECIES
	db 1
	dw BOX_MONS
	db BOXMON_STRUCT_LENGTH
	dw BOX_OTS
	db NAME_LENGTH
	dw BOX_NICKNAMES
	db MON_NAME_LENGTH
	db -1 ; end

	; The end marker is checked against the first byte of an offset.
	assert LOW(BOX_SPECIES) != $ff && LOW(BOX_MONS) != $ff
	assert LOW(BOX_OTS) != $ff && LOW(BOX_NICKNAMES) != $ff
	assert BOXENTRY_LENGTH == 1 + BOXMON_STRUCT_LENGTH + NAME_LENGTH + MON_NAME_LENGTH

_StageStorageBoxes:
; See StageStorageBoxes.
	; e = staged buffers
	ld e, 0
for n, NUM_BOX_BUFFERS
	ld a, [wBoxBufferBoxes + n]
	and a
	jr z, .not_buffered{d:n}
	push af
	ld a, n
	call _GetBoxBuffer
	pop af
	ld [hl], a
	push de
	ld a, n
	call _StageBoxBuffer
	pop de
	set n, e
.not_buffered{d:n}
endr
	ld a, [wStorageNewGame]
	and a
	jr z, .got_staged
	set STAGED_BOXES_NEW_GAME_F, e
.got_staged
	ld a, BANK(sStagedBoxes)
	call OpenSRAM
	ld a, e
	ld [sStagedBoxes], a
	ret

_CommitStorageBoxes:
; See CommitStorageBoxes. b = the current box.
	push bc
	ld a, BANK(sStagedBoxes)
	call OpenSRAM
	ld a, [sStagedBoxes]
	ld [wStorageStagedBoxes], a

	; Load the staged boxes into the buffers, and write them to the saved boxes.
for n, NUM_BOX_BUFFERS
	xor a
	ld [wBoxBufferBoxes + n], a
	ld a, [wStorageStagedBoxes]
	bit n, a
	jr z, .not_staged{d:n}
	ld a, n
	call _UnstageBoxBuffer
	ld a, n
	call _GetBoxBuffer
	; Skip it if its box number is invalid.
	ld a, [hl]
	dec a
	cp NUM_BOXES
	jr nc, .not_staged{d:n}
	inc a
	ld [wBoxBufferBoxes + n], a
	call _CopyBufferToSavedBox
.not_staged{d:n}
endr

	; After starting a new game, the other saved boxes belong to the old game.
	ld a, [wStorageStagedBoxes]
	bit STAGED_BOXES_NEW_GAME_F, a
	jr z, .erased
	ld b, 1
.erase_loop
	call _FindBoxBuffer
	call z, _EraseSavedBox
	inc b
	ld a, b
	cp NUM_BOXES + 1
	jr nz, .erase_loop
.erased

	; The buffers are free now.
	ld hl, wBoxBufferBoxes
	ld bc, NUM_BOX_BUFFERS
	xor a
	call ByteFill
	ld [wStorageNewGame], a
	ld a, BANK(sStagedBoxes)
	call OpenSRAM
	xor a
	ld [sStagedBoxes], a

	pop bc
	; fallthrough
_CopySavedBoxToActiveBox:
; Copies saved box b to sBox, as vanilla does when saving and loading.
	xor a
	push bc
	call _GetBoxBuffer
	pop bc
	push hl
	call _CopySavedBoxToBuffer
	pop hl
	ld bc, wBoxBuffer1Box - wBoxBuffer1
	add hl, bc
	ld a, BANK(sBox)
	call OpenSRAM
	ld de, sBox
	ld bc, BOX_LENGTH
	jp CopyBytes

_LoadStorageBoxes:
; See LoadStorageBoxes. b = the current box.
	; Clear the buffers and anything staged by an unfinished save.
	push bc
	ld hl, wBoxBufferBoxes
	ld bc, NUM_BOX_BUFFERS
	xor a
	call ByteFill
	ld [wStorageNewGame], a
	ld a, BANK(sStagedBoxes)
	call OpenSRAM
	xor a
	ld [sStagedBoxes], a
	pop bc

	; Pokemon Stadium 2 changes the saved boxes like vanilla does, so their
	; slot maps may no longer match.
	push bc
	ld b, 1
.loop
	call _NormalizeSavedBox
	inc b
	ld a, b
	cp NUM_BOXES + 1
	jr nz, .loop
	pop bc
	jr _CopySavedBoxToActiveBox

_StageBoxBuffer:
; Copies box buffer a to its staging area in SRAM.
	ld e, FALSE
	jr _CopyBoxStaging

_UnstageBoxBuffer:
; Copies box buffer a's staging area in SRAM back to it.
	ld e, TRUE
_CopyBoxStaging:
	push af
	ld a, e
	ld [wStorageCopyMode], a
	pop af
	push af
	call _GetBoxBuffer
	pop af
	push hl
	ld hl, BoxStagingAreas
	ld c, a
	ld b, 0
	add hl, bc
	add hl, bc
	ld a, [hli]
	ld [wStorageStagingPart], a
	ld a, [hl]
	ld [wStorageStagingPart + 1], a
	pop hl
.part_loop
	; Each part is a bank, an address and a size.
	ld a, [wStorageStagingPart]
	ld c, a
	ld a, [wStorageStagingPart + 1]
	ld b, a
	ld a, [bc]
	cp -1
	ret z
	inc bc
	call OpenSRAM
	ld a, [bc]
	inc bc
	ld e, a
	ld a, [bc]
	inc bc
	ld d, a
	ld a, [bc]
	inc bc
	push af
	ld a, [bc]
	inc bc
	push af
	ld a, c
	ld [wStorageStagingPart], a
	ld a, b
	ld [wStorageStagingPart + 1], a
	pop af
	ld b, a
	pop af
	ld c, a
	ld a, [wStorageCopyMode]
	and a
	call nz, SwapHLDE
	call CopyBytes
	ld a, [wStorageCopyMode]
	and a
	call nz, SwapHLDE
	jr .part_loop

MACRO box_staging_part
	dba \1
	dw \1End - \1
ENDM

BoxStagingAreas:
; SRAM parts of each box buffer's staging area
	table_width 2
	dw .Buffer1
	dw .Buffer2
	dw .Buffer3
	assert_table_length NUM_BOX_BUFFERS

.Buffer1:
	box_staging_part sBoxStaging1Part1
	box_staging_part sBoxStaging1Part2
	box_staging_part sBoxStaging1Part3
	box_staging_part sBoxStaging1Part4
	db -1 ; end

.Buffer2:
	box_staging_part sBoxStaging2
	db -1 ; end

.Buffer3:
	box_staging_part sBoxStaging3Part1
	box_staging_part sBoxStaging3Part2
	box_staging_part sBoxStaging3Part3
	box_staging_part sBoxStaging3Part4
	db -1 ; end

	assert sBoxStaging1Part1End - sBoxStaging1Part1 + sBoxStaging1Part2End - sBoxStaging1Part2 \
		+ sBoxStaging1Part3End - sBoxStaging1Part3 + sBoxStaging1Part4End - sBoxStaging1Part4 \
		== BOXBUF_LENGTH
	assert sBoxStaging2End - sBoxStaging2 == BOXBUF_LENGTH
	assert sBoxStaging3Part1End - sBoxStaging3Part1 + sBoxStaging3Part2End - sBoxStaging3Part2 \
		+ sBoxStaging3Part3End - sBoxStaging3Part3 + sBoxStaging3Part4End - sBoxStaging3Part4 \
		== BOXBUF_LENGTH

InitializeBoxes:
; Starts the Storage System for a new game. The saved boxes belong to the
; previous game until this one is saved, so they count as empty until then.
	ld a, TRUE
	ld [wStorageNewGame], a
	ld hl, wBoxBufferBoxes
	ld bc, NUM_BOX_BUFFERS
	xor a
	call ByteFill
	ld hl, wBoxNames
	call SetDefaultBoxNames
	ld hl, wBoxThemes
	; fallthrough
SetDefaultBoxThemes:
; Writes the default theme of each box to hl.
	ld d, h
	ld e, l
	ld hl, BillsPC_DefaultBoxThemes
	ld bc, NUM_BOXES
	jp CopyBytes

SetDefaultBoxNames:
; Writes the names "BOX 1" to "BOX14" to hl.
	ld b, 1
.loop
	push hl
	push bc
	push hl
	ld bc, BOX_NAME_LENGTH
	xor a
	call ByteFill
	pop hl
	ld de, .Box
	call CopyName2
	dec hl
	pop bc
	ld a, b
	cp 10
	jr c, .one_digit
	ld [hl], '1'
	inc hl
	sub 10
.one_digit
	add '0'
	ld [hli], a
	ld [hl], '@'
	pop hl
	ld de, BOX_NAME_LENGTH
	add hl, de
	inc b
	ld a, b
	cp NUM_BOXES + 1
	jr nz, .loop
	ret

.Box:
	db "BOX @"

INCLUDE "data/pc/default_box_themes.asm"

_PointBoxTheme:
; Returns [wCurBox]'s theme pointer in hl.
	ld a, [wCurBox]
	ld hl, wBoxThemes
	add l
	ld l, a
	ret nc
	inc h
	ret

GetBoxTheme:
; Returns [wCurBox]'s theme in a.
	call _PointBoxTheme
	ld a, [hl]
	ret

SetBoxTheme:
; Sets [wCurBox]'s theme to a.
	push af
	call _PointBoxTheme
	pop af
	ld [hl], a
	ret

GetCurBoxName:
; Writes name of current box to string buffer 1.
	ld a, [wCurBox]
	inc a
	ld b, a
	; fallthrough
GetBoxName:
; Writes name of box b to string buffer 1.
	ld c, 0
	call CopyBoxName

	; Ensure that there's a terminator at the end. This isn't included as part
	; of saved box name.
	ld a, '@'
	ld [wStringBuffer1 + BOX_NAME_LENGTH], a
	ret

SetBoxName:
; Writes name from string buffer 1 to box b.
	ld c, 1
	; fallthrough
CopyBoxName:
; Copies between box b and string buffer 1 depending on value of c.
; c=0: Copy from box b to string buffer 1.
; c=1: Copy from string buffer 1 to box b.
	ld hl, wBoxNames
	ld a, b
	dec a
	push bc
	ld bc, BOX_NAME_LENGTH
	call AddNTimes
	pop bc
	ld de, wStringBuffer1
	dec c
	call z, SwapHLDE
	ld bc, BOX_NAME_LENGTH
	jp CopyBytes

ShiftPartySlotToEnd:
; Shift party slot c until the end.
	ld a, [wPartyCount]
	cp c
	ret z
	ld e, c
	inc c
	call SwapPartyMons
	jr ShiftPartySlotToEnd

CopyBetweenPartyAndTemp:
; Copies between partymon c (1-indexed) and temp. Doesn't preserve registers.
; Note that this will not update the party count if adding a new mon.
; If bit 7 of b is set, copies between wOTPartyMons instead of wPartyMons.
; If bit 0 of b is set, copies from party to temp, otherwise the reverse.
	dec c
	ld hl, wPartyMon1
	ld de, wBufferMon
	ld a, PARTYMON_STRUCT_LENGTH
	call .Copy

	ld hl, wPartyMonNicknames
	ld de, wBufferMonNickname
	ld a, MON_NAME_LENGTH
	call .Copy

	ld hl, wPartyMonOTs
	ld de, wBufferMonOT
	ld a, NAME_LENGTH
	call .Copy

	ld hl, wPartySpecies
	ld de, wBufferMonAltSpecies
	ld a, 1
	; fallthrough
.Copy:
; Copies c bytes from hl+c*a to de if b is 1, otherwise the reverse.
	push bc
	bit 7, b
	jr z, .got_party

	; Copies from OT party instead.
	push bc
	ld bc, wOTPartyMons - wPartyMons
	add hl, bc
	pop bc
.got_party
	ld b, 0
	push af
	call AddNTimes
	pop af
	pop bc
	push bc
	ld c, a
	bit 0, b
	call z, SwapHLDE
	ld b, 0
	call CopyBytes
	pop bc
	ret

SetTempPartyMonData:
	; Calculate stats
	ld a, [wBufferMonSpecies]
	ld [wCurSpecies], a
	ld hl, wBufferMonDVs
	predef GetUnownLetter
	ld a, [wUnownLetter]
	ld [wCurForm], a
	call GetBaseData
	ld b, TRUE
	ld hl, wBufferMonStatExp - 1
	ld de, wBufferMonMaxHP
	ld a, [wBufferMonLevel]
	ld [wCurPartyLevel], a
	predef CalcMonStats

	; Reset status condition
	xor a
	ld [wBufferMonStatus], a

	; Set HP to full
	ld hl, wBufferMonMaxHP
	ld de, wBufferMonHP
	ld a, [hli]
	ld [de], a
	inc de
	ld a, [hl]
	ld [de], a

	; Eggs have 0 current HP
	ld a, [wBufferMonAltSpecies]
	cp EGG
	jr nz, .not_egg
	xor a
	ld [de], a
	dec de
	ld [de], a

.not_egg
	ld hl, wBufferMonMoves
	ld de, wBufferMonPP
	newfarcall RestoreBufferPP
	or 1
	ret

PrevStorageBoxMon:
; Reads wBufferMonBox+wBufferMonSlot and attempts to load a previous mon.
; Returns nz upon success, otherwise z. If there is no previous mon,
; wBufferMonBox+wBufferMonSlot is unchanged.
	push bc
	ld a, [wBufferMonSlot]
	ld b, a
	ld c, a
.loop
	dec c
	jr z, .restore_slot
	push bc
	ld a, [wBufferMonBox]
	ld b, a
	call GetStorageBoxMon
	pop bc
	jr nz, .done
	jr .loop
.restore_slot
	ld a, b
	ld [wBufferMonSlot], a
.done
	pop bc
	ret

NextStorageBoxMon:
; Reads wBufferMonBox+wBufferMonSlot and attempts to load the next mon.
; Returns nz upon success, otherwise z. If there is no next mon,
; wBufferMonBox+wBufferMonSlot is unchanged.
	push bc
	ld a, [wBufferMonSlot]
	ld b, a
	ld c, a
.loop
	ld a, c
	inc c
	cp MONS_PER_BOX
	jr z, .restore_slot
.get_storage
	push bc
	ld a, [wBufferMonBox]
	ld b, a
	call GetStorageBoxMon
	pop bc
	jr nz, .done
	; If we're dealing with a party, we ran past the amount of mons we have.
	ld a, [wBufferMonBox]
	and $7f
	jr nz, .loop
	; fallthrough
.restore_slot
	ld a, b
	ld [wBufferMonSlot], a
.done
	pop bc
	ret

GetStorageBoxMon:
; Reads box b slot c and puts it in wBufferMon.
; This function supports handling the OT party by setting b to $80.
; Returns z if the requested mon doesn't exist, nz|nc otherwise.
; If b==0, read from party list. c is 1-indexed.
	xor a
	ld [wBufferMonSlot], a
	; Check if we're reading party or box data.
	ld a, b
	ld [wBufferMonBox], a
	and $7f
	jr z, .read_party
	push hl
	ld hl, wBoxTempEntry
	call ReadStorageBoxEntry
	jr z, .done
	ld hl, wBoxTempEntry
	call BoxEntryToBufferMon
	ld a, c
	ld [wBufferMonSlot], a
.done
	pop hl
	ret

.read_party
	and a
	ld a, [wPartyCount]
	jr z, .got_partycount
	ld a, [wOTPartyCount]
.got_partycount
	cp c
	jr nc, .party_not_empty
	xor a
	ret
.party_not_empty
	ld a, c
	ld [wBufferMonSlot], a
	push hl
	push de
	push bc
	inc b
	call CopyBetweenPartyAndTemp

	; Calculate stats
	ld a, [wBufferMonSpecies]
	ld [wCurSpecies], a
	ld hl, wBufferMonDVs
	predef GetUnownLetter
	ld a, [wUnownLetter]
	ld [wCurForm], a
	call GetBaseData
	or 1
	jp PopBCDEHL

Special_CurBoxFullCheck:
; Returns [wScriptVar] = zero if wBufferMonBox == wCurBox
; Returns [wScriptVar] = nonzero if wBufferMonBox != wCurBox
	call CurBoxFullCheck
	ld [wScriptVar], a
	ret

CurBoxFullCheck:
; Requires wBufferMonBox to have sent mon box (returned in b)
; Returns z if wBufferMonBox == wCurBox (or wBufferMonBox = 0)
; Returns nz if wBufferMonBox != wCurBox
;   Also returns name of old wCurBox in wStringBuffer1
;   and sets wCurBox to wBufferMonBox in this case
	ld a, [wBufferMonBox]
	and a
	ret z
	dec a
	ld b, a
	ld a, [wCurBox]
	cp b
	ret z
	push bc
	call GetCurBoxName
	pop bc
	ld a, b
	ld [wCurBox], a
	or 1
	ret
