;=============================================================================
;  Station specials.  The station's SPEC list holds one record per special, ending $FF:
;    1  transporter: booth x0, x1, Bob's x range lo, hi, feet rows of booths 1-4
;    2  moving platform: x, row, width, steps left, travel, dir, speed lo, hi, tile, waits
;    3  box: x0, y0, x1, y1, tile (radioactive waste, the TNT store's walls)
;    4  text: character row, column, string, 0
;    5  the lift (station 8): x, row, x min, x max, row min, row max
;    6  pulverizers (station 9): beam row, beam x0, x1, top row min, max, four head x
;    7  the cannon (station 10): rest x, x min, x max, landing rows for 1, 2, 3 tons
;  Speeds are in 1/256 block per frame.
;=============================================================================

; BS_SPEC - read the SPEC list and draw the specials
BS_SPEC:
	xor	a
	ld	(TRANSON),a
	ld	(TRLOCK),a
	ld	(NPLAT),a
	ld	(HAZON),a
	ld	(WALLON),a
	ld	(LIFTON),a
	ld	(LIFTDRV),a
	ld	(PULVON),a
	ld	(CANON),a
	ld	(TNT),a
	ld	ix,PLATTAB
	ld	hl,(LISTS+10)
BSP0:	ld	a,(hl)
	inc	hl
	cp	1
	jr	z,BSP_TR
	cp	2
	jr	z,BSP_PL
	cp	3
	jp	z,BSP_BOX
	cp	4
	jp	z,BSP_TXT
	cp	5
	jp	z,BSP_LIFT
	cp	6
	jp	z,BSP_PULV
	cp	7
	jp	z,BSP_CAN
	ret
BSP_TR:	ld	de,TRX0		; 8 bytes: x0, x1, lo, hi, floors 1-4
	ld	bc,8
	ldir
	ld	a,1
	ld	(TRANSON),a
	push	hl
	call	DRAWBOOTHS
	pop	hl
	jr	BSP0
BSP_PL:	push	ix		; 10 bytes into the record, then a fraction of 0
	pop	de
	ld	bc,10
	ldir
	ld	(ix+10),0
	ld	a,(ix+8)
	cp	T_HAZARD
	jr	nz,BSP_P0
	ld	(HAZON),a
BSP_P0:	push	hl
	ld	c,(ix+0)
	ld	b,(ix+1)
	ld	e,(ix+2)
BSP_P1:	ld	a,(ix+8)
	call	PLOTIFEMPTY
	inc	c
	dec	e
	jr	nz,BSP_P1
	pop	hl
	ld	de,PLATLEN
	add	ix,de
	ld	a,(NPLAT)
	inc	a
	ld	(NPLAT),a
	jr	BSP0

; record layout (PLATTAB): the list's 10 bytes, then the fraction
PLATLEN	equ	11		; +0 x +1 row +2 width +3 steps left +4 travel +5 dir +6/+7 speed
				; +8 tile +9 waits for Bob at its start +10 fraction

; DRAWBOOTHS - four booths.  Booth n stands on floor F (TRF + n - 1):
;   row F-9  a sign: a bar from x0+1 to x1-1
;   row F-8  the sign's ends, with n lights between them
;   row F-7  the roof, x0 to x1
;   rows F-6 .. F-1  the walls at x0 and x1 (Bob fits between them)
DRAWBOOTHS:
	ld	hl,TRF
	ld	d,1		; booth number
DBO0:	push	hl
	push	de
	ld	a,(hl)
	sub	9
	ld	b,a		; sign top
	ld	a,(TRX0)
	inc	a
	ld	c,a
DBO1:	ld	a,T_DECOR
	call	PLOTIFEMPTY
	inc	c
	ld	a,(TRX1)
	cp	c
	jr	nz,DBO1
	inc	b		; the row of lights
	ld	a,(TRX0)
	inc	a
	ld	c,a
	ld	a,T_DECOR
	call	PLOTIFEMPTY
	ld	a,(TRX1)
	dec	a
	ld	c,a
	ld	a,T_DECOR
	call	PLOTIFEMPTY
	ld	a,(TRX0)	; lights: centre - (n - 1), every second block
	ld	e,a
	ld	a,(TRX1)
	add	a,e
	srl	a
	sub	d
	inc	a
	ld	c,a
	ld	e,d
DBO2:	ld	a,T_DECOR
	call	PLOTIFEMPTY
	inc	c
	inc	c
	dec	e
	jr	nz,DBO2
	inc	b		; the roof
	ld	a,(TRX0)
	ld	c,a
DBO3:	ld	a,T_DECOR
	call	PLOTIFEMPTY
	ld	a,(TRX1)
	cp	c
	jr	z,DBO3A
	inc	c
	jr	DBO3
DBO3A:
	ld	e,6		; the walls
DBO4:	inc	b
	ld	a,(TRX0)
	ld	c,a
	ld	a,T_DECOR
	call	PLOTIFEMPTY
	ld	a,(TRX1)
	ld	c,a
	ld	a,T_DECOR
	call	PLOTIFEMPTY
	dec	e
	jr	nz,DBO4
	pop	de
	pop	hl
	inc	hl
	inc	d
	ld	a,d
	cp	5
	jr	nz,DBO0
	ret

;-----------------------------------------------------------------------------
; TRYTRANS - Bob is standing still: in a booth, with a digit 1-4 for another booth held
;   and the transporter charged?  A = 1 if the trip has started, else 0.
;-----------------------------------------------------------------------------
TRYTRANS:
	ld	a,(TRANSON)
	or	a
	ret	z
	ld	a,(TRLOCK)
	or	a
	jr	nz,TT_NO
	ld	a,(BOBX)
	ld	b,a
	ld	a,(TRBLO)
	dec	a
	cp	b		; lo - 1 < x ?
	jr	nc,TT_NO
	ld	a,(TRBHI)
	cp	b		; hi >= x ?
	jr	c,TT_NO
	ld	a,(BOBY)	; which floor?
	add	a,BOBH
	ld	b,a
	ld	hl,TRF
	ld	c,1
TT1:	ld	a,(hl)
	cp	b
	jr	z,TT2
	inc	hl
	inc	c
	ld	a,c
	cp	5
	jr	nz,TT1
	jr	TT_NO
TT2:	push	bc
	call	DIGIT
	pop	bc
	jr	z,TT_NO
	cp	5
	jr	nc,TT_NO
	cp	c
	jr	z,TT_NO
	ld	(TRDEST),a
	ld	a,S_TRANS
	ld	(BOBSTATE),a
	xor	a
	ld	(TRTMR),a
	ld	hl,BOB_STAND_R	; his picture for the beam
	ld	a,(BOBDIR)
	or	a
	jr	z,TT3
	ld	hl,BOB_STAND_L
TT3:	ld	de,TRPIC
	ld	bc,BOBH
	ldir
	ld	a,1
	ret
TT_NO:	xor	a
	ret

;-----------------------------------------------------------------------------
; BOBTRANS - the trip, after TRANSPORT in the Atari code: 16 frames fading into sparkles
;   with a rising buzz, 8 frames gone (Bob moves to the new booth), 16 frames forming
;   again, then the transporter needs 45 frames to recharge.
;-----------------------------------------------------------------------------
BOBTRANS:
	ld	hl,TRTMR
	inc	(hl)
	ld	a,(hl)
	cp	40
	jr	nc,BTR_DONE
	cp	16
	jr	nz,BTR1
	ld	a,(TRDEST)	; arrive: Bob's feet on the chosen booth's floor
	ld	e,a
	ld	d,0
	ld	hl,TRF-1
	add	hl,de
	ld	a,(hl)
	sub	BOBH
	ld	(BOBY),a
	ld	a,16
BTR1:	ld	c,1		; how sparse: 1 = half the dots, 2 = a quarter, 0 = none
	cp	8
	jr	c,BTR2
	inc	c
	cp	16
	jr	c,BTR2
	ld	c,0
	cp	24
	jr	c,BTR2
	ld	c,2
	cp	32
	jr	c,BTR2
	ld	c,1
BTR2:	ld	hl,TRPIC
	ld	de,MELTBUF
	ld	b,BOBH
BTR3:	push	bc
	ld	a,c
	or	a
	ld	a,0
	jr	z,BTR5
	call	RANDOM
	pop	bc
	push	bc
	dec	c
	jr	z,BTR4
	ld	c,a
	call	RANDOM
	and	c
BTR4:	and	(hl)
BTR5:	ld	(de),a
	inc	hl
	inc	de
	pop	bc
	djnz	BTR3
	call	RANDOM		; the buzz
	and	$1F
	add	a,6
	ld	b,a
	ld	c,5
	jp	SOUND
BTR_DONE:
	xor	a
	ld	(BOBSTATE),a	; S_GROUND
	ld	(BOBANIM),a
	ld	a,45
	ld	(TRLOCK),a
	ret

;-----------------------------------------------------------------------------
; MOVEPLAT - move the platforms; one standing on a platform rides with it (UPDATE_LIFTS)
;-----------------------------------------------------------------------------
MOVEPLAT:
	ld	a,(FLASHCD)	; the death flash's rest (the testing cheat)
	or	a
	jr	z,MPF
	dec	a
	ld	(FLASHCD),a
MPF:	ld	a,(TRLOCK)	; the transporter recharges here too
	or	a
	jr	z,MP0
	dec	a
	ld	(TRLOCK),a
MP0:	ld	a,(NPLAT)
	or	a
	ret	z
	ld	b,a
	ld	ix,PLATTAB
MP1:	push	bc
	ld	a,(ix+9)	; station 9: a platform at the start of its run waits for Bob
	or	a
	jr	z,MP1A
	ld	a,(ix+3)
	cp	(ix+4)
	jr	nz,MP1A
	call	ONPLAT
	jr	nz,MP3
MP1A:	ld	a,(ix+10)	; steps this frame = (fraction + speed) / 256
	add	a,(ix+6)
	ld	(ix+10),a
	ld	a,(ix+7)
	adc	a,0
	jr	z,MP3
	ld	b,a
MP2:	push	bc
	call	PSTEP
	pop	bc
	djnz	MP2
MP3:	ld	de,PLATLEN
	add	ix,de
	pop	bc
	djnz	MP1
	ret

; PSTEP - one block for the platform at IX
PSTEP:	call	ONPLAT		; Z = Bob rides it
	push	af
	ld	b,(ix+1)
	ld	a,(ix+5)
	cp	1
	jr	nz,PS_LEFT
	ld	c,(ix+0)	; right: clear the left end, add a block at the right
	call	PERASE
	ld	a,c
	add	a,(ix+2)
	ld	c,a
	ld	a,(ix+8)
	call	PLOTIFEMPTY
	inc	(ix+0)
	jr	PS_BOB
PS_LEFT:
	dec	(ix+0)		; left: add a block at the left, clear the right end
	ld	c,(ix+0)
	ld	a,(ix+8)
	call	PLOTIFEMPTY
	ld	a,c
	add	a,(ix+2)
	ld	c,a
	call	PERASE
PS_BOB:	pop	af
	jr	nz,PS_END
	ld	a,(BOBX)	; carry Bob, within the screen
	add	a,(ix+5)
	cp	128-BOBW+1
	jr	nc,PS_END
	ld	(BOBX),a
PS_END:	dec	(ix+3)		; end of the run: turn round
	ret	nz
	ld	a,(ix+5)
	neg
	ld	(ix+5),a
	ld	a,(ix+4)
	ld	(ix+3),a
	ret

; PERASE - clear block (C, B) if it is this platform's tile
PERASE:	call	GETT
	cp	(ix+8)
	ret	nz
	xor	a
	jp	PLOT

; ONPLAT - Z if Bob stands on the platform at IX: on the ground (or in the transporter),
;   feet on its row, one of his middle feet over it
ONPLAT:	ld	a,(ix+8)	; a deadly bar carries nobody
	cp	T_PLAT
	ret	nz
	ld	a,(BOBSTATE)
	or	a
	ret	nz
	ld	a,(BOBY)
	add	a,BOBH
	cp	(ix+1)
	ret	nz
	ld	a,(BOBX)	; x + 3 >= px  and  x + 2 < px + w
	add	a,3
	cp	(ix+0)
	jr	c,OP_NO
	sub	1
	ld	c,a
	ld	a,(ix+0)
	add	a,(ix+2)
	dec	a
	cp	c		; px + w - 1 >= x + 2
	jr	c,OP_NO
	xor	a
	ret
OP_NO:	or	1
	ret

;=============================================================================
;  Boxes and text: radioactive waste (station 6), the TNT store (station 10)
;=============================================================================
BSP_BOX:
	ld	c,(hl)		; x0
	inc	hl
	ld	b,(hl)		; y0
	inc	hl
	ld	a,(hl)		; x1
	ld	(TMP1),a
	inc	hl
	ld	a,(hl)		; y1
	ld	(TMP2),a
	inc	hl
	ld	a,(hl)		; tile
	ld	(TMP3),a
	inc	hl
	cp	T_HAZARD
	jr	nz,BBX0
	ld	(HAZON),a
BBX0:	cp	T_WALL
	jr	nz,BBX1
	ld	(WALLON),a
BBX1:	push	hl
	ld	e,c
BBX2:	ld	c,e		; each row from x0 to x1
BBX3:	ld	a,(TMP3)
	call	PLOT
	ld	a,(TMP1)
	cp	c
	jr	z,BBX4
	inc	c
	jr	BBX3
BBX4:	ld	a,(TMP2)
	cp	b
	jr	z,BBX5
	inc	b
	jr	BBX2
BBX5:	pop	hl
	jp	BSP0

BSP_TXT:
	ld	a,(hl)		; character row
	inc	hl
	ld	e,(hl)		; column
	inc	hl
	push	hl
	ld	l,a		; BG + row * 64 + column
	ld	h,0
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	d,0
	add	hl,de
	ld	de,BG
	add	hl,de
	pop	de		; DE = the string
BTX1:	ld	a,(de)
	inc	de
	or	a
	jr	z,BTX2
	ld	(hl),a
	inc	hl
	jr	BTX1
BTX2:	ex	de,hl
	jp	BSP0

;-----------------------------------------------------------------------------
; WALLOK - may Bob stand at x = A?  Carry set if a wall or something deadly is in the
;   way (rows BOBY .. BOBY+4, his middle four columns).  Keeps A, BC, DE, HL.
;-----------------------------------------------------------------------------
WALLOK:	push	hl
	push	de
	push	bc
	ld	e,a
	ld	a,(WALLON)
	ld	d,a
	ld	a,(HAZON)
	or	d
	jr	z,WO_FREE
	ld	a,(BOBY)
	ld	b,a
	ld	d,5
WO_R:	ld	a,e
	inc	a
	ld	c,a
	ld	h,4
WO_C:	call	GETT
	cp	T_WALL
	jr	z,WO_BLK
	cp	T_HAZARD
	jr	nz,WO_C1
	ld	a,(INVULN)	; with the cheat on he walks through deadly things (else, caught
	or	a		;   in one, he could never move again)
	jr	z,WO_BLK
WO_C1:
	inc	c
	dec	h
	jr	nz,WO_C
	inc	b
	dec	d
	jr	nz,WO_R
WO_FREE:
	ld	a,e
	pop	bc
	pop	de
	pop	hl
	or	a
	ret
WO_BLK:	ld	a,e
	pop	bc
	pop	de
	pop	hl
	scf
	ret

; HAZCHECK - Bob touching something deadly dies (GV_TOUCH in the Atari code)
HAZCHECK:
	ld	a,(BOBSTATE)
	cp	S_DYING
	ret	z
	cp	S_TRANS
	ret	z
	ld	a,(PULVON)
	or	a
	jr	z,HZ0
	call	PULVHIT
	jp	z,KILLBOB
HZ0:	ld	a,(HAZON)
	or	a
	ret	z
	ld	a,(BOBY)
	ld	b,a
	ld	d,BOBH
HZ_R:	ld	a,(BOBX)
	inc	a
	ld	c,a
	ld	e,4
HZ_C:	call	GETT
	cp	T_HAZARD
	jp	z,KILLBOB
	inc	c
	dec	e
	jr	nz,HZ_C
	inc	b
	dec	d
	jr	nz,HZ_R
	ret

;=============================================================================
;  The lift (station 8, LIFT_CONTROL).  Standing on it, ENTER hands the arrows to the
;  lift; ENTER or SPACE hands them back (the Atari used SPACE for the lift and the fire
;  button to jump; here SPACE jumps, so the lift has its own key).  It moves sideways at walking speed, rises a row
;  every 8 frames and drops a row every 4, carrying Bob.  Scissor arms reach down to
;  the floor and fold as it moves.
;=============================================================================
LIFTW	equ	13

BSP_LIFT:
	ld	de,LIFTX	; x, row, x min, x max, row min, row max
	ld	bc,6
	ldir
	ld	a,1
	ld	(LIFTON),a
	xor	a
	ld	(LIFTPH),a
	ld	(LIFTFR),a
	push	hl
	call	DRAWLIFT
	pop	hl
	jp	BSP0

; ONLIFT - Z if Bob stands on the lift
ONLIFT:	ld	a,(LIFTON)
	or	a
	jr	z,OL_NO
	ld	a,(BOBSTATE)
	or	a
	ret	nz
	ld	a,(BOBY)
	add	a,BOBH
	ld	hl,LIFTROW
	cp	(hl)
	ret	nz
	ld	a,(BOBX)
	add	a,3
	ld	hl,LIFTX
	cp	(hl)
	jr	c,OL_NO
	ld	a,(hl)
	add	a,LIFTW+1
	ld	c,a
	ld	a,(BOBX)
	cp	c		; x < lift x + 14 (his middle feet over it)
	jr	nc,OL_NO
	xor	a
	ret
OL_NO:	or	1
	ret

; LIFTSPACE - ENTER pressed on the ground: take or give up the controls.  A = 1 if used.
LIFTSPACE:
	ld	a,(LIFTDRV)
	or	a
	jr	nz,LS_OFF
	call	ONLIFT
	ld	a,0
	ret	nz
	ld	a,1
	ld	(LIFTDRV),a
	ret
LS_OFF:	xor	a
	ld	(LIFTDRV),a
	inc	a
	ret

; MOVELIFT - while Bob drives: arrows move the lift and him with it.  The platform is
;   in the background (Bob stands on it); the scissor arms are a sprite (DRAWARMS).
MOVELIFT:
	ld	a,(LIFTDRV)
	or	a
	ret	z
	call	ONLIFT		; knocked off or dead: controls off
	jr	z,ML0
	xor	a
	ld	(LIFTDRV),a
	ret
ML0:	ld	a,(KEYNOW)
	ld	e,a
	bit	5,e		; sideways, at walking speed
	jr	z,ML1
	call	STEP
	jr	nc,ML_V
	ld	a,(LIFTXMIN)
	ld	c,a
	ld	a,(LIFTX)
	cp	c
	jr	z,ML_V
	dec	a
	ld	(LIFTX),a
	ld	c,a		; new block at the left, old one off the right
	ld	a,(LIFTROW)
	ld	b,a
	ld	a,T_PLAT
	call	PLOTIFEMPTY
	ld	a,c
	add	a,LIFTW
	ld	c,a
	call	LIFTOFF
	ld	hl,BOBX
	dec	(hl)
	jr	ML_V
ML1:	bit	6,e
	jr	z,ML_V
	call	STEP
	jr	nc,ML_V
	ld	a,(LIFTXMAX)
	ld	c,a
	ld	a,(LIFTX)
	cp	c
	jr	z,ML_V
	ld	c,a		; old block off the left, new one at the right
	ld	a,(LIFTROW)
	ld	b,a
	call	LIFTOFF
	ld	a,c
	add	a,LIFTW
	ld	c,a
	ld	a,T_PLAT
	call	PLOTIFEMPTY
	ld	hl,LIFTX
	inc	(hl)
	ld	hl,BOBX
	inc	(hl)
ML_V:	ld	d,0		; up a row every 8 frames, down every 4
	bit	3,e
	jr	z,ML3
	ld	a,(FRAMES)
	and	7
	jr	nz,ML3
	dec	d
ML3:	bit	4,e
	jr	z,ML4
	ld	a,(FRAMES)
	and	3
	jr	nz,ML4
	inc	d
ML4:	ld	a,d
	or	a
	jr	z,ML_SND
	ld	a,(LIFTROW)
	add	a,d
	ld	c,a
	ld	a,(LIFTRMIN)
	dec	a
	cp	c
	jr	nc,ML_SND
	ld	a,(LIFTRMAX)
	cp	c
	jr	c,ML_SND
	push	de
	push	bc
	call	LIFTROWOFF
	pop	bc
	ld	a,c
	ld	(LIFTROW),a
	pop	de
	ld	a,(BOBY)
	add	a,d
	ld	(BOBY),a
	ld	a,(LIFTPH)	; the arms fold one step
	add	a,d
	jp	p,ML5
	ld	a,5
ML5:	cp	6
	jr	c,ML6
	xor	a
ML6:	ld	(LIFTPH),a
	call	DRAWLIFT
ML_SND:	ld	a,(KEYNOW)	; the motor hum
	and	$78
	ret	z
	ld	bc,$2802
	jp	SOUND

; DRAWLIFT - the platform at (LIFTX, LIFTROW)
DRAWLIFT:
	ld	a,(LIFTROW)
	ld	b,a
	ld	a,(LIFTX)
	ld	c,a
	ld	e,LIFTW
DL1:	ld	a,T_PLAT
	call	PLOTIFEMPTY
	inc	c
	dec	e
	jr	nz,DL1
	ret
; LIFTROWOFF - clear the platform's row
LIFTROWOFF:
	ld	a,(LIFTROW)
	ld	b,a
	ld	a,(LIFTX)
	ld	c,a
	ld	e,LIFTW
LRO1:	call	LIFTOFF
	inc	c
	dec	e
	jr	nz,LRO1
	ret
; LIFTOFF - clear block (C, B) if it is platform
LIFTOFF:
	call	GETT
	cp	T_PLAT
	ret	nz
	xor	a
	jp	PLOT

; DRAWARMS - the scissor arms from under the platform to the floor, as sprites: two
;   columns (7 + 6 blocks) cut from a repeating 6-row picture at the fold phase
DRAWARMS:
	ld	a,(LIFTON)
	or	a
	ret	z
	ld	a,(LIFTROW)
	ld	b,a
	ld	a,46
	sub	b
	ret	z
	ld	d,a		; rows
	inc	b
	push	bc
	push	de
	ld	a,(LIFTPH)
	ld	e,a
	ld	d,0
	ld	hl,ARMSL
	add	hl,de
	ld	a,(LIFTX)
	ld	c,a
	pop	de
	push	de
	call	SPRITE
	pop	de
	pop	bc
	ld	a,(LIFTPH)
	ld	l,a
	ld	h,0
	push	de
	ld	de,ARMSR
	add	hl,de
	pop	de
	ld	a,(LIFTX)
	add	a,7
	ld	c,a
	jp	SPRITE
; arms: columns 2m and 12-2m for m = 0, 1, 2, 3, 2, 1 ...; 6 phases + 30 rows
ARMSL:	db	$80,$20,$08,$02,$08,$20, $80,$20,$08,$02,$08,$20, $80,$20,$08,$02,$08,$20
	db	$80,$20,$08,$02,$08,$20, $80,$20,$08,$02,$08,$20, $80,$20,$08,$02,$08,$20
ARMSR:	db	$04,$10,$40,$00,$40,$10, $04,$10,$40,$00,$40,$10, $04,$10,$40,$00,$40,$10
	db	$04,$10,$40,$00,$40,$10, $04,$10,$40,$00,$40,$10, $04,$10,$40,$00,$40,$10

;=============================================================================
;  Pulverizers (station 9, MOVE_PULVERIZERS).  Four heads hang from a beam; each waits,
;  drops to the floor, rises again.  A head is deadly; its rod is not.  The wait is
;  (18 - 2 * min(zone, 9)) * 4 + 20 frames.
;=============================================================================
PULVW	equ	10

BSP_PULV:
	ld	a,(hl)		; beam row
	ld	b,a
	inc	b
	ld	(PULVBEAM),a
	inc	hl
	ld	c,(hl)		; beam x0
	inc	hl
	ld	a,(hl)		; beam x1
	ld	(TMP1),a
	inc	hl
	ld	a,(hl)
	ld	(PULVTOP),a
	inc	hl
	ld	a,(hl)
	ld	(PULVBOT),a
	inc	hl
	push	hl
	dec	b
	push	bc		; the beam ...
PV1:	ld	a,T_SURF
	call	PLOT
	ld	a,(TMP1)
	cp	c
	jr	z,PV2
	inc	c
	jr	PV1
PV2:	pop	bc		; ... and its two posts, down to the floor
	push	bc
PV3:	inc	b
	ld	a,T_DECOR
	call	PLOT
	ld	a,b
	cp	46
	jr	nz,PV3
	pop	bc
	ld	a,(TMP1)
	ld	c,a
PV4:	inc	b
	ld	a,T_DECOR
	call	PLOT
	ld	a,b
	cp	46
	jr	nz,PV4
	pop	hl
	ld	ix,PULVTAB	; four heads: x, top row, direction, timer
	ld	b,4
PV5:	ld	a,(hl)
	inc	hl
	ld	(ix+0),a
	ld	a,(PULVTOP)
	ld	(ix+1),a
	ld	(ix+2),1
	call	RANDOM
	and	$7F
	add	a,20
	ld	(ix+3),a
	ld	de,4
	add	ix,de
	djnz	PV5
	ld	a,1
	ld	(PULVON),a
	jp	BSP0

; MOVEPULV - one row every second frame.  The heads are sprites (DRAWPULV), the rods
;   background blocks; HAZCHECK tests Bob against the heads.
MOVEPULV:
	ld	a,(PULVON)
	or	a
	ret	z
	ld	ix,PULVTAB
	ld	b,4
MV0:	push	bc
	ld	a,(ix+3)	; waiting?
	or	a
	jr	z,MV1
	dec	(ix+3)
	jr	MVNEXT
MV1:	ld	a,(FRAMES)
	and	1
	jr	nz,MVNEXT
	ld	a,(ix+2)	; the rod is background: down, the old top row becomes rod;
	cp	1		;   up, the row the head moves into loses its rod
	ld	b,(ix+1)
	ld	a,T_DECOR
	jr	z,MV0A
	dec	b
	xor	a
MV0A:	push	af
	ld	a,(ix+0)
	add	a,4
	ld	c,a
	pop	af
	call	PLOT
	inc	c
	call	PLOT
	ld	a,(ix+1)
	add	a,(ix+2)
	ld	(ix+1),a
	ld	c,a
	ld	a,(ix+2)
	cp	1
	jr	nz,MV_UP
	ld	a,(PULVBOT)	; down: at the bottom, a thump and back up
	cp	c
	jr	nz,MVNEXT
	ld	(ix+2),$FF
	ld	bc,$1006
	call	SOUND
	jr	MVNEXT
MV_UP:	ld	a,(PULVTOP)	; up: at the top, wait
	cp	c
	jr	nz,MVNEXT
	ld	(ix+2),1
	ld	a,(ZONE)
	cp	10
	jr	c,MV2
	ld	a,9
MV2:	add	a,a
	ld	c,a
	ld	a,18
	sub	c
	add	a,a
	add	a,a
	add	a,20
	ld	(ix+3),a
MVNEXT:	ld	de,4
	add	ix,de
	pop	bc
	djnz	MV0
	ret

; DRAWPULV - each head (10 x 2 blocks, as 7 + 3)
DRAWPULV:
	ld	a,(PULVON)
	or	a
	ret	z
	ld	ix,PULVTAB
	ld	a,4
DP0:	push	af
	ld	c,(ix+0)
	ld	b,(ix+1)
	ld	d,2
	ld	hl,HEADL
	call	SPRITE
	ld	a,(ix+0)
	add	a,7
	ld	c,a
	ld	b,(ix+1)
	ld	d,2
	ld	hl,HEADR
	call	SPRITE
DP1:	ld	de,4
	add	ix,de
	pop	af
	dec	a
	jr	nz,DP0
	ret
HEADL:	db	$FE,$DE		; ####### / ##.####
HEADR:	db	$E0,$60		; ###     / .##

; PULVHIT - Z if Bob overlaps a head: head x .. x+9, top .. top+1 against Bob x+1 .. x+4,
;   y .. y+5
PULVHIT:
	ld	ix,PULVTAB
	ld	b,4
PH0:	ld	a,(BOBX)	; x: bob.x+4 >= hx  and  hx+9 >= bob.x+1
	add	a,4
	cp	(ix+0)
	jr	c,PHNEXT
	ld	a,(ix+0)
	add	a,8
	ld	hl,BOBX
	cp	(hl)
	jr	c,PHNEXT
	ld	a,(BOBY)	; y: bob.y+5 >= top  and  top+1 >= bob.y
	add	a,5
	cp	(ix+1)
	jr	c,PHNEXT
	ld	a,(ix+1)
	inc	a
	ld	hl,BOBY
	cp	(hl)
	jr	c,PHNEXT
	xor	a
	ret
PHNEXT:	ld	de,4
	add	ix,de
	djnz	PH0
	or	1
	ret

;=============================================================================
;  The cannon (station 10, CANNON).  Bob collects TNT in the store (each bundle adds
;  its tons), walks into the cannon's mouth and is loaded; arrows roll the cannon,
;  SPACE fires.  One ton lands him on the lowest platform, two on the middle, three
;  on the top; more blows him off the top of the mine.  The empty cannon rolls back.
;=============================================================================
CANW	equ	13

BSP_CAN:
	ld	de,CANX		; rest x, x min, x max, landing rows
	ld	bc,6
	ldir
	ld	a,(CANX)
	ld	(CANREST),a
	ld	a,1
	ld	(CANON),a
	xor	a
	ld	(CANST),a
	ld	(CANFR),a
	push	hl
	call	SHOWTNT
	pop	hl
	jp	BSP0

; the cannon, rows 41-46, 13 blocks wide, drawn as two sprites (7 + 6 blocks) every
;   frame; Bob stands inside between the barrel walls
CANPICL: db	$60,$60,$60,$FE,$FE,$70	; .##.... / #######  / .###...
CANPICR: db	$18,$18,$18,$FC,$FC,$E0	; ...##.  / ######   / ###...
DRAWCAN:
	ld	a,(CANON)
	or	a
	ret	z
	ld	a,(CANX)
	ld	c,a
	ld	b,41
	ld	d,6
	ld	hl,CANPICL
	call	SPRITE
	ld	a,(CANX)
	add	a,7
	ld	c,a
	ld	b,41
	ld	d,6
	ld	hl,CANPICR
	jp	SPRITE

; MOVECAN - every frame on station 10
MOVECAN:
	ld	a,(CANON)
	or	a
	ret	z
	ld	a,(CANST)
	or	a
	ret	nz
	ld	a,(CANX)	; empty: roll back to rest, one block every 3 frames or so
	ld	hl,CANREST
	cp	(hl)
	jr	z,MC1
	ld	a,(CANFR)
	add	a,90
	ld	(CANFR),a
	jr	nc,MC1
	ld	a,(CANX)
	inc	a
	ld	(CANX),a
MC1:	ld	a,(TNT)		; loaded with TNT, Bob on the floor at the mouth gets in
	or	a
	ret	z
	ld	a,(BOBSTATE)
	or	a
	ret	nz
	ld	a,(BOBY)
	cp	47-BOBH
	ret	nz
	ld	a,(CANX)
	add	a,3
	ld	hl,BOBX
	sub	(hl)
	add	a,1		; within one block of the mouth
	cp	3
	ret	nc
	ld	a,(CANX)
	add	a,3
	ld	(hl),a
	ld	a,1
	ld	(CANST),a
	ld	a,S_CANNON
	ld	(BOBSTATE),a
	ld	bc,$2010
	jp	SOUND

; BOBCANNON - inside: arrows roll the cannon, a fresh SPACE fires
BOBCANNON:
	ld	a,(KEYNOW)
	ld	e,a
	bit	7,e
	jr	z,BC1
	ld	a,(KEYOLD)
	bit	7,a
	jr	nz,BC1
	ld	a,2		; fire
	ld	(CANST),a
	ld	a,S_FLY
	ld	(BOBSTATE),a
	ld	bc,$0840
	call	SOUND
	ld	bc,$1820
	jp	SOUND
BC1:	ld	d,0
	bit	5,e
	jr	z,BC2
	dec	d
BC2:	bit	6,e
	jr	z,BC3
	inc	d
BC3:	ld	a,d
	or	a
	ret	z
	call	STEP
	ret	nc
	ld	a,(CANX)
	add	a,d
	ld	hl,CANXMIN
	cp	(hl)
	ret	c
	ld	c,a
	ld	a,(CANXMAX)
	cp	c
	ret	c
	ld	a,c
	ld	(CANX),a
	add	a,3
	ld	(BOBX),a
	ret

; BOBFLY - shot from the cannon: up a row a frame to the platform the charge reaches
BOBFLY:	ld	a,(TNT)
	cp	4
	jr	nc,BF_HIGH
	ld	e,a
	ld	d,0
	ld	hl,CANROWS-1
	add	hl,de
	ld	a,(BOBY)
	add	a,BOBH
	cp	(hl)
	jr	z,BF_LAND
	jr	c,BF_LAND
BF_UP:	ld	hl,BOBY
	dec	(hl)
	ld	a,(FRAMES)	; whistle
	and	3
	ret	nz
	ld	a,(BOBY)
	add	a,8
	ld	b,a
	ld	c,4
	jp	SOUND
BF_HIGH:
	ld	a,(BOBY)	; too much TNT: off the top of the mine
	cp	4
	jr	nc,BF_UP
	ld	a,(INVULN)	; with the cheat on he drops back down instead
	or	a
	jp	z,KILLBOB
	ld	a,S_FALL
	ld	(BOBSTATE),a
	xor	a
	ld	(CANST),a
	ld	(TNT),a
	ld	(JIDX),a
	ld	(FALLROWS),a
	jp	SHOWTNT
BF_LAND:
	xor	a
	ld	(BOBSTATE),a	; S_GROUND
	ld	(CANST),a
	ld	(TNT),a
	ld	(JIDX),a
	call	SHOWTNT
	call	FOLLOW		; no girder under him: he falls
	ret

; SHOWTNT - "TNT n" at the end of the status line (station 10)
SHOWTNT:
	ld	a,(CANON)
	or	a
	ret	z
	ld	hl,58
	ld	de,T_TNT
	call	PRINT
	ld	a,(TNT)
	cp	10
	jr	c,STN1
	ld	a,9
STN1:	add	a,'0'
	ld	(BG+62),a
	ld	(VRAM+62),a
	ret
T_TNT:	db	"TNT ",0
