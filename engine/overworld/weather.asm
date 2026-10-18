DEF WEATHER_TILE_1  EQU $6d
DEF WEATHER_TILE_2  EQU $6e
DEF RAINDROP_TILE   EQU WEATHER_TILE_1
DEF RAINSPLASH_TILE EQU WEATHER_TILE_2
DEF SNOWFLAKE_TILE  EQU WEATHER_TILE_1
DEF SANDSTORM_TILE  EQU WEATHER_TILE_1
DEF PAL_OW_WEATHER  EQU 6

DoOverworldWeather::
; Run one frame of overworld weather (wCurWeather): spawn and move its
; sprites, or tint the palettes for sunlight. Weather sprites use the OAM
; slots before hUsedWeatherSpriteIndex, below the map objects' slots.
	push hl
	push de
	push bc

	; if weather is disabled, we are done
	ld hl, wWeatherFlags
	bit OW_WEATHER_DISABLED_F, [hl]
	jr nz, .done

	; Disabled: run weather only on odd frames (30 fps), using
	; wOverworldWeatherInternalTimer, a counter that wraps from 255 to 0.
;	ld a, [wOverworldWeatherInternalTimer]
;	and %1
;	jr z, .done

	; we are running weather, so decrement the cooldown if needed.
	ld a, [wOverworldWeatherCooldown]
	and a
	jr z, .no_cooldown
	dec a
	ld [wOverworldWeatherCooldown], a
.no_cooldown

	; If hUsedWeatherSpriteIndex reaches the first OAM slot used by
	; objects, move it to the slot before that.
	ldh a, [hUsedOAMIndex]
	; a = (SPRITEOAMSTRUCT_LENGTH * NUM_SPRITE_OAM_STRUCTS) - a
	cpl
	add NUM_SPRITE_OAM_STRUCTS * SPRITEOAMSTRUCT_LENGTH + 1
	ld hl, hUsedWeatherSpriteIndex
	cp [hl]
	jr nc, .ok
	add -SPRITEOAMSTRUCT_LENGTH
	ldh [hUsedWeatherSpriteIndex], a
.ok
	; While the weather is ending (cooldown not 0), don't spawn new weather
	; sprites: let the current ones finish falling.
	ld a, [wOverworldWeatherCooldown]
	and a
	jr nz, .on_cooldown

	ld a, [wCurWeather]
	ld hl, .DoWeather_Jumptable
	call JumpTable
.done
	; we are done, increment the weather frame counter (0->255->0)
	ld hl, wOverworldWeatherInternalTimer
	inc [hl]
	; always check if we have exceeded the sprite limit
	call WeatherSpriteLimitCheck
	jmp PopBCDEHL

.DoWeather_Jumptable:
	table_width 2
	dw DoNothing
	dw DoOverworldRain
	dw DoOverworldSnow
	dw DoOverworldRain
	dw DoOverworldSandstorm
	dw DoOverworldSunlight
	assert_table_length NUM_OW_WEATHERS + 1

.on_cooldown
	ld a, [wPrevWeather]
	call StackJumpTable

.Cooldown_Jumptable:
	table_width 2
	dw .cooldown_cleanup
	dw .rain_cooldown
	dw .snow_cooldown
	dw .rain_cooldown
	dw .sand_cooldown
	dw .sun_cooldown
	assert_table_length NUM_OW_WEATHERS + 1

.sand_cooldown
	call DoSandFall
	jr .cooldown_cleanup
.snow_cooldown
	call DoSnowFall
	jr .cooldown_cleanup
.rain_cooldown
	call DoRainFall
	call RainSplashCleanup
; Sunlight has nothing to wind down (DoOverworldSunlight handles it), but it
; needs an entry in the jumptable.
.sun_cooldown
.cooldown_cleanup
	; decrement the weather cooldown until it is 0
	ld a, [wOverworldWeatherCooldown]
	dec a
	jr nz, .done
	call ClearWeather
	call LoadWeatherGraphics
	jr .done

SpawnRandomWeatherFullScreen::
	lb bc, SCREEN_WIDTH_PX, SCREEN_HEIGHT_PX
; fallthrough
SpawnRandomWeatherCoords::
; Fill the free OAM slots with weather sprites at random positions, x from
; 0 to b and y from 0 to c, so weather is already on screen when it starts.
	ld a, [wCurWeather]
	assert OW_WEATHER_NONE == 0
	and a
	ret z
	ld a, [wCurWeather]
	assert OW_WEATHER_RAIN == 1
	dec a
	jr z, .rain
	assert OW_WEATHER_SNOW == 2
	dec a
	jr z, .snow
	assert OW_WEATHER_THUNDERSTORM == 3
	dec a
	jr z, .rain
	assert OW_WEATHER_SANDSTORM == 4
.sand
	call .find_oam_and_radomize
	ret c
	ld a, SANDSTORM_TILE
	ld [hli], a
	ld a, PAL_OW_WEATHER
	ld [hld], a
	dec hl
	dec hl
	ldh a, [hUsedWeatherSpriteIndex]
	cp l
	jr nc, .sand
	ld a, l
	ldh [hUsedWeatherSpriteIndex], a
	jr .sand

