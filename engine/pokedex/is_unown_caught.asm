; Check whether an Unown letter has been caught (is in wUnownDex).
; IN
;   b  = queried index with "A" starting at 00
; OUT
;   a  = (replaced)
;   c  = (replaced)
;   hl = (replaced)
;   f  = CARRY, if unown is found
	; reset carry
	and a
	ld c, NUM_UNOWN
	ld hl, wUnownDex
.loop
	ld a, [hli]
	and a
	ret z
	; UnownDex has "A" starting at 01
	dec a
	cp b
	jr z, .found
	dec c
	jr nz, .loop
; not found
	and a
	ret
.found
	scf
	ret