.snow
	call .find_oam_and_radomize
	ret c
	ld a, SNOWFLAKE_TILE
	ld [hli], a
	ld a, PAL_OW_WEATHER
	ld [hld], a
	dec hl
	dec hl
	ldh a, [hUsedWeatherSpriteIndex]
	cp l
	jr nc, .snow
	ld a, l
	ldh [hUsedWeatherSpriteIndex], a
	jr .snow

.rain
	call .find_oam_and_radomize
	ret c
	; 20% of them are splashes
	call Random
	cp 20 percent
	; a = carry ? RAINSPLASH_TILE : RAINDROP_TILE
	assert RAINDROP_TILE + 1 == RAINSPLASH_TILE
	ccf
	sbc a
	add RAINSPLASH_TILE
.got_tile
	ld [hli], a
	ld a, PAL_OW_WEATHER
	ld [hld], a
	dec hl
	dec hl
	ldh a, [hUsedWeatherSpriteIndex]
	cp l
	jr nc, .rain
	ld a, l
	ldh [hUsedWeatherSpriteIndex], a
	jr .rain

.find_oam_and_radomize
	push bc
	call ScanForEmptyOAM
	pop bc
	ret c
	; sprite coord (y, x) is (RandomRange(0, c), RandomRange(0, b))
	ld a, c
	call RandomRange
	ld [hli], a
	ld a, b
	call RandomRange
	ld [hli], a
	or 1
	ret

DoOverworldSnow:
	ld a, [wLoadedObjPal6]
	inc a
	jr z, .continue
	farcall LoadWeatherPal
.continue
rept 2
	; spawn two snowflakes
	call ScanForEmptyOAM
	call nc, SpawnSnowFlake
endr
; fallthrough
DoSnowFall:
	ld de, wShadowOAM
	ld h, d
	ld l, e
	ld b, NUM_SPRITE_OAM_STRUCTS
; for each sprite in wShadowOAM
.loop
	; if the sprite is hidden, skip it
	ld hl, SPRITEOAMSTRUCT_YCOORD
	ld a, [hl]
	cp OAM_YCOORD_HIDDEN
	jr z, .next

	; if the sprite is not a snowflake, skip it
	ld hl, SPRITEOAMSTRUCT_TILE_ID
	add hl, de
	ld a, [hli]
	cp SNOWFLAKE_TILE
	jr nz, .next

	; if the sprite doesn't use the weather palette, skip it
	ld a, [hl]
	cp PAL_OW_WEATHER
	jr nz, .next

	; the snowflake has a 0.1% chance of despawning
	call Random
	cp 1 percent
	jr nc, .ok
	call Random
	cp 10 percent
	jr c, .despawn
.ok

	; add the player's step vector (may be positive or negative)
	ld a, [wPlayerStepVectorY]
	ld c, a

	; get the sprite's y coord and subtract the player's step vector
	ld hl, SPRITEOAMSTRUCT_YCOORD
	add hl, de
	ld a, [hl]
	sub c
	ld c, a

	; sprites with an odd index move down 1 faster.
	call IsEvenSpriteIndex
	add c

	; minimum fall speed is 2
	add 2

	; if the sprite goes offscreen, despawn it, otherwise update its y coord
	ld hl, SPRITEOAMSTRUCT_YCOORD
	add hl, de
	cp OAM_YCOORD_HIDDEN
	ld [hl], a
	jr nc, .despawn

	; add the player's step vector (may be positive or negative)
	ld a, [wPlayerStepVectorX]
	ld c, a

	; sprite has a 50% chance to wiggle left 1.
	call Random
	and 1
	ld a, c
	jr nz, .no_add_1
	inc a
.no_add_1
	ld c, a

	; get the sprite's x coord and subtract the player's step vector + wiggle
	ld hl, SPRITEOAMSTRUCT_XCOORD
	add hl, de
	ld a, [hl]
	sub c

	; sprite can have 0 change in x coord (no wiggle or step vector)
	; so we increment a before subtracting to check for despawn (offscreen)
	inc a
	ld hl, SPRITEOAMSTRUCT_XCOORD
	add hl, de
	; sub 1 instead of dec a, to set carry
	sub 1 ; no-optimize a++|a--
	ld [hl], a
	jr c, .despawn
.next
	ld hl, SPRITEOAMSTRUCT_LENGTH
	add hl, de
	ld d, h
	ld e, l
	dec b
	jr nz, .loop
	ret

.despawn
	ld hl, SPRITEOAMSTRUCT_YCOORD
	add hl, de
	ld a, OAM_YCOORD_HIDDEN
	ld [hli], a
	xor a
	ld [hli], a
	ld [hli], a
	ld [hl], a
	jr .next

DoOverworldRain:
	ld a, [wLoadedObjPal6]
	cp PAL_OW_RAIN
	jr z, .continue
	farcall LoadWeatherPal
.continue
	ld a, [wCurWeather]
	cp OW_WEATHER_THUNDERSTORM
	jr nz, .no_lightning

	; 0.5% chance of lightning
	call Random
	cp 1 percent
	jr nc, .no_lightning
	call Random
	cp 50 percent
	call c, Lightning
.no_lightning
rept 3
	; spawn three raindrops
	call ScanForEmptyOAM
	call nc, SpawnRainDrop
endr
	call DoRainFall
; fallthrough
RainSplashCleanup:
	; Rain splashes stay on screen for up to 8 frames. Each OAM slot is
	; cleared on its own frame of the 8, so they don't all vanish at once.
	ld de, wShadowOAM
	ld b, NUM_SPRITE_OAM_STRUCTS
	ld c, 0
; for each sprite in wShadowOAM
.loop
	; if sprite tile is not a rain splash, skip it
	ld hl, SPRITEOAMSTRUCT_TILE_ID
	add hl, de
	ld a, [hli]
	cp RAINSPLASH_TILE
	jr nz, .next

	; only this slot's assigned tick (based on its OAM index) clears it,
	; spreading clears for all splashes evenly across the 8-tick window
	ld a, [wOverworldWeatherInternalTimer]
	and %111
	cp c
	jr nz, .next

	; hide the rain splash
	ld hl, SPRITEOAMSTRUCT_YCOORD
	add hl, de
	ld [hl], OAM_YCOORD_HIDDEN
.next
	ld hl, SPRITEOAMSTRUCT_LENGTH
	add hl, de
	ld d, h
	ld e, l
	inc c
	ld a, c
	and %111
	ld c, a
	dec b
	jr nz, .loop
	ret

SpawnSnowFlake:
	; 40% chance of spawning a snowflake.
	call Random
	cp 40 percent
	ret nc
	; 25% chance of spawning a snowflake on the right side of the screen.
	call Random
	and %11
	jr z, .spawn_on_right
	
	; sprite coord (y, x) is (0, RandomRange(0, SCREEN_WIDTH_PX + 7) + TILE_WIDTH)
	xor a
	ld [hli], a
	ld a, SCREEN_WIDTH_PX + 7
	call RandomRange
	; x-coord less than TILE_WIDTH is offscreen, so add TILE_WIDTH
	add TILE_WIDTH
	ld [hli], a
.finish
	ld a, SNOWFLAKE_TILE
	ld [hli], a
	ld a, PAL_OW_WEATHER
	ld [hld], a
	dec hl
	dec hl
	ldh a, [hUsedWeatherSpriteIndex]
	cp l
	ret nc
	ld a, l
	ldh [hUsedWeatherSpriteIndex], a
	ret

.spawn_on_right
	; sprite coord (y, x) is (RandomRange(0, OAM_YCOORD_HIDDEN), SCREEN_WIDTH_PX + TILE_WIDTH)
	ld a, OAM_YCOORD_HIDDEN
	call RandomRange
	ld [hli], a
	ld a, SCREEN_WIDTH_PX + TILE_WIDTH
	ld [hli], a
	jr .finish

ScanForEmptyOAM:
; return empty OAM slot in de or carry set if none
	ld de, wShadowOAM
	ld h, d
	ld l, e
	ldh a, [hUsedOAMIndex]
	; a = (SPRITEOAMSTRUCT_LENGTH * NUM_SPRITE_OAM_STRUCTS) - a
	cpl
	add NUM_SPRITE_OAM_STRUCTS * SPRITEOAMSTRUCT_LENGTH + 1
	; a = a / 4
	rrca
	rrca
	ld b, a
; scan wShadowOAM up to the first object OAM slot
.loop
	; if the sprite is hidden, return the slot
	ld a, [hl]
	cp OAM_YCOORD_HIDDEN
	ret z
	; next slot
	ld hl, SPRITEOAMSTRUCT_LENGTH
	add hl, de
	ld d, h
	ld e, l
	dec b
	jr nz, .loop
	; no empty slots
	scf
	ret

SpawnRainDrop:
	; 50% chance of spawning a raindrop on the right
	call Random
	and 1
	jr z, .spawn_on_right

	; sprite coord (y, x) is (0, RandomRange(0, SCREEN_WIDTH_PX + 7) + TILE_WIDTH)
	xor a
	ld [hli], a
	ld a, SCREEN_WIDTH_PX + 7
	call RandomRange
	; x-coord less than TILE_WIDTH is offscreen, so add TILE_WIDTH
	add TILE_WIDTH
	ld [hli], a
.finish
	ld a, RAINDROP_TILE
	ld [hli], a
	ld a, PAL_OW_WEATHER
	ld [hld], a
	dec hl
	dec hl
	ldh a, [hUsedWeatherSpriteIndex]
	cp l
	ret nc
	ld a, l
	ldh [hUsedWeatherSpriteIndex], a
	ret

.spawn_on_right
	; sprite coord (y, x) is (RandomRange(0, OAM_YCOORD_HIDDEN), SCREEN_WIDTH_PX + TILE_WIDTH)
	ld a, OAM_YCOORD_HIDDEN
	call RandomRange
	ld [hli], a
	ld a, SCREEN_WIDTH_PX + TILE_WIDTH
	ld [hli], a
	jr .finish

ClearWeather:
	; doing this will cause _UpdateSprites to hide all weather sprites.
	xor a
	ldh [hUsedWeatherSpriteIndex], a
	; Reset the sunlight cycle too.
	ld [wSunlightTimer], a
	ld [wSunlightIncCounter], a
.finish_clearing
	ret

DoRainFall:
	ld de, wShadowOAM
	ld h, d
	ld l, e
	ld b, NUM_SPRITE_OAM_STRUCTS
; for each sprite in wShadowOAM
.loop
	; if the sprite is hidden, skip it
	ld hl, SPRITEOAMSTRUCT_YCOORD
	ld a, [hl]
	cp OAM_YCOORD_HIDDEN
	jr z, .next

	; if the sprite is a splash, update splash.
	ld hl, SPRITEOAMSTRUCT_TILE_ID
	add hl, de
	ld a, [hli]
	cp RAINSPLASH_TILE
	jr z, .update_splash

	; if the sprite is not a raindrop, skip it
	cp RAINDROP_TILE
	jr nz, .next

	; if the sprite doesn't use the weather palette, skip it
	ld a, [hl]
	cp PAL_OW_WEATHER
	jr nz, .next

	; raindrops have a 5% chance of splashing.
	call Random
	cp 5 percent
	jr c, .splash

	; raindrops fall independently of player movement.
	ld hl, SPRITEOAMSTRUCT_YCOORD
	add hl, de
	ld a, [hl]
	ld c, a

	; sprites with an odd index move down 2 faster.
	call IsEvenSpriteIndex
	add a
	add c

	; minimum fall speed is 8
	add 8

	; if the sprite goes offscreen, despawn it, otherwise update its y coord
	ld hl, SPRITEOAMSTRUCT_YCOORD
	add hl, de
	cp OAM_YCOORD_HIDDEN
	ld [hl], a
	jr nc, .despawn

	ld hl, SPRITEOAMSTRUCT_XCOORD
	add hl, de
	ld a, [hl]
	ld c, a

	; sprites with an odd index move left 2 faster.
	call IsEvenSpriteIndex
	cpl
	inc a
	add a
	add c

	; minimum horizontal movement left is 4.
	sub 4

	; if the sprite goes offscreen, despawn it, otherwise update its x coord
	ld hl, SPRITEOAMSTRUCT_XCOORD
	add hl, de
	ld [hl], a
	jr c, .despawn
.next
	ld hl, SPRITEOAMSTRUCT_LENGTH
	add hl, de
	ld d, h
	ld e, l
	dec b
	jr nz, .loop
	ret

.despawn
	ld hl, SPRITEOAMSTRUCT_YCOORD
	add hl, de
	ld a, OAM_YCOORD_HIDDEN
	ld [hli], a
	xor a
	ld [hli], a
	ld [hli], a
	ld [hl], a
	jr .next

.update_splash
	; if the sprite doesn't use the weather palette, skip it
	ld a, [hl]
	cp PAL_OW_WEATHER
	jr nz, .next

	; Splashes stay on the ground, so they only move with the screen.
	ld a, [wPlayerStepVectorY]
;	add a
	ld c, a

	; get the sprite's y coord and subtract the player's step vector
	ld hl, SPRITEOAMSTRUCT_YCOORD
	add hl, de
	ld a, [hl]
	sub c

	; if the sprite goes offscreen, despawn it, otherwise update its y coord
	cp OAM_YCOORD_HIDDEN
	jr nc, .despawn
	ld [hli], a

	ld a, [wPlayerStepVectorX]
;	add a
	ld c, a

	; get the sprite's x coord and subtract the player's step vector
	ld a, [hl]
	sub c
	ld [hl], a
	jr .next

.splash
	; convert raindrop to splash
	ld hl, SPRITEOAMSTRUCT_TILE_ID
	add hl, de
	ld [hl], RAINSPLASH_TILE
	jr .next

DoOverworldSandstorm:
	ld a, [wLoadedObjPal6]
	cp PAL_OW_SAND
	jr z, .continue
	farcall LoadWeatherPal
.continue
rept 3
	; spawn three sand drops
	call ScanForEmptyOAM
	call nc, SpawnSandDrop
endr
; fallthrough
DoSandFall:
	ld de, wShadowOAM
	ld h, d
	ld l, e
	ld b, NUM_SPRITE_OAM_STRUCTS
; for each sprite in wShadowOAM
.loop
	; if the sprite is hidden, skip it
	ld hl, SPRITEOAMSTRUCT_YCOORD
	ld a, [hl]
	cp OAM_YCOORD_HIDDEN
	jr z, .next

	; if the sprite is not a sand drop, skip it
	ld hl, SPRITEOAMSTRUCT_TILE_ID
	add hl, de
	ld a, [hli]
	cp SANDSTORM_TILE
	jr nz, .next

	; if the sprite doesn't use the weather palette, skip it
	ld a, [hl]
	cp PAL_OW_WEATHER
	jr nz, .next

	; sand drops have a 5% chance of despawning.
	call Random
	cp 5 percent
	jr c, .despawn

	; quadruple the player's step vector (may be positive or negative)
	ld a, [wPlayerStepVectorY]
	add a
	add a
	ld c, a

	; get the sprite's y coord and subtract the player's quadrupled step vector
	ld hl, SPRITEOAMSTRUCT_YCOORD
	add hl, de
	ld a, [hl]
	sub c
	ld c, a

	; sprites with an odd index move up 2 slower.
	call IsEvenSpriteIndex
	add a
	add c

	; minimum rise speed is 4
	sub 4

	; if the sprite goes offscreen, despawn it, otherwise update its y coord
	ld hl, SPRITEOAMSTRUCT_YCOORD
	add hl, de
	cp OAM_YCOORD_HIDDEN
	ld [hl], a
	jr nc, .despawn

	; quadruple the player's step vector (may be positive or negative)
	ld a, [wPlayerStepVectorX]
	add a
	add a
	ld c, a

	; get the sprite's x coord and subtract the player's quadrupled step vector
	ld hl, SPRITEOAMSTRUCT_XCOORD
	add hl, de
	ld a, [hl]
	sub c
	ld c, a

	; sprites with an odd index move left 2 faster.
	call IsEvenSpriteIndex
	cpl
	inc a
	add a
	add c

	; minimum horizontal movement left is 12
	sub 12

	; if the sprite goes offscreen, despawn it, otherwise update its x coord
	ld hl, SPRITEOAMSTRUCT_XCOORD
	add hl, de
	ld [hl], a
	jr c, .despawn
.next
	ld hl, SPRITEOAMSTRUCT_LENGTH
	add hl, de
	ld d, h
	ld e, l
	dec b
	jr nz, .loop
	ret

.despawn
	ld hl, SPRITEOAMSTRUCT_YCOORD
	add hl, de
	ld a, OAM_YCOORD_HIDDEN
	ld [hli], a
	xor a
	ld [hli], a
	ld [hli], a
	ld [hl], a
	jr .next

SpawnSandDrop:
	; 50% chance of spawning a sand drop on the right
	call Random
	and 1
	jr z, .spawn_on_right

	; sprite coord (y, x) is (SCREEN_HEIGHT_PX + TILE_WIDTH, RandomRange(0, SCREEN_WIDTH_PX + 7) + TILE_WIDTH)
	ld a, SCREEN_HEIGHT_PX + TILE_WIDTH
	ld [hli], a
	ld a, SCREEN_WIDTH_PX + 7
	call RandomRange
	add TILE_WIDTH
	ld [hli], a
.finish
	ld a, SANDSTORM_TILE
	ld [hli], a
	ld a, PAL_OW_WEATHER
	ld [hld], a
	dec hl
	dec hl
	ldh a, [hUsedWeatherSpriteIndex]
	cp l
	ret nc
	ld a, l
	ldh [hUsedWeatherSpriteIndex], a
	ret

.spawn_on_right
	; sprite coord (y, x) is (RandomRange(0, OAM_YCOORD_HIDDEN), SCREEN_WIDTH_PX + TILE_WIDTH)
	ld a, OAM_YCOORD_HIDDEN
	call RandomRange
	ld [hli], a
	ld a, SCREEN_WIDTH_PX + TILE_WIDTH
	ld [hli], a
	jr .finish

IsEvenSpriteIndex:
; input: e = low byte of the sprite's address in wShadowOAM
; output: a = 1 if the sprite's index (e / 4) is odd, 0 if it's even
	ld a, e
	rra
	rra
	and 1
	ret

WeatherSpriteLimitCheck:
; The Game Boy draws at most 10 sprites per scanline. Count the sprites on
; each scanline in wWeatherScratch, and hide the extra weather sprites on
; any line with more than 10.
	ldh a, [rSVBK]
	push af
	ld a, BANK(wWeatherScratch)
	ldh [rSVBK], a
	xor a

	; clear wWeatherScratch
	ld hl, wWeatherScratch
	ld bc, SCREEN_HEIGHT_PX
	call ByteFill

	ld hl, wShadowOAM
	ld d, h
	ld e, l
	ld b, NUM_SPRITE_OAM_STRUCTS
; for each sprite in wShadowOAM
.loop
	ld a, [hl]
	; convert OAM y coord to screen y coord
	sub TILE_WIDTH * 2
	; skip sprites above or below the screen
	jr c, .next
	cp SCREEN_HEIGHT_PX + 1
	jr nc, .next
	; increment the bytes in wWeatherScratch for the 8 lines this sprite covers
	ld h, HIGH(wWeatherScratch)
	ld l, a
rept TILE_WIDTH - 1
	inc [hl]
	inc l
endr
	inc [hl]
.next
	ld hl, SPRITEOAMSTRUCT_LENGTH
	add hl, de
	ld e, l
	dec b
	jr nz, .loop

	; scan wWeatherScratch for scanlines with more than 10 sprites
	ld hl, wWeatherScratch
	; sprites per scanline limit
	ld a, 10
rept SCREEN_HEIGHT_PX - 1
	cp [hl]
	call c, SpriteLimitExceeded
	inc hl
endr
	cp [hl]
	call c, SpriteLimitExceeded

	pop af
	ldh [rSVBK], a
	ret

SpriteLimitExceeded:
; Scanline l (low byte of its wWeatherScratch entry) has more than 10
; sprites: hide all but 10 of them, from the last OAM slot to the first.
; Weather sprites use the first slots, so they're the ones hidden.
	push hl
	push af
	; initialize wSpriteOverlapCount to 0.
	xor a
	ld [wSpriteOverlapCount], a
	ld a, l
	; convert screen y coord to OAM y coord
	add TILE_WIDTH * 2
	ld c, a
	; d is still HIGH(wShadowOAM)
	ld hl, wShadowOAM + (NUM_SPRITE_OAM_STRUCTS - 1) * SPRITEOAMSTRUCT_LENGTH
	ld e, l
rept NUM_SPRITE_OAM_STRUCTS
	; a = distance between the OAM y coord and (scanline + 16)
	ld a, [hl]
	sub c
	; skip sprites that start below the scanline
	jr z, .continue_\@
	jr nc, .next_\@
.continue_\@
	; use two's complement to make a positive number
	cpl
	inc a
	; skip sprites that end above the scanline (distance >= TILE_WIDTH)
	cp TILE_WIDTH
	jr nc, .next_\@
	; hide every sprite after the 10th
	ld a, [wSpriteOverlapCount]
	inc a
	cp 11
	ld [wSpriteOverlapCount], a
	call nc, .delete_sprite
.next_\@
	ld hl, -SPRITEOAMSTRUCT_LENGTH
	add hl, de
	ld e, l
endr
	pop af
	pop hl
	ret

.delete_sprite
	; hl = sprite to delete
	ld a, [hl]
	ld [hl], OAM_YCOORD_HIDDEN
	; convert OAM y coord to screen y coord
	sub TILE_WIDTH * 2
	; decrement the bytes in wWeatherScratch for the 8 lines this sprite covers
	ld h, HIGH(wWeatherScratch)
	ld l, a
rept TILE_WIDTH - 1
	dec [hl]
	inc l
endr
	dec [hl]
	ret

Lightning:
	ld hl, wWeatherFlags
	bit OW_WEATHER_DO_FLY_F, [hl]
	ret nz
	bit OW_WEATHER_LIGHTNING_DISABLED_F, [hl]
	ret nz
	call SetWhitePals
	farcall ApplyPals
	ld de, SFX_THUNDER_OW
	call PlaySFX
	call DelayFrame
	farcall LoadMapPals
	farcall ClearSavedObjPals
	ld hl, wPalFlags
	set NO_DYN_PAL_APPLY_UNTIL_RESET_F, [hl]
	farcall CheckForUsedObjPals
	farcall OWFadePalettesInit
	ret

DoOverworldSunlight:
; Sunlight brightens the palettes a step every 3 frames for 15 frames, then
; darkens them back over the next 15, and starts again. wSunlightTimer holds
; the wOverworldWeatherInternalTimer value the cycle started at, and the low
; nibble of wSunlightIncCounter counts the brightening steps.

	; First check if there is a value in the Sunlight Timer.
	ld a, [wSunlightTimer]
	and a
	jr nz, .check1
	; Bit 7 of wSunlightIncCounter says whether the timer has been loaded,
	; in case the start time was 0.
	ld a, [wSunlightIncCounter]
	cp %10000000
	jr z, .check1
	; Load up the value
	ld a, [wOverworldWeatherInternalTimer]
	ld [wSunlightTimer], a
	; Set the flag
	ld a, %10000000
	ld [wSunlightIncCounter], a
	; Nothing occurs on the first cycle, so we're done here
	jr .done

.check1
; Only step on frames 3, 6, 9... of the cycle.
	ld hl, wSunlightTimer
	ld a, [wOverworldWeatherInternalTimer]
	sub a, [hl]
.mod_loop
	sub a, 3
	jr z, .increment
	jr c, .done
	jr .mod_loop
.increment
	ld hl, wSunlightTimer
	ld a, [wOverworldWeatherInternalTimer]
	sub a, [hl]
; Brighten up to frame 15, then darken.
	cp 15
	jr c, .inc_pals
	jr z, .inc_pals
	jr .dec_check

.inc_pals
	ld a, [wSunlightIncCounter]
	add 1
	ld [wSunlightIncCounter], a
	call Sunlight_IncPals
	jr .done

.dec_pals
	ld a, [wSunlightIncCounter]
	sub 1
	ld [wSunlightIncCounter], a
	call Sunlight_DecPals
	jr .done

.dec_check
	ld hl, wSunlightTimer
	ld a, [wOverworldWeatherInternalTimer]
	sub a, [hl]
.mod_loop2
	sub a, 3
	jr z, .decrement
	jr c, .done
	jr .mod_loop2
.decrement
	ld hl, wSunlightTimer
	ld a, [wOverworldWeatherInternalTimer]
	sub a, [hl]
	cp 30
	jr c, .dec_pals
.clear_timers
; Frame 30: the last darkening step, then start a new cycle. Reload the map
; palettes to get exactly the untinted colors back, since steps that were
; capped at 0 or 31 don't cancel out.
	call Sunlight_DecPals
	farcall LoadMapPals
	xor a
	ld [wSunlightTimer], a
	ld [wSunlightIncCounter], a
.done
	ret

Sunlight_IncPals:
	; Input:
	;   N/A
	; Operation:
	;   Attempts to slightly increment the overworld palettes
	; Output:
	;   N/A
	ldh a, [rSVBK]
	push af
	ld a, BANK(wBGPals1)
	ldh [rSVBK], a

	; Brighten the first 7 BG palettes: 7 * 4 = 28 colors.
	ld hl, wBGPals1
	ld e, 28
.attempt_inc_bg
	call SunTogglePreserveBlueGreen
	call UnpackColor
	call TrySaturateColor
	call PackColor
	dec e
	jr nz, .attempt_inc_bg

	; Restore the original bank
	pop af
	ldh [rSVBK], a

	; Update the pals. ApplyPals overwrites the water's animated colors, so
	; redraw the current frame of the water animation (now from the tinted
	; colors) right after it.
	farcall ApplyPals
	farcall AnimateWaterPalette
	ld a, TRUE
	ldh [hCGBPalUpdate], a
	ret

Sunlight_DecPals:
	; Input:
	;   N/A
	; Operation:
	;   Attempts to slightly decrement the overworld palettes
	; Output:
	;   N/A
	ldh a, [rSVBK]
	push af
	ld a, BANK(wBGPals1)
	ldh [rSVBK], a

	; Same logic as above.
	ld hl, wBGPals1
	ld e, 28
.attempt_dec_bg
	call SunTogglePreserveBlueGreen
	call UnpackColor
	call TryDesaturateColor
	call PackColor
	dec e
	jr nz, .attempt_dec_bg

	; Restore the bank
	pop af
	ldh [rSVBK], a

	; Update the pals, and redraw the water animation (see Sunlight_IncPals).
	farcall ApplyPals
	farcall AnimateWaterPalette
	ld a, TRUE
	ldh [hCGBPalUpdate], a
	ret


ResetSunlightPals::
	; Call this whenever the overworld's base palette gets reloaded
	; (e.g. returning from the Pokedex/Bag/Party menu) while sunlight
	; weather is active. Without this, wSunlightIncCounter keeps
	; counting from before the palette was reset, causing Sunlight_DecPals
	; to subtract from an already-base palette and overshoot into
	; colors darker than intended.
	xor a
	ld [wSunlightTimer], a
	ld [wSunlightIncCounter], a
	ret

UnpackColor:
	; Input:
	;   hl -> An RGB555 color in a palette
	; Outputs:
	;   b = red   (0-31)
	;   c = green (0-31)
	;   d = blue  (0-31)
	; On return:
	;   hl points to the head of the color again
	
	ld a, [hl]    ; 1/2; a = %gggRRRRR
	and %00011111 ; 2/2; a = %000RRRRR
	ld b, a       ; 1/1; b = %000RRRRR (b <- R done)
	
	ld a, [hli]   ; 1/2; a = %gggRRRRR
	and %11100000 ; 2/2; a = %ggg00000
	ld c, a       ; 1/1; c = %ggg00000
	
	ld a, [hl]    ; 1/2; a = %0BBBBBGG
	and %00000011 ; 2/2; a = %000000GG
	or c          ; 1/1; a = %ggg000GG
	rlca          ; 1/1; a = %gg000GGg
	rlca          ; 1/1; a = %g000GGgg
	rlca          ; 1/1; a = %000GGggg
	ld c, a       ; 1/1; c = %000GGggg (c <- G done)
	
	ld a, [hl]   ; 1/2; a = %0BBBBBGG
	and %01111100 ; 2/2; a = %0BBBBB00
	rrca          ; 1/1; a = %00BBBBB0
	rrca          ; 1/1; a = %000BBBBB
	ld d, a       ; 1/1; d = %000BBBBB (d <- B done)
	
	dec hl
	ret

PackColor:
	; Input:
	;   hl -> An RGB555 color in a palette
	;   b = a 5-bit R value (0-31)
	;   c = a 5-bit G value (0-31)
	;   d = a 5-bit B value (0-31)
	; Operation:
	;   Packs the new RGB555 color into the color in a palette pointed to by hl
	; Clobbers:
	;   a, e
	; On return:
	;   hl points to the next color in the palette
	swap c        ; %Gggg000G
	ld a, c       ; %Gggg000G
	rlca          ; %ggg000GG
	and %11100000 ; %GGG00000
	or b          ; %GGGRRRRR
	ld [hli], a
	ld a, c       ; %Gggg000G
	rrca          ; %GGggg000
	and %11000000 ; %GG000000
	or d          ; %GG0BBBBB
	rlca          ; %G0BBBBBG
	rlca          ; %0BBBBBGG
	ld [hli], a
	ret

TrySaturateColor:
	; Input:
	;   b = a 5-bit R value (0-31)
	;   c = a 5-bit G value (0-31)
	;   d = a 5-bit B value (0-31)
	; Operation:
	;   Brightens an RGB555 color by adding 1 to each channel that isn't
	;   preserved (see SunTogglePreserveBlueGreen), up to 31
	ld a, [wSunlightPreserveRed]
	and %00010000
	jr nz, .green
	ld a, b
	call TrySaturateChannel
	ld b, a
.green
	ld a, [wSunlightPreserveGreen]
	and %00100000
	jr nz, .blue
	ld a, c
	call TrySaturateChannel
	ld c, a
.blue
	ld a, [wSunlightPreserveBlue]
	and %01000000
	ret nz
	ld a, d
	call TrySaturateChannel
	ld d, a
	ret

TryDesaturateColor:
	; Input:
	;   b = a 5-bit R value (0-31)
	;   c = a 5-bit G value (0-31)
	;   d = a 5-bit B value (0-31)
	; Operation:
	;   Darkens an RGB555 color by subtracting 1 from each channel that isn't
	;   preserved (see SunTogglePreserveBlueGreen), down to 0
	ld a, [wSunlightPreserveRed]
	and %00010000
	jr nz, .green
	ld a, b
	call TryDesaturateChannel
	ld b, a
.green
	ld a, [wSunlightPreserveGreen]
	and %00100000
	jr nz, .blue
	ld a, c
	call TryDesaturateChannel
	ld c, a
.blue
	ld a, [wSunlightPreserveBlue]
	and %01000000
	ret nz
	ld a, d
	call TryDesaturateChannel
	ld d, a
	ret

TrySaturateChannel:
	; Input:
	;   a = a 5-bit RGB value (0-31)
	; Operation:
	;   Adds 1 to an RGB channel, up to 31
	; Output:
	;   a = a 5-bit RGB value, where 1 <= a <= 31
	inc a
	cp 32
	ret c
	ld a, 31
	ret

TryDesaturateChannel:
	; Input:
	;   a = a 5-bit RGB value (0-31)
	; Operation:
	;   Subtracts 1 from an RGB channel, down to 0
	; Output:
	;   a = a 5-bit RGB value, where 0 <= a <= 30
	sub 1
	ret nc
	xor a
	ret

SunTogglePreserveBlueGreen:
	; Input:
	;   N/A
	; Operation:
	;   Sets bits 6 and 5 of wSunlightIncCounter (wSunlightPreserveBlue
	;   and wSunlightPreserveGreen) on steps 2 and 4 of the cycle, and
	;   clears them on the others. Skipping blue and green on those steps
	;   tints the light red, like sunshine.
	;   (Sunlight never runs at night: SetCurrentWeather checks for that.)
	ld a, [wSunlightIncCounter]
	and %00001111
	cp 2
	jr z, .preserve_BG
	cp 4
	ld a, [wSunlightIncCounter]
	jr nz, .unset_BG
.preserve_BG
	or %01100000
	jr .done
.unset_BG
	and %10011111
.done
	ld [wSunlightIncCounter], a
	ret


; TogglePreserveRed, TogglePreserveGreen and TogglePreserveBlue are unused.

TogglePreserveRed:
	; Input:
	;   N/A
	; Operation:
	;   Toggles bit 4 of wSunlightPreserveRed.
	ld a, [wSunlightPreserveRed]
	and %00010000
	ld a, [wSunlightPreserveRed]
	jr nz, .unset
	or %00010000
	jr .done

.unset
	and %11101111
.done
	ld [wSunlightPreserveRed], a
	ret

TogglePreserveGreen:
	; Input:
	;   N/A
	; Operation:
	;   Toggles bit 5 of wSunlightPreserveGreen.
	ld a, [wSunlightPreserveGreen]
	and %00100000
	ld a, [wSunlightPreserveGreen]
	jr nz, .unset
	or %00100000
	jr .done

.unset
	and %11011111
.done
	ld [wSunlightPreserveGreen], a
	ret

TogglePreserveBlue:
	; Input:
	;   N/A
	; Operation:
	;   Toggles bit 6 of wSunlightPreserveBlue.
	ld a, [wSunlightPreserveBlue]
	and %01000000
	ld a, [wSunlightPreserveBlue]
	jr nz, .unset
	or %01000000
	jr .done

.unset
	and %10111111
.done
	ld [wSunlightPreserveBlue], a
	ret

LoadWeatherGraphics::
	ld a, [wCurWeather]
	assert OW_WEATHER_NONE == 0
	and a
	ret z
	assert OW_WEATHER_RAIN == 1
	dec a
	jr z, .rain
	assert OW_WEATHER_SNOW == 2
	dec a
	jr z, .snow
	assert OW_WEATHER_THUNDERSTORM == 3
	dec a
	jr z, .rain
	assert OW_WEATHER_SANDSTORM == 4
	dec a
	jr z, .sandstorm
	assert OW_WEATHER_SUNLIGHT == 5
	; We don't actually load any GFX for sun
	ret

.sandstorm
	lb bc, BANK(SandGFX), 1
	ld de, SandGFX
	jr .continue
.rain
	lb bc, BANK(RainGFX), 2
	ld de, RainGFX
	jr .continue
.snow
	lb bc, BANK(SnowGFX), 1
	ld de, SnowGFX
.continue
	ld hl, vTiles0 tile WEATHER_TILE_1
	jmp Get2bpp



RainGFX:   INCBIN "gfx/overworld/rain.2bpp"
SplashGFX: INCBIN "gfx/overworld/rain_splash.2bpp"
SnowGFX:   INCBIN "gfx/overworld/snow.2bpp"
SandGFX:   INCBIN "gfx/overworld/sand.2bpp"
