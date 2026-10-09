;=============================================================================
;  MINER 2049er for the TRS-80 Model III
;  A port of Bill Hogue's 1982 Atari game, written from the commented disassembly
;  of the Atari cartridge.  Stations are converted from the Atari ROM's own data.
;
;  Assemble:  zmac --zmac -o miner3.cmd miner3.asm
;  Load:      TRSDOS 1.3 (48K), type MINER3
;
;  The game takes over the machine: interrupts off, no ROM or DOS calls.
;  Screen: 64 x 16 characters; block graphics give 128 x 48 "blocks".
;  Text row 0 (blocks 0-2) is the status line; the mine is block rows 3-47.
;  Timing: one game frame per 30 Hz real-time-clock tick (port $E0 bit 2).
;=============================================================================

VRAM	equ	$3C00		; video memory, 64 x 16
BG	equ	$9C00		; background copy of the screen (VRAM + $6000)
TYPEMAP	equ	$A000		; one byte per block: what is there (128 x 48 = $1800 bytes)
DIRTY	equ	$B800		; VRAM addresses covered by sprites last frame (2 bytes each)
MAXDIRTY equ	200
KBROW6	equ	$3840		; ENTER CLEAR BREAK UP DOWN LEFT RIGHT SPACE (bits 0-7)
KBROW7	equ	$3880		; SHIFT (bit 0)
KBDIG0	equ	$3810		; digits 0-7
KBROW1	equ	$3802		; H I J K L M N O (bits 0-7)
KBROW2	equ	$3804		; P Q R S T U V W (bits 0-7)
KBDIG8	equ	$3820		; digits 8, 9

; block types in TYPEMAP
T_EMPTY	equ	0
T_ITEM	equ	1		; item picture
T_LADDER equ	2		; ladder or slide
T_SURF	equ	3		; top row of a girder: Bob stands on it
T_DASH	equ	4		; lit block of a girder's lower row
T_GAP	equ	5		; unlit block of a girder's lower row: an unclaimed section
T_FLOOR	equ	6		; the bottom floor (cannot be claimed)
T_HAZARD equ	7		; deadly to touch
T_DECOR	equ	8		; scenery: transporter booths
T_PLAT	equ	9		; a moving platform: stand on it
T_WALL	equ	10		; a wall: blocks Bob

; Bob's states
S_GROUND equ	0
S_JUMP	equ	1
S_FALL	equ	2
S_LADDER equ	3
S_SLIDE	equ	4
S_DYING	equ	5
S_TRANS	equ	6
S_CANNON equ	7		; loaded in the cannon
S_FLY	equ	8		; shot from the cannon

BOBW	equ	6
BOBH	equ	6

	org	$5200

;=============================================================================
;  START - entry point.  Interrupts off, our own stack, RTC status enabled.
;=============================================================================
START:	di
	ld	sp,$FF00
	ld	a,$04		; port E0: enable the RTC interrupt *status* (we poll it)
	out	($E0),a
	xor	a		; port EC: 64 columns, the normal character set (its codes
	out	($EC),a		;   192-255 are the symbols some items are drawn with)
	ld	hl,$1234
	ld	(SEED),hl
	xor	a
	ld	(INVULN),a
	ld	(IKEYOLD),a
	ld	(SNDN),a
	call	TITLE
NEWGAME:
	xor	a
	ld	(SCORE),a
	ld	(SCORE+1),a
	ld	(SCORE+2),a
	ld	a,3
	ld	(LIVES),a
	ld	a,(STARTST)
	ld	(STATION),a
	ld	a,1
	ld	(ZONE),a
	ld	a,1
	ld	(XLIFE),a	; extra life still to be earned
PLAYSTATION:
	call	BUILD_STATION
	call	PREPARE
	call	PLAY		; returns when the turn ends: A = 0 died, 1 station cleared
	or	a
	jr	nz,CLEARED
	ld	a,(LIVES)
	dec	a
	ld	(LIVES),a
	jr	nz,PLAYSTATION
	call	GAMEOVER
	call	TITLE
	jr	NEWGAME
CLEARED:
	call	TALLY		; bonus into the score
	ld	a,(STATION)
	inc	a
	cp	11
	jr	c,NEXTST
	ld	a,(ZONE)
	inc	a
	ld	(ZONE),a
	ld	a,1
NEXTST:	ld	(STATION),a
	jr	PLAYSTATION

;=============================================================================
;  WAITTICK - wait for the next 30 Hz real-time-clock tick, then clear it.  Port E0 reads
;  the interrupt latch inverted (MAME: ~(mask & irq)), so a pending tick reads as 0.
;=============================================================================
WAITTICK:
	push	bc
WT0:	in	a,($E0)		; interrupt status, active low: bit 2 = 0 when the RTC has ticked
	and	$04
	jr	z,WT2
	ld	a,(SNDN)	; while waiting, play the queued sound (SOUND): the frame's
	or	a		;   spare time makes the noise, so sound never slows the game
	jr	z,WT0
	dec	a
	ld	(SNDN),a
	ld	a,(SOUNDON)
	or	a
	jr	z,WT0
	ld	a,1
	out	($FF),a
	ld	a,(SNDB)
	ld	b,a
WT1:	djnz	WT1
	ld	a,2
	out	($FF),a
	ld	a,(SNDB)
	ld	b,a
WT1A:	djnz	WT1A
	jr	WT0
WT2:	pop	bc
	in	a,($EC)		; reading port EC clears the RTC interrupt
	ld	hl,(FRAMES)
	inc	hl
	ld	(FRAMES),hl
	ret

;=============================================================================
;  Screen primitives
;=============================================================================
; CLS - clear the background copy, the type map and the screen
CLS:	ld	hl,BG
	ld	de,BG+1
	ld	bc,1023
	ld	(hl),128
	ldir
	ld	hl,TYPEMAP
	ld	de,TYPEMAP+1
	ld	bc,$17FF
	ld	(hl),0
	ldir
	ld	hl,DIRTY
	ld	(DPTR),hl
	; fall into SHOWBG
; SHOWBG - copy the whole background to the screen
SHOWBG:	ld	hl,BG
	ld	de,VRAM
	ld	bc,1024
	ldir
	ret

; CELL - block (C = x 0-127, B = y 0-47) -> HL = BG address of its character, A = bit mask
;   uses DE
CELL:	ld	h,YM2/256	; mask index = (y mod 3) * 2 + (x and 1)
	ld	l,b
	ld	a,(hl)
	bit	0,c
	jr	z,CELL1
	inc	a
CELL1:	ld	l,a
	ld	h,MASKS/256
	ld	e,(hl)
	ld	h,YVL/256	; BG address = VRAM row address + $6000 + x / 2
	ld	l,b
	ld	a,c
	srl	a
	add	a,(hl)		; (a row starts on a multiple of 64: no carry)
	inc	h
	ld	h,(hl)
	ld	l,a
	ld	a,h
	add	a,(BG-VRAM)/256
	ld	h,a
	ld	a,e
	ret

; TADDR - block (C = x, B = y) -> HL = its TYPEMAP address.  TYPEMAP = $A000 + y*128 + x
TADDR:	ld	a,b
	srl	a
	add	a,TYPEMAP/256
	ld	h,a
	ld	a,b
	rrca			; bit 0 of y -> bit 7
	and	$80
	or	c
	ld	l,a
	ret

; GETT - A = type of block (C, B); out of range = empty.  Keeps BC.
GETT:	ld	a,c
	cp	128
	jr	nc,GETT0
	ld	a,b
	cp	48
	jr	nc,GETT0
	push	hl
	call	TADDR
	ld	a,(hl)
	pop	hl
	ret
GETT0:	xor	a
	ret

; PLOT - set block (C, B) to type A, lit or unlit as the type requires, on the BG and the
;   screen.  Keeps BC.
PLOT:	push	hl
	push	de
	push	af
	ld	a,c
	cp	128
	jr	nc,PLOTX
	ld	a,b
	cp	48
	jr	nc,PLOTX
	call	TADDR
	pop	af
	ld	(hl),a
	push	af
	call	CELL		; HL = BG address, A = mask
	ld	e,a
	pop	af
	push	af
	call	ISLIT
	ld	a,e
	jr	z,PLOTOFF
	or	(hl)
	jr	PLOTSET
PLOTOFF:
	cpl
	and	(hl)
PLOTSET:
	ld	(hl),a
	ld	e,a
	ld	a,(NOVRAM)	; building a station behind the prepare screen?
	or	a
	jr	nz,PLOTX
	ld	a,e
	ld	de,VRAM-BG
	add	hl,de
	ld	(hl),a
PLOTX:	pop	af
	pop	de
	pop	hl
	ret

; ISLIT - Z clear if type A is drawn lit
ISLIT:	cp	T_EMPTY
	ret	z
	cp	T_GAP
	ret	z
	or	a		; non-zero: NZ
	ret

; PLOTIFEMPTY - plot type A at (C, B) only where the block is empty (ladders, slides)
PLOTIFEMPTY:
	push	af
	call	GETT
	or	a
	jr	nz,PIE1
	pop	af
	jp	PLOT
PIE1:	pop	af
	ret

; PRINT - text at the character position in HL (BG offset 0-1023), string at DE, ends with 0
PRINT:	push	hl
	ld	bc,BG
	add	hl,bc
PRINT1:	ld	a,(de)
	or	a
	jr	z,PRINT2
	ld	(hl),a
	push	hl
	push	de
	ld	de,VRAM-BG
	add	hl,de
	ld	(hl),a
	pop	de
	pop	hl
	inc	hl
	inc	de
	jr	PRINT1
PRINT2:	pop	hl
	ret

; PRBCD - print A as two digits at BG offset HL (advances HL by 2)
PRBCD:	push	af
	rrca
	rrca
	rrca
	rrca
	call	PRDIG
	pop	af
PRDIG:	and	$0F
	add	a,'0'
	push	hl
	push	de
	ld	de,BG
	add	hl,de
	ld	(hl),a
	ld	de,VRAM-BG
	add	hl,de
	ld	(hl),a
	pop	de
	pop	hl
	inc	hl
	ret

;=============================================================================
;  Sprites.  A sprite is drawn block by block straight into video memory; every
;  character it touches is recorded in DIRTY so that next frame RESTORE can put the
;  background back.  Sprites never touch BG or TYPEMAP.
;=============================================================================
; RESTORE - put back the characters the sprites covered (the list runs from DIRTY to DPTR)
RESTORE:
	ld	hl,DIRTY
REST1:	ld	a,(DPTR)	; each entry: the first of four characters a sprite row touched
	cp	l
	jr	nz,REST2
	ld	a,(DPTR+1)
	cp	h
	jr	z,REST3
REST2:	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	push	hl
	ld	hl,BG-VRAM
	add	hl,de
	ldi
	ldi
	ldi
	ldi
	pop	hl
	jr	REST1
REST3:	ld	hl,DIRTY
	ld	(DPTR),hl
	ret

; SPRITE - draw the picture at HL (one byte per row, bit 7 = leftmost block, at most 6
;   blocks wide), D rows high, with its top-left block at (C = x, B = y).  Rows outside the
;   mine (y < 3 or y > 47) are skipped; x must be 0-122.
;   Each row is handled a character at a time: the row's pattern is shifted to an even
;   block boundary, then taken two blocks (one character column) at a time, and the pair is
;   turned into the character's bit mask with CMASK.  Each character changed goes on the
;   DIRTY list.
SPRITE:
	ld	a,c		; the column of the first character, and whether x is odd
	srl	a
	ld	(SPCOL),a
	sbc	a,a
	ld	(SPODD),a	; $FF if odd
	ld	iy,(DPTR)
SP_ROW:	ld	a,b
	cp	3
	jr	c,SP_SKIP
	cp	48
	jr	nc,SP_SKIP
	ld	a,(hl)
	or	a
	jr	z,SP_SKIP
	push	hl
	push	de
	push	bc
	ld	d,a		; D = the row's pattern, shifted right one block if x is odd
	ld	a,(SPODD)
	or	a
	jr	z,SP1
	srl	d
SP1:	ld	h,YM4/256
	ld	l,b
	ld	e,(hl)		; E = CMASK offset for this row within the character
	inc	h
	ld	a,(SPCOL)
	add	a,(hl)		; YVL
	inc	h
	ld	h,(hl)		; YVH
	ld	l,a		; HL = the first character
	ld	(iy+0),l	; remember it (RESTORE puts back four characters from here)
	ld	(iy+1),h
	inc	iy
	inc	iy
	ld	b,CMASK/256
	ld	a,d		; four characters, two blocks each
	rlca
	rlca
	ld	d,a
	and	3
	or	e
	ld	c,a
	ld	a,(hl)		; a character (an item from the ROM) shows through the sprite
	and	$C0
	cp	$80
	jr	nz,SPX0
	ld	a,(bc)
	or	(hl)
	ld	(hl),a
SPX0:	inc	hl
	ld	a,d
	rlca
	rlca
	ld	d,a
	and	3
	or	e
	ld	c,a
	ld	a,(hl)		; a character (an item from the ROM) shows through the sprite
	and	$C0
	cp	$80
	jr	nz,SPX1
	ld	a,(bc)
	or	(hl)
	ld	(hl),a
SPX1:	inc	hl
	ld	a,d
	rlca
	rlca
	ld	d,a
	and	3
	or	e
	ld	c,a
	ld	a,(hl)		; a character (an item from the ROM) shows through the sprite
	and	$C0
	cp	$80
	jr	nz,SPX2
	ld	a,(bc)
	or	(hl)
	ld	(hl),a
SPX2:	inc	hl
	ld	a,d
	rlca
	rlca
	and	3
	or	e
	ld	c,a
	ld	a,(hl)
	and	$C0
	cp	$80
	jr	nz,SPX3
	ld	a,(bc)
	or	(hl)
	ld	(hl),a
SPX3:	pop	bc
	pop	de
	pop	hl
SP_SKIP:
	inc	hl
	inc	b
	dec	d
	jp	nz,SP_ROW
	ld	(DPTR),iy
	ret

;=============================================================================
;  RANDOM - A = pseudo-random byte (16-bit Galois LFSR)
;=============================================================================
RANDOM:	push	hl
	ld	hl,(SEED)
	srl	h
	rr	l
	jr	nc,RND1
	ld	a,h
	xor	$B4
	ld	h,a
RND1:	ld	(SEED),hl
	ld	a,r
	xor	l
	pop	hl
	ret

;=============================================================================
;  Sound: 1-bit tones through the cassette port (port $FF, bits 0-1).
;  BEEP - B = half period (loop count), C = number of cycles.  Blocks while it plays.
;=============================================================================
BEEP:	ld	a,(SOUNDON)
	or	a
	ret	z
BEEP1:	ld	a,1
	out	($FF),a
	push	bc
BEEP2:	djnz	BEEP2
	pop	bc
	ld	a,2
	out	($FF),a
	push	bc
BEEP3:	djnz	BEEP3
	pop	bc
	dec	c
	jr	nz,BEEP1
	ret

; SOUND - queue a tone (B = half period, C = cycles) for WAITTICK to play while it waits
;   for the next tick; a later sound replaces it.  Keeps BC, DE, HL.
SOUND:	ld	a,b
	ld	(SNDB),a
	ld	a,c
	ld	(SNDN),a
	ret

;=============================================================================
;  Keyboard.  KEYS returns the arrow/space row; bits: 3 up, 4 down, 5 left, 6 right,
;  7 space, 2 break.
;=============================================================================
KEYS:	ld	a,(KBROW6)
	ret

;  DIGIT - A = digit key held (1-9, 0 means 10) and NZ, or Z if none
DIGIT:	ld	a,(KBDIG0)
	ld	c,0
	or	a
	jr	nz,DIG1
	ld	a,(KBDIG8)
	and	3
	ret	z
	ld	c,8
DIG1:	rrca			; find the lowest set bit
	jr	c,DIG2
	inc	c
	jr	DIG1
DIG2:	ld	a,c
	or	a
	jr	nz,DIG3
	ld	a,10		; 0 = station 10
DIG3:	or	a
	ret

;=============================================================================
;  TITLE - title screen; waits for space.
;=============================================================================
TITLE:	call	CLS
	call	DRAWLOGO
	call	SHOWINV
	ld	hl,4*64+8
	ld	de,T_PORT
	call	PRINT
	ld	hl,5*64+9
	ld	de,T_ORIG
	call	PRINT
	ld	hl,9*64+8
	ld	de,T_KEYS
	call	PRINT
	ld	hl,10*64+8
	ld	de,T_KEYS2
	call	PRINT
	ld	hl,11*64+8
	ld	de,T_KEYS3
	call	PRINT
	ld	hl,12*64+8
	ld	de,T_KEYS4
	call	PRINT
	ld	hl,13*64+20
	ld	de,T_START
	call	PRINT
	ld	a,1
	ld	(STARTST),a
	xor	a
	ld	(IDLE),a
TIT1:	call	WAITTICK
	call	RANDOM
	call	DIGIT		; a digit picks the starting station (0 = 10)
	jr	z,TIT1A
	ld	(STARTST),a
	xor	a
	ld	(IDLE),a
	call	SHOWFROM
TIT1A:	ld	a,(KBROW1)	; I: the invincibility cheat, for testing
	and	$02
	ld	hl,IKEYOLD
	ld	c,(hl)
	ld	(hl),a
	jr	z,TIT1B
	cp	c
	jr	z,TIT1B
	ld	a,(INVULN)
	xor	1
	ld	(INVULN),a
	call	SHOWINV
TIT1B:	call	KEYS
	and	$80
	jr	nz,TIT2
	ld	hl,IDLE		; eight seconds with nothing pressed: the demonstration
	inc	(hl)
	ld	a,(hl)
	cp	250
	jr	nz,TIT1
	call	DEMO
	or	a
	jp	z,TITLE
TIT2:	call	KEYS		; wait for the key to be released
	and	$80
	jr	nz,TIT2
	ld	a,1
	ld	(SOUNDON),a
	ret
; DRAWLOGO - the big MINER 2049er in block letters, rows 4-10
DRAWLOGO:
	ld	hl,LOGO
	ld	b,4
DLG1:	ld	c,0
DLG2:	ld	d,(hl)
	inc	hl
	ld	e,8
DLG3:	sla	d
	jr	nc,DLG4
	ld	a,T_DECOR
	call	PLOT
DLG4:	inc	c
	dec	e
	jr	nz,DLG3
	ld	a,c
	cp	128
	jr	nz,DLG2
	inc	b
	ld	a,b
	cp	11
	jr	nz,DLG1
	ret
; DEATHFLASH - invincible Bob has just been killed: light the whole mine for two frames,
;   with a buzz.  Not again for a second, so a mutant he stands in does not strobe.
DEATHFLASH:
	ld	a,(FLASHCD)
	or	a
	ret	nz
	ld	a,30
	ld	(FLASHCD),a
	push	hl
	push	de
	push	bc
	ld	hl,VRAM+64	; every block lit, the status line left alone
	ld	de,VRAM+65
	ld	bc,1023-64
	ld	(hl),191
	ldir
	ld	bc,$3008
	call	BEEP
	ld	b,2
	call	WAITN
	call	SHOWBG
	ld	hl,DIRTY	; the sprites went with it
	ld	(DPTR),hl
	pop	bc
	pop	de
	pop	hl
	ret

; WHISTLES - the pick-up whistle, a few cycles a frame so a pick-up does not stop the
;   game (the Atari played it on a sound channel while the game ran on)
WHISTLES:
	ld	a,(WHISTLE)
	or	a
	ret	z
	ld	b,a
	add	a,4
	cp	$80
	jr	c,WH1
	xor	a
WH1:	ld	(WHISTLE),a
	ld	c,4
	jp	SOUND

; TESTKEYS - with the invincibility cheat on: U (held) shows only the land still to
;   claim, and how much; N goes straight to the next station
TESTKEYS:
	ld	a,(INVULN)
	or	a
	ret	z
	ld	a,(KBROW1)	; N
	and	$40
	jr	z,TK1
	ld	hl,0
	ld	(SECTIONS),hl
	ret
TK1:	ld	a,(KBROW2)	; U
	and	$20
	ret	z
SHOWLEFT:
	ld	hl,VRAM		; a blank screen ...
	ld	de,VRAM+1
	ld	bc,1023
	ld	(hl),128
	ldir
	ld	hl,(SECTIONS)	; ... "nnn SECTIONS LEFT TO CLAIM" on the status line ...
	ld	de,100
	call	DIGOUT
	ld	(VRAM+20),a
	ld	de,10
	call	DIGOUT
	ld	(VRAM+21),a
	ld	a,l
	add	a,'0'
	ld	(VRAM+22),a
	ld	hl,VRAM+24
	ld	de,T_LEFT
	call	PRINTV
	call	FLIPGAPS	; ... and only the unclaimed gaps, lit
SL1:	ld	a,(KBROW2)	; until U is let go
	and	$20
	jr	nz,SL1
	call	SHOWBG		; back to the station (the background copy holds it all)
	ld	hl,DIRTY	; nothing of the sprites is left to restore
	ld	(DPTR),hl
	ret
T_LEFT:	db	"SECTIONS LEFT TO CLAIM",0
; DIGOUT - A = '0' + HL / DE, HL = the remainder
DIGOUT:	ld	a,'0'-1
DO1:	inc	a
	or	a
	sbc	hl,de
	jr	nc,DO1
	add	hl,de
	ret
; FLIPGAPS - invert every unclaimed gap block on the screen
FLIPGAPS:
	ld	hl,TYPEMAP
	ld	bc,0		; B = y, C = x
FG1:	ld	a,(hl)
	cp	T_GAP
	jr	nz,FG2
	push	hl
	call	CELL		; HL = BG address, A = mask
	ld	de,VRAM-BG
	add	hl,de
	xor	(hl)
	ld	(hl),a
	pop	hl
FG2:	inc	hl
	inc	c
	bit	7,c
	jr	z,FG1
	ld	c,0
	inc	b
	ld	a,b
	cp	48
	jr	nz,FG1
	ret

; SHOWINV - the cheat's state on the title screen
SHOWINV:
	ld	hl,14*64+18
	ld	de,T_INVON
	ld	a,(INVULN)
	or	a
	jr	nz,SHI1
	ld	de,T_INVOFF
SHI1:	jp	PRINT
T_INVON: db	"INVINCIBLE: NOTHING KILLS YOU",0
T_INVOFF: db	"                             ",0
; SHOWCHEAT - a * at the end of the status line while the cheat is on
SHOWCHEAT:
	ld	a,(INVULN)
	or	a
	ret	z
	ld	hl,63
	ld	de,T_STAR
	jp	PRINT
T_STAR:	db	"*",0
SHOWFROM:
	ld	hl,15*64+22
	ld	de,T_FROM
	call	PRINT
	ld	hl,15*64+39
	ld	a,(STARTST)
	call	BINBCD
	jp	PRBCD

;-----------------------------------------------------------------------------
; DEMO - the attract mode: each station in turn for four seconds, its mutants, platforms,
;   lift arms and pulverizers going about their business.  Space (or a digit, which also
;   picks the starting station) ends it: A = 1.  After station 10, A = 0.
;-----------------------------------------------------------------------------
DEMO:	xor	a
	ld	(SOUNDON),a
	ld	a,1
	ld	(DEMOST),a
DEMO1:	ld	a,(DEMOST)
	ld	(STATION),a
	ld	a,1
	ld	(ZONE),a
	call	BUILD_STATION
	ld	hl,0		; the status line becomes the invitation
	ld	de,T_DEMO
	call	PRINT
	call	SHOWBG
	ld	hl,DIRTY
	ld	(DPTR),hl
	ld	b,120
DEMO2:	push	bc
	call	WAITTICK
	call	RESTORE
	call	MOVEPLAT
	call	MOVEPULV
	call	MOVEMUT
	call	DRAWMUT
	call	DRAWCAN
	call	DRAWARMS
	call	DRAWPULV
	call	DRAWBOB
	pop	bc
	call	DIGIT
	jr	z,DEMO3
	ld	(STARTST),a
	ld	a,1
	ret
DEMO3:	call	KEYS
	and	$80
	ld	a,1
	ret	nz
	djnz	DEMO2
	ld	a,(DEMOST)
	inc	a
	ld	(DEMOST),a
	cp	11
	jr	c,DEMO1
	xor	a
	ret

T_PORT:	db	"   THE 1982 ATARI GAME, FOR THE TRS-80 MODEL III   ",0
T_ORIG:	db	"     ORIGINAL GAME BY BILL HOGUE, BIG FIVE SOFTWARE",0
T_KEYS:	db	"ARROWS: WALK AND CLIMB         SPACE: JUMP",0
T_KEYS2: db	"1-4 IN A BOOTH: TRANSPORTER    BREAK: PAUSE",0
T_KEYS3: db	"ENTER ON THE LIFT: DRIVE IT    0-9 NOW: START STATION",0
T_KEYS4: db	"I NOW: INVINCIBLE (THEN U: LAND TO CLAIM, N: NEXT STATION)",0
T_DEMO:	db	"  DEMONSTRATION      SPACE TO PLAY      0-9 TO PICK A STATION   ",0
T_START: db	"PRESS SPACE TO START",0
T_FROM:	db	"START AT STATION",0

;=============================================================================
;  BUILD_STATION - draw the station and set up Bob, the mutants and the items.
;=============================================================================
BUILD_STATION:
	call	CLS
	call	PREPMSG		; "PREPARE FOR STATION n" while it is drawn
	ld	a,1
	ld	(NOVRAM),a
	call	STHEADER	; HL = station header
	ld	a,(hl)
	ld	(BOBSX),a
	inc	hl
	ld	a,(hl)
	ld	(BOBSFEET),a
	inc	hl
	ld	a,(hl)		; bonus base (hundreds) + 5 per zone, at most 99
	ld	b,a
	ld	a,(ZONE)
	ld	c,a
BS_B1:	ld	a,b
	add	a,5
	ld	b,a
	dec	c
	jr	nz,BS_B1
	ld	a,b
	cp	100
	jr	c,BS_B2
	ld	a,99
BS_B2:	call	BINBCD
	ld	(BONUS),a
	inc	hl
	ld	de,LISTS	; copy the six list pointers
	ld	bc,12
	ldir
	ld	(STNAME),hl
	; the bottom floor
	ld	b,47
	ld	c,0
BS_FL:	ld	a,T_FLOOR
	call	PLOT
	inc	c
	ld	a,c
	cp	128
	jr	nz,BS_FL
	; girders
	ld	hl,0
	ld	(SECTIONS),hl
	ld	hl,(LISTS)
BS_RUN:	ld	a,(hl)
	cp	$FF
	jr	z,BS_LAD
	ld	c,a		; x
	inc	hl
	ld	e,(hl)		; length
	inc	hl
	ld	b,(hl)		; row
	inc	hl
	push	hl
BS_R1:	ld	a,T_SURF
	call	PLOT
	inc	b		; the row below: lit on even x, a gap on odd x
	ld	a,T_DASH
	bit	0,c
	jr	z,BS_R2
	ld	a,T_GAP
	push	hl
	ld	hl,(SECTIONS)
	inc	hl
	ld	(SECTIONS),hl
	pop	hl
BS_R2:	call	PLOT
	dec	b
	inc	c
	dec	e
	jr	nz,BS_R1
	pop	hl
	jr	BS_RUN
	; ladders: rails at x and x+3, a rung every second row, from 2 rows above the top
	; surface down to the bottom surface, only on empty blocks
BS_LAD:	ld	hl,(LISTS+2)
BS_L0:	ld	a,(hl)
	cp	$FF
	jr	z,BS_SLI
	ld	c,a
	inc	hl
	ld	a,(hl)		; top
	sub	2
	ld	b,a
	inc	hl
	ld	d,(hl)		; bottom
	inc	hl
	push	hl
BS_L1:	ld	a,T_LADDER
	call	PLOTIFEMPTY
	inc	c
	inc	c
	inc	c
	call	PLOTIFEMPTY
	dec	c
	bit	0,b
	jr	nz,BS_L2
	call	PLOTIFEMPTY
	dec	c
	call	PLOTIFEMPTY
	inc	c
BS_L2:	dec	c
	dec	c
	inc	b
	ld	a,b
	cp	d
	jr	nz,BS_L1
	pop	hl
	jr	BS_L0
	; slides: a 3-block band from (x0, y0) to (x1, y1)
BS_SLI:	ld	hl,(LISTS+4)
BS_S0:	ld	a,(hl)
	cp	$FF
	jr	z,BS_ITEMS
	push	hl
	call	DRAWSLIDE
	pop	hl
	ld	de,4
	add	hl,de
	jr	BS_S0
	; items: copy each to ITEMTAB and draw it
BS_ITEMS:
	ld	hl,(LISTS+6)
	ld	ix,ITEMTAB
	xor	a
	ld	(NITEMS),a
BS_I0:	ld	a,(hl)
	cp	$FF
	jr	z,BS_MUT
	ld	(ix+0),a	; x
	inc	hl
	ld	a,(hl)
	ld	(ix+1),a	; y
	inc	hl
	ld	a,(hl)
	ld	(ix+2),a	; w
	inc	hl
	ld	a,(hl)
	ld	(ix+3),a	; h
	inc	hl
	ld	a,(hl)
	ld	(ix+4),a	; points / 100
	inc	hl
	ld	a,(hl)
	ld	(ix+5),a	; Atari shape number
	inc	hl
	ld	(ix+6),l	; picture
	ld	(ix+7),h
	ld	(ix+8),1	; present
	push	hl
	call	DRAWITEM
	pop	hl
	bit	7,(ix+5)	; a character item: skip its count and characters
	jr	z,BSI1
	ld	a,(hl)
	inc	a
	jr	BSI2
BSI1:	ld	a,(ix+3)	; a block picture: skip 2 bytes per row
	add	a,a
BSI2:	ld	e,a
	ld	d,0
	add	hl,de
	ld	de,9
	add	ix,de
	ld	a,(NITEMS)
	inc	a
	ld	(NITEMS),a
	jr	BS_I0
BS_MUT:	call	BS_SPEC
	call	COUNTGAPS	; overlapping scenery may have covered some gaps: count what is left
	call	INITMUT
	call	INITBOB
	call	STATUS
	call	SHOWCHEAT
	xor	a
	ld	(NOVRAM),a
	ret

; COUNTGAPS - SECTIONS = the number of unclaimed gaps in TYPEMAP
COUNTGAPS:
	ld	hl,TYPEMAP
	ld	de,0
	ld	bc,128*48
CG1:	ld	a,(hl)
	cp	T_GAP
	jr	nz,CG2
	inc	de
CG2:	inc	hl
	dec	bc
	ld	a,b
	or	c
	jr	nz,CG1
	ld	(SECTIONS),de
	ret

; DRAWSLIDE - HL -> x0, y0, x1, y1.  Draws 3 blocks per row from y0 to y1.
DRAWSLIDE:
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	inc	hl
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	; rows n = y1 - y0 ; x moves (x1 - x0) / n per row (stored as 8.8 fraction)
	ld	a,d
	sub	b
	jr	nz,DSL1
	inc	a
DSL1:	ld	(TMP1),a	; n
	ld	a,c
	ld	(TMP2),a	; x0
	ld	a,e
	sub	c
	ld	(TMP3),a	; dx (signed)
	xor	a
	ld	(TMP4),a	; k
DSL2:	; x = x0 + dx * k / n
	ld	a,(TMP3)
	ld	e,a
	ld	a,(TMP4)
	call	MULDIVS		; A = dx * k / n (signed)
	ld	hl,TMP2
	add	a,(hl)
	ld	c,a
	ld	a,T_LADDER
	call	PLOTIFEMPTY
	inc	c
	call	PLOTIFEMPTY
	inc	c
	call	PLOTIFEMPTY
	inc	b
	ld	a,(TMP4)
	inc	a
	ld	(TMP4),a
	ld	hl,TMP1
	cp	(hl)
	jr	c,DSL2
	jr	z,DSL2
	ret

; MULDIVS - A = (signed E) * A / (TMP1), A and TMP1 small and positive
MULDIVS:
	push	bc
	ld	c,a		; k
	ld	a,e
	bit	7,a
	push	af
	jr	z,MDS1
	neg
MDS1:	ld	h,0		; |dx| * k
	ld	l,0
	ld	d,0
	ld	e,a
	ld	b,c
	inc	b
	dec	b
	jr	z,MDS3
MDS2:	add	hl,de
	djnz	MDS2
MDS3:	ld	a,(TMP1)	; / n
	ld	c,a
	ld	b,0
	xor	a
MDS4:	or	a
	sbc	hl,bc
	jr	c,MDS5
	inc	a
	jr	MDS4
MDS5:	ld	c,a
	pop	af
	ld	a,c
	jr	z,MDS6
	neg
MDS6:	pop	bc
	ret

; DRAWITEM - draw item IX as type T_ITEM, or erase it (A = 0 in ITEMERASE)
DRAWITEM:
	ld	a,T_ITEM
	ld	(TMP5),a
DI0:	bit	7,(ix+5)	; drawn with characters from the ROM?
	jp	nz,GLYPHITEM
	ld	l,(ix+6)
	ld	h,(ix+7)
	ld	b,(ix+1)
	ld	a,(ix+3)
	ld	(TMP7),a	; rows to go
DI1:	ld	c,(ix+0)
	ld	e,0		; block index in the row
	ld	d,(hl)
	inc	hl
	ld	a,(hl)
	inc	hl
	ld	(TMP6),a
	push	hl
DI2:	ld	a,e
	cp	8		; after 8 blocks, the row's second byte
	jr	nz,DI2A
	ld	a,(TMP6)
	ld	d,a
DI2A:	sla	d
	jr	nc,DI3
	ld	a,(TMP5)
	call	PLOT
DI3:	inc	c
	inc	e
	ld	a,e
	cp	(ix+2)
	jr	c,DI2
	pop	hl
	inc	b
	ld	a,(TMP7)
	dec	a
	ld	(TMP7),a
	jr	nz,DI1
	ret
ITEMERASE:
	xor	a
	ld	(TMP5),a
	jr	DI0

; GLYPHITEM - an item drawn with characters: its cell (x/2, y/3) gets the characters
;   (or blank graphics when erased), and its blocks are marked T_ITEM (or emptied) in
;   TYPEMAP for the pick-up test.  The picture pointer points at the count, then codes.
GLYPHITEM:
	ld	b,(ix+1)	; TYPEMAP: w x 3 blocks
	ld	e,3
GI1:	ld	c,(ix+0)
	ld	d,(ix+2)
GI2:	call	TADDR
	ld	a,(TMP5)
	ld	(hl),a
	inc	c
	dec	d
	jr	nz,GI2
	inc	b
	dec	e
	jr	nz,GI1
	ld	a,(ix+1)	; BG address of the cell: YVL/YVH give the VRAM row, + $6000
	ld	l,a
	ld	h,YVL/256
	ld	a,(ix+0)
	srl	a
	add	a,(hl)
	inc	h
	ld	h,(hl)
	ld	l,a
	ld	a,h
	add	a,(BG-VRAM)/256
	ld	h,a
	ld	e,(ix+6)
	ld	d,(ix+7)
	ld	a,(de)		; how many characters
	ld	b,a
GI3:	inc	de
	ld	a,(TMP5)
	or	a
	ld	a,128		; erased: blank graphics
	jr	z,GI4
	ld	a,(de)
GI4:	ld	(hl),a
	ld	c,a
	ld	a,(NOVRAM)
	or	a
	jr	nz,GI5
	push	hl
	push	de
	ld	de,VRAM-BG
	add	hl,de
	ld	(hl),c
	pop	de
	pop	hl
GI5:	inc	hl
	djnz	GI3
	ret

; BINBCD - A (0-99) -> packed BCD in A
BINBCD:	push	bc
	ld	b,0
BB1:	cp	10
	jr	c,BB2
	sub	10
	inc	b
	jr	BB1
BB2:	ld	c,a
	ld	a,b
	rlca
	rlca
	rlca
	rlca
	or	c
	pop	bc
	ret

;=============================================================================
;  STATUS - the status line (text row 0)
;    SCORE 000000   BONUS 3000   MINER 3   STATION 1  ZONE 1
;=============================================================================
STATUS:	ld	hl,0
	ld	de,T_STATUS
	call	PRINT
	call	SHOWSCORE
	call	SHOWBONUS
	ld	hl,32
	ld	a,(LIVES)
	call	PRDIG
	ld	hl,43
	ld	a,(STATION)
	call	BINBCD
	call	PRBCD
	ld	hl,52
	ld	a,(ZONE)
	call	BINBCD
	call	PRBCD
	ret
T_STATUS: db	"SCORE 000000  BONUS 0000  MINER 0  STATION 00  ZONE 00",0
SHOWSCORE:
	ld	hl,6
	ld	a,(SCORE)
	call	PRBCD
	ld	a,(SCORE+1)
	call	PRBCD
	ld	a,(SCORE+2)
	jp	PRBCD
SHOWBONUS:
	ld	hl,20
	ld	a,(BONUS)
	call	PRBCD
	ld	a,0
	jp	PRBCD

; ADDSCORE - add the packed-BCD value in A to the score at the position given by
;   C: 2 = units/tens, 1 = hundreds/thousands, 0 = ten-thousands/hundred-thousands
ADDSCORE:
	ld	hl,SCORE+2
	ld	b,0
	push	af
	ld	a,2
	sub	c
	ld	c,a
	or	a
	sbc	hl,bc
	pop	af
	add	a,(hl)
	daa
	ld	(hl),a
AS1:	jr	nc,AS2
	ld	a,l
	cp	SCORE & $FF
	jr	z,AS2
	dec	hl
	ld	a,(hl)
	add	a,1
	daa
	ld	(hl),a
	jr	AS1
AS2:	; extra life at 10,000
	ld	a,(XLIFE)
	or	a
	jr	z,AS3
	ld	a,(SCORE)	; ten-thousands digit reached?
	or	a
	jr	z,AS3
	xor	a
	ld	(XLIFE),a
	ld	hl,LIVES
	inc	(hl)
	ld	hl,32
	ld	a,(LIVES)
	call	PRDIG
	ld	bc,$1020
	call	SOUND
AS3:	jp	SHOWSCORE

;=============================================================================
;  PREPARE - "PREPARE FOR STATION n" for two seconds, then show the station
;=============================================================================
; STHEADER - HL = this station's header (STATIONS table)
STHEADER:
	ld	a,(STATION)
	dec	a
	add	a,a
	ld	l,a
	ld	h,0
	ld	de,STATIONS
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ex	de,hl
	ret
PREPMSG:
	call	STHEADER	; the name follows the 3 bytes and 6 pointers
	ld	de,15
	add	hl,de
	ld	(STNAME),hl
	ld	hl,VRAM+7*64	; a message box over the middle of the screen
	ld	b,192
PRE0:	ld	(hl),128
	inc	hl
	djnz	PRE0
	ld	hl,VRAM+7*64+20
	ld	de,T_PREP
	call	PRINTV
	ld	hl,VRAM+8*64+20
	ld	de,T_STAT
	call	PRINTV
	ld	a,(STATION)
	call	BINBCD
	call	PRBCDV
	ld	hl,VRAM+9*64+32
	ld	de,(STNAME)
	ld	a,(de)		; centre the name
	push	hl
	ld	hl,(STNAME)
	ld	c,0
PRE1:	ld	a,(hl)
	or	a
	jr	z,PRE2
	inc	c
	inc	hl
	jr	PRE1
PRE2:	pop	hl
	srl	c
	ld	b,0
	or	a
	sbc	hl,bc
	call	PRINTV
	ret
PREPARE:
	ld	b,45
PRE3:	push	bc
	call	WAITTICK
	pop	bc
	djnz	PRE3
	jp	SHOWBG
T_PREP:	db	"PREPARE FOR",0
T_STAT:	db	"STATION ",0
; PRINTV - print DE at VRAM address HL (screen only), HL advances
PRINTV:	ld	a,(de)
	or	a
	ret	z
	ld	(hl),a
	inc	hl
	inc	de
	jr	PRINTV
PRBCDV:	push	af
	rrca
	rrca
	rrca
	rrca
	and	$0F
	add	a,'0'
	ld	(hl),a
	inc	hl
	pop	af
	and	$0F
	add	a,'0'
	ld	(hl),a
	inc	hl
	ret

;=============================================================================
;  PLAY - run the station until Bob dies (A = 0) or every section is claimed (A = 1)
;=============================================================================
PLAY:	xor	a
	ld	(BONUSTMR),a
	ld	(WHISTLE),a
	ld	hl,DIRTY
	ld	(DPTR),hl
PLAYLOOP:
	call	WAITTICK
	call	RESTORE
	call	KEYS
	ld	(KEYNOW),a
	and	$04		; BREAK pauses
	call	nz,PAUSE
	call	TESTKEYS	; with the cheat on: U shows the land to claim, N skips
	call	MOVEBOB
	call	MOVEPLAT
	call	MOVELIFT
	call	MOVEPULV
	call	MOVECAN
	call	HAZCHECK
	call	MOVEMUT
	call	ITEMS
	call	HITMUT
	call	TIMER
	call	WHISTLES
	call	DRAWMUT
	call	DRAWCAN
	call	DRAWARMS
	call	DRAWPULV
	call	DRAWBOB
	ld	a,(KEYNOW)
	ld	(KEYOLD),a
	ld	a,(BOBSTATE)
	cp	S_DYING
	jr	nz,PL1
	ld	a,(DYTMR)
	or	a
	jr	nz,PLAYLOOP
	xor	a		; died
	ret
PL1:	ld	hl,(SECTIONS)
	ld	a,h
	or	l
	jr	nz,PLAYLOOP
	call	DRAWBOB
	ld	a,1		; station cleared
	ret

PAUSE:	call	KEYS		; wait for BREAK to be released, pressed and released again
	and	$04
	jr	nz,PAUSE
PAU1:	call	KEYS
	and	$04
	jr	z,PAU1
PAU2:	call	KEYS
	and	$04
	jr	nz,PAU2
	ret

;=============================================================================
;  TIMER - the bonus drops by 100 every 3 seconds (90 frames); at zero Bob dies
;=============================================================================
TIMER:	ld	a,(BOBSTATE)
	cp	S_DYING
	ret	z
	ld	hl,BONUSTMR
	inc	(hl)
	ld	a,(hl)
	cp	90
	ret	c
	ld	(hl),0
	ld	a,(BONUS)
	or	a
	ret	z
	sub	1
	daa
	ld	(BONUS),a
	push	af
	call	SHOWBONUS
	pop	af
	or	a
	ret	nz
	jp	KILLBOB

;=============================================================================
;  Bob
;=============================================================================
INITBOB:
	ld	a,$FF
	ld	(LASTCX),a
	ld	a,(BOBSX)
	ld	(BOBX),a
	ld	a,(BOBSFEET)
	sub	BOBH
	ld	(BOBY),a
	xor	a
	ld	(BOBSTATE),a
	ld	(BOBDIR),a
	ld	(BOBFRAC),a
	ld	(BOBANIM),a
	ld	(DYTMR),a
	ld	a,$FF
	ld	(KEYOLD),a	; a held space does not jump at once
	ret

; SOLID - Z set if block (C, B) is something to stand on (surface or floor)
SOLID:	call	GETT
	cp	T_SURF
	ret	z
	cp	T_PLAT
	ret	z
	cp	T_FLOOR
	ret

; FEETSOLID - Z set if there is a surface under either of Bob's middle feet blocks at row B
FEETSOLID:
	ld	a,(BOBX)
	add	a,2
	ld	c,a
	call	SOLID
	ret	z
	inc	c
	jp	SOLID

MOVEBOB:
	ld	a,(BOBSTATE)
	cp	S_GROUND
	jp	z,BOBGROUND
	cp	S_JUMP
	jp	z,BOBJUMP
	cp	S_FALL
	jp	z,BOBFALL
	cp	S_LADDER
	jp	z,BOBLADDER
	cp	S_SLIDE
	jp	z,BOBSLIDE
	cp	S_TRANS
	jp	z,BOBTRANS
	cp	S_CANNON
	jp	z,BOBCANNON
	cp	S_FLY
	jp	z,BOBFLY
	jp	BOBDYING

; ---- on a girder -------------------------------------------------------------
BOBGROUND:
	ld	a,(KEYOLD)	; fresh presses: bits set now and not last frame
	cpl
	ld	hl,KEYNOW
	and	(hl)
	ld	d,a
	ld	e,(hl)
	bit	0,d		; ENTER on the lift takes or gives up its controls (the Atari's
	jr	z,BG_SP		;   SPACE; its fire button jumps, as our SPACE does)
	call	LIFTSPACE
	or	a
	ret	nz
BG_SP:	ld	a,(LIFTDRV)	; driving the lift: the arrows are the lift's; SPACE lets go
	or	a
	jr	z,BG_JUMP
	bit	7,d
	jp	z,CLAIM
	xor	a
	ld	(LIFTDRV),a
	jp	CLAIM
BG_JUMP:
	bit	7,d		; space: jump on a fresh press
	jp	nz,STARTJUMP
BG_UP:	bit	3,e
	jr	z,BG_DN
	call	TRYLADDERUP
	ret	c
BG_DN:	bit	4,e
	jr	z,BG_LR
	call	TRYLADDERDN
	ret	c
BG_LR:	bit	5,e
	jr	nz,BG_LEFT
	bit	6,e
	jr	nz,BG_RIGHT
	xor	a		; standing still
	ld	(BOBANIM),a
	call	TRYTRANS	; in a transporter booth with a digit held?
	or	a
	ret	nz
	call	FOLLOW		; a platform may have gone from under him
	ret	c
	jp	CLAIM
BG_LEFT:
	ld	a,1
	ld	(BOBDIR),a
	call	STEP		; carry = a whole block this frame
	jp	nc,CLAIM
	ld	a,(BOBX)
	or	a
	jp	z,CLAIM
	dec	a
	call	WALLOK		; a wall (or the waste) in the way?
	jp	c,CLAIM
	ld	(BOBX),a
	jr	BG_MOVED
BG_RIGHT:
	xor	a
	ld	(BOBDIR),a
	call	STEP
	jp	nc,CLAIM
	ld	a,(BOBX)
	cp	128-BOBW
	jp	nc,CLAIM
	inc	a
	call	WALLOK
	jp	c,CLAIM
	ld	(BOBX),a
BG_MOVED:
	ld	hl,BOBANIM
	inc	(hl)
	call	FOLLOW		; up or down a step, or off the edge
	ret	c		; started to fall
	call	CLAIM		; claim before a slide can carry him off
	call	SLIDECHECK
	ret	c
	call	STEPSOUND
	jp	CLAIM

; STEP - walking speed: 0.8 blocks per frame (24 blocks a second, as the Atari's
;   30 pixels a second scaled to 128 blocks).  Carry = move one block now.
STEP:	ld	a,(BOBFRAC)
	add	a,205
	ld	(BOBFRAC),a
	ret

; FOLLOW - after a step: girder one row higher -> step up; level -> fine; one row lower ->
;   step down; nothing -> start falling (carry set).
FOLLOW:	ld	a,(BOBY)	; on the bottom floor, a girder two rows up can be stepped onto
	cp	47-BOBH		;   (the Atari's ramps leave the floor a few lines at a time, finer
	jr	nz,FO0A		;   than our rows); anywhere else only one row, so a ramp's end
	add	a,BOBH-2	;   above a girder does not catch Bob as he walks underneath
	ld	b,a
	call	FEETSOLID
	jr	nz,FO0
	ld	hl,BOBY
	dec	(hl)
	dec	(hl)
	or	a
	ret
FO0A:	add	a,BOBH-2
	ld	b,a
FO0:	inc	b		; row of the feet
	call	FEETSOLID
	jr	nz,FO1
	ld	hl,BOBY		; girder at feet level: it rises
	dec	(hl)
	or	a
	ret
FO1:	inc	b
	call	FEETSOLID
	ret	z		; on level ground (carry clear after CP equal)
	inc	b
	call	FEETSOLID
	jr	nz,FO2
	ld	hl,BOBY		; girder fell by one row
	inc	(hl)
	or	a
	ret
FO2:	ld	a,S_FALL
	ld	(BOBSTATE),a
	xor	a
	ld	(FALLROWS),a
	ld	(JIDX),a
	scf
	ret

; CLAIM - the heart of the game: under each of Bob's two middle feet blocks, if the row
;   below the surface has a gap, fill it.  The screen is the only record of what is claimed.
CLAIM:	ld	a,(BOBX)	; nothing new to claim where he claimed last time
	ld	hl,LASTCX
	cp	(hl)
	jr	nz,CLM1
	ld	a,(BOBY)
	inc	hl
	cp	(hl)
	ret	z
CLM1:	ld	a,(BOBX)
	ld	(LASTCX),a
	ld	a,(BOBY)
	ld	(LASTCY),a
	add	a,BOBH
	ld	b,a		; surface row under the feet
	ld	a,(BOBX)	; his whole width, so the sections at the screen edges and next
	ld	c,a		;   to a slide's top can be reached too
	call	CLAIMAT
	inc	c
	call	CLAIMAT
	inc	c
	call	CLAIMAT
	inc	c
	call	CLAIMAT
	inc	c
	call	CLAIMAT
	inc	c
; CLAIMWIDE - claim two blocks beyond Bob on each side as well (slide tops and feet,
;   where the slide would otherwise leave a section or two out of reach)
CLAIMWIDE:
	push	hl
	ld	a,(BOBY)
	add	a,BOBH
	ld	b,a
	ld	a,(BOBX)
	sub	2
	ld	c,a
	ld	e,10
CW1:	push	de
	call	CLAIMAT
	pop	de
	inc	c
	dec	e
	jr	nz,CW1
	pop	hl
	ret
CLAIMAT:
	call	GETT
	cp	T_SURF
	ret	nz
	inc	b		; the lower row of this two-block section
	push	bc
	set	0,c		; the gap is the odd block of the pair
	call	GETT
	cp	T_GAP
	jr	nz,CA1
	ld	a,T_DASH	; fill it: the section is claimed
	call	PLOT
	ld	hl,(SECTIONS)
	dec	hl
	ld	(SECTIONS),hl
	ld	a,$05		; 5 points
	ld	c,2
	call	ADDSCORE
	ld	bc,$0806
	call	SOUND
CA1:	pop	bc
	dec	b
	ret

STEPSOUND:
	ld	a,(BOBANIM)
	and	3
	ret	nz
	ld	bc,$3003
	jp	SOUND

; ---- ladders -------------------------------------------------------------------
; TRYLADDERUP - a ladder whose bottom is at Bob's feet and whose rails are within 2
;   blocks of his middle: snap onto it and climb.  Carry set if he did.
TRYLADDERUP:
	ld	hl,(LISTS+2)
TLU0:	ld	a,(hl)
	cp	$FF
	jr	z,TLNO
	push	hl
	call	LADX		; Z set if Bob is lined up with ladder (HL)
	pop	hl
	jr	nz,TLU1
	inc	hl
	inc	hl
	ld	a,(BOBY)	; feet within a row of the bottom
	add	a,BOBH
	sub	(hl)
	inc	a
	cp	3
	ld	a,(hl)
	dec	hl
	dec	hl
	jr	c,TLGO
TLU1:	inc	hl
	inc	hl
	inc	hl
	jr	TLU0
TLNO:	or	a
	ret
TLGO:	sub	BOBH		; feet exactly on the end he got on at
	ld	(BOBY),a
	ld	a,(hl)		; Bob's x = rail - 1
	dec	a
	ld	(BOBX),a
	inc	hl
	ld	a,(hl)
	ld	(LADTOP),a
	inc	hl
	ld	a,(hl)
	ld	(LADBOT),a
	ld	a,S_LADDER
	ld	(BOBSTATE),a
	scf
	ret
TRYLADDERDN:
	ld	hl,(LISTS+2)
TLD0:	ld	a,(hl)
	cp	$FF
	jr	z,TLNO
	push	hl
	call	LADX
	pop	hl
	jr	nz,TLD1
	inc	hl
	ld	a,(BOBY)	; feet within a row of the top
	add	a,BOBH
	sub	(hl)
	inc	a
	cp	3
	ld	a,(hl)
	dec	hl
	jr	c,TLGO
TLD1:	inc	hl
	inc	hl
	inc	hl
	jr	TLD0
; LADX - Z set if |(rail x - 1) - BOBX| <= 2
LADX:	ld	a,(hl)
	dec	a
	ld	hl,BOBX
	sub	(hl)
	add	a,2
	cp	5
	jr	nc,LADX1
	xor	a
	ret
LADX1:	or	1
	ret

BOBLADDER:
	ld	a,(KEYNOW)
	ld	e,a
	ld	a,(FRAMES)
	and	3		; one row every 4 frames
	ret	nz
	bit	3,e
	jr	nz,BL_UP
	bit	4,e
	ret	z
	ld	a,(BOBY)	; down
	add	a,BOBH
	ld	hl,LADBOT
	cp	(hl)
	jr	z,BL_OFF
	ld	hl,BOBY
	inc	(hl)
	jr	BL_ANIM
BL_UP:	ld	a,(BOBY)
	add	a,BOBH
	ld	hl,LADTOP
	cp	(hl)
	jr	z,BL_OFF
	ld	hl,BOBY
	dec	(hl)
BL_ANIM:
	ld	hl,BOBANIM
	inc	(hl)
	ld	bc,$1802
	jp	SOUND
BL_OFF:	xor	a		; at an end: back on the girder
	ld	(BOBSTATE),a
	ld	(BOBANIM),a
	ret

; ---- jumping and falling ----------------------------------------------------------
; The jump: 4 rows up with pauses, as the Atari's 16 lines scaled by 4, then down.
; JUMPARC - rows per frame (-1 up, +1 down), from the Atari's JUMP_ARC: its 32 entries are
;   lines per 60 Hz frame; summed in pairs and scaled (44/183 rows per line) they give these
;   heights above the take-off: 0 1 1 2 2 3 3 3 3 4 4 4 3 3 3 3.  After the table Bob drops a
;   row every second frame, as the Atari drops a line a frame.
JUMPARC: db	0,-1,0,-1,0,-1,0,0,0,-1,0,0,1,0,0,0
JUMPLEN	equ	16
STARTJUMP:
	ld	a,S_JUMP
	ld	(BOBSTATE),a
	xor	a
	ld	(JIDX),a
	ld	(FALLROWS),a
	ld	a,(KEYNOW)	; direction from the arrows
	ld	c,0
	bit	5,a
	jr	z,SJ1
	ld	c,-1
	ld	a,1
	ld	(BOBDIR),a
SJ1:	ld	a,(KEYNOW)
	bit	6,a
	jr	z,SJ2
	ld	c,1
	xor	a
	ld	(BOBDIR),a
SJ2:	ld	a,c
	ld	(JDX),a
	ld	bc,$2008	; (short: a beep blocks the frame)
	jp	SOUND

BOBJUMP:
	ld	a,(JDX)		; sideways at walking speed
	or	a
	jr	z,BJ2
	call	STEP
	jr	nc,BJ2
	ld	a,(JDX)
	ld	hl,BOBX
	add	a,(hl)
	cp	128-BOBW+1
	jr	nc,BJ2		; the screen edge stops him
	call	WALLOK		; so do walls
	jr	c,BJ2
	ld	(hl),a
BJ2:	ld	a,(JIDX)
	cp	JUMPLEN
	jr	nc,BJ_FALL
	inc	a
	ld	(JIDX),a
	dec	a
	ld	e,a
	ld	d,0
	ld	hl,JUMPARC
	add	hl,de
	ld	a,(hl)
	or	a
	ret	z
	bit	7,a
	jr	z,BJ_DOWN
	ld	hl,BOBY		; up (not above the top of the screen: on the top girder his head
	ld	a,(hl)		;   is already in the status line, where he is not drawn)
	or	a
	ret	z
	dec	(hl)
	ret
BJ_DOWN:
	jp	DESCEND
BJ_FALL:
	jr	nz,BF1		; (JIDX > JUMPLEN)
	xor	a		; the end of the arc: the fall counts from here, as the Atari's
	ld	(FALLROWS),a	;   FALL_LEN does
	jr	BF1

BOBFALL:
	ld	a,(JDX)		; a fall drifts no further sideways
BF1:	ld	hl,JIDX		; fall: one row every second frame
	inc	(hl)
	ld	a,(hl)
	and	1
	ret	nz
; DESCEND - move Bob down one row unless he lands
DESCEND:
	ld	a,(BOBY)
	add	a,BOBH
	ld	b,a
	call	FEETSOLID
	jr	z,LAND
	ld	hl,BOBY
	inc	(hl)
	ld	hl,FALLROWS
	inc	(hl)
	ld	a,(BOBY)
	cp	48-BOBH
	ret	c
	jp	KILLBOB		; fell off the bottom
LAND:	ld	a,(FALLROWS)
	cp	10		; ten rows or more: fatal (the Atari's 40 lines of falling)
	jr	c,LAND1
	ld	a,(INVULN)	;   (unless the cheat is on: then he just lands)
	or	a
	jp	z,KILLBOB
LAND1:
	xor	a
	ld	(BOBSTATE),a
	ld	(JDX),a
	ld	bc,$4004
	call	SOUND
	jp	CLAIM

; ---- slides -----------------------------------------------------------------
; SLIDECHECK - Bob's feet at the top of a slide: ride it.  Carry set if he did.
SLIDECHECK:
	ld	hl,(LISTS+4)
SC0:	ld	a,(hl)
	cp	$FF
	jr	z,SCNO
	ld	a,(BOBX)	; exactly at the top, as the Atari (BOB_X = the slide's x)
	cp	(hl)
	jr	nz,SC1
	inc	hl
	ld	a,(BOBY)
	add	a,BOBH
	cp	(hl)
	dec	hl
	jr	z,SCGO
SC1:	inc	hl
	inc	hl
	inc	hl
	inc	hl
	jr	SC0
SCNO:	or	a
	ret
SCGO:	ld	(SLIDEP),hl
	call	CLAIMWIDE	; the girder round a slide's top is claimed as he goes
	xor	a
	ld	(JIDX),a
	ld	a,S_SLIDE
	ld	(BOBSTATE),a
	scf
	ret
BOBSLIDE:
	ld	hl,(SLIDEP)
	ld	c,(hl)		; x0
	inc	hl
	ld	b,(hl)		; y0
	inc	hl
	ld	e,(hl)		; x1
	inc	hl
	ld	d,(hl)		; y1
	ld	a,d
	sub	b
	jr	nz,BSL1
	inc	a
BSL1:	ld	(TMP1),a	; rows
	ld	a,e
	sub	c
	ld	e,a		; dx
	ld	hl,JIDX
	inc	(hl)
	ld	a,(hl)
	srl	a		; one row every second frame
	ld	hl,TMP1
	cp	(hl)
	jr	nc,BSL_END
	push	af
	push	bc
	call	MULDIVS		; A = dx * k / rows
	pop	bc
	add	a,c		; Bob's x follows the slide's x, as the Atari's BOB_X does
	cp	128-BOBW+1
	jr	c,BSL2
	ld	a,128-BOBW
BSL2:	ld	(BOBX),a
	pop	af
	add	a,b
	sub	BOBH
	ld	(BOBY),a
	ld	a,(FRAMES)
	and	1
	ret	nz
	ld	a,(JIDX)
	add	a,$20
	ld	b,a
	ld	c,2
	jp	SOUND
BSL_END:
	ld	hl,(SLIDEP)	; finish exactly at the slide's foot
	inc	hl
	inc	hl
	ld	a,(hl)		; x1
	cp	128-BOBW+1
	jr	c,BSE1
	ld	a,128-BOBW
BSE1:	ld	(BOBX),a
	inc	hl
	ld	a,(hl)		; y1
	sub	BOBH
	ld	(BOBY),a
	xor	a
	ld	(BOBSTATE),a
	call	CLAIMWIDE	; the girder round a slide's foot too, and a landing between two
				;   slides in passing
	call	SLIDECHECK	; the top of another slide: carry on down it (as the Atari checks
	ret	c		;   for a slide before it checks his footing)
	call	FOLLOW
	ret

; ---- dying ---------------------------------------------------------------------
KILLBOB:
	ld	a,(INVULN)	; the testing cheat: nothing kills him, but the screen flashes
	or	a		;   once to show he would have died
	jp	nz,DEATHFLASH
	ld	a,(BOBSTATE)
	cp	S_DYING
	ret	z
	ld	a,S_DYING
	ld	(BOBSTATE),a
	ld	a,45
	ld	(DYTMR),a
	ld	hl,MELTBUF	; Bob's picture into the melt buffer
	ld	de,BOB_STAND_R
	ex	de,hl
	ld	bc,6
	ldir
	ret
; BOBDYING - the melt: each frame a random row enters at his feet and the picture shifts
;   down one row, from the top of what is left (after MELT_BOB in the Atari code)
BOBDYING:
	ld	hl,DYTMR
	dec	(hl)
	ld	a,(hl)
	and	1
	ret	nz
	ld	a,(hl)
	cp	30
	ret	c		; melted: a puddle stays for a second
	ld	hl,MELTBUF+4	; shift rows down: 5 <- 4 <- ... <- top
	ld	de,MELTBUF+5
	ld	bc,5
	lddr
	xor	a
	ld	(MELTBUF),a
	call	RANDOM
	and	$FC
	ld	hl,MELTBUF+5
	or	(hl)
	ld	(hl),a
	ld	a,(DYTMR)
	add	a,$40
	ld	b,a
	ld	c,3
	jp	SOUND

; DRAWBOB - pick Bob's picture for his state and draw him
DRAWBOB:
	ld	a,(BOBSTATE)
	cp	S_TRANS
	jr	z,DB0
	cp	S_DYING
	jr	nz,DB1
DB0:
	ld	hl,MELTBUF
	jr	DBGO
DB1:	cp	S_CANNON
	jr	nz,DB1A
	ld	hl,BOB_STAND_R	; in the cannon: only his top three rows show
	ld	a,(BOBX)
	ld	c,a
	ld	a,(BOBY)
	ld	b,a
	ld	d,3
	jp	SPRITE
DB1A:	cp	S_LADDER
	jr	nz,DB2
	ld	hl,BOB_CLIMB1
	ld	a,(BOBANIM)
	and	1
	jr	z,DBGO
	ld	hl,BOB_CLIMB2
	jr	DBGO
DB2:	cp	S_GROUND
	jr	z,DB3
	ld	hl,BOB_JUMP_R
	ld	a,(BOBDIR)
	or	a
	jr	z,DBGO
	ld	hl,BOB_JUMP_L
	jr	DBGO
DB3:	ld	a,(BOBANIM)	; walking: frames 1-3, 2, ... ; standing: frame 0
	or	a
	ld	e,0
	jr	z,DB4
	rrca
	rrca
	and	3
	ld	e,a
	cp	3		; 0,1,2,3 -> 1,2,3,2
	jr	nz,DB3A
	ld	e,1
DB3A:	inc	e
DB4:	ld	a,(BOBDIR)
	add	a,a
	add	a,a
	add	a,e
	ld	l,a		; frame * 6
	add	a,a
	add	a,l
	add	a,a
	ld	e,a
	ld	d,0
	ld	hl,BOB_STAND_R
	add	hl,de
DBGO:	ld	a,(BOBX)
	ld	c,a
	ld	a,(BOBY)
	ld	b,a
	ld	d,BOBH
	jp	SPRITE

;=============================================================================
;  Mutants.  MUTTAB: 8 records of 10 bytes:
;    +0 x  +1 feet row  +2 min x  +3 max x  +4 dir (1 / $FF)  +5 speed (1/128 blocks per frame)
;    +6 fraction  +7 state (0 none, 1 walking, 2 eaten)  +8 timer  +9 animation
;=============================================================================
MUTLEN	equ	10
INITMUT:
	ld	ix,MUTTAB
	ld	b,8
IM0:	ld	(ix+7),0
	ld	de,MUTLEN
	add	ix,de
	djnz	IM0
	ld	hl,(LISTS+8)
	ld	ix,MUTTAB
IM1:	ld	a,(hl)
	cp	$FF
	ret	z
	ld	(ix+0),a
	inc	hl
	ld	a,(hl)
	ld	(ix+1),a
	inc	hl
	ld	a,(hl)
	ld	(ix+2),a
	inc	hl
	ld	a,(hl)
	ld	(ix+3),a
	inc	hl
	ld	a,(hl)
	ld	(ix+4),a
	inc	hl
	ld	a,(hl)		; Atari: one pixel every d frames at 60 Hz, d = delay + 1 - zone
	inc	a
	push	hl
	ld	hl,ZONE
	sub	(hl)
	jr	z,IM2
	jr	nc,IM3
IM2:	ld	a,1
IM3:	ld	e,a		; speed = 205 / d  (0.8 x 2 x 128 / d)
	ld	d,0
	ld	hl,205
	ld	b,0
IM4:	or	a
	sbc	hl,de
	jr	c,IM5
	inc	b
	jr	IM4
IM5:	ld	(ix+5),b
	pop	hl
	inc	hl
	ld	(ix+6),0
	ld	(ix+7),1
	ld	(ix+8),0
	ld	(ix+9),0
	ld	de,MUTLEN
	add	ix,de
	jr	IM1

MOVEMUT:
	ld	ix,MUTTAB
	ld	b,8
MM0:	push	bc
	ld	a,(ix+7)
	cp	1
	jr	z,MM1
	cp	2
	jr	nz,MMNEXT
	dec	(ix+8)		; eaten: gone when its timer runs out
	jr	nz,MMNEXT
	ld	(ix+7),0
	jr	MMNEXT
MM1:	ld	a,(ix+6)	; walking: fraction += speed; a block per 128
	add	a,(ix+5)
	ld	(ix+6),a
MM2:	ld	a,(ix+6)
	cp	128
	jr	c,MMNEXT
	sub	128
	ld	(ix+6),a
	inc	(ix+9)
	ld	a,(ix+0)
	add	a,(ix+4)
	ld	(ix+0),a
	cp	(ix+2)		; at an end of the patrol: turn round
	jr	z,MMTURN
	cp	(ix+3)
	jr	nz,MM2
MMTURN:	ld	a,(ix+4)
	neg
	ld	(ix+4),a
	jr	MM2
MMNEXT:	ld	de,MUTLEN
	add	ix,de
	pop	bc
	djnz	MM0
	; the edible countdown
	ld	a,(EDIBLE)
	or	a
	ret	z
	dec	a
	ld	(EDIBLE),a
	ret

DRAWMUT:
	ld	ix,MUTTAB
	ld	b,8
DM0:	push	bc
	ld	a,(ix+7)
	or	a
	jr	z,DMNEXT
	cp	2
	jr	nz,DM1
	ld	a,(FRAMES)	; eaten: flashes
	and	2
	jr	z,DMNEXT
	ld	hl,MUT_E2
	jr	DMGO
DM1:	ld	a,(EDIBLE)
	or	a
	jr	z,DM3
	cp	30		; the last second: blinking
	jr	nc,DM2
	ld	a,(FRAMES)
	and	4
	jr	z,DM3
DM2:	ld	hl,MUT_E1
	bit	2,(ix+9)
	jr	z,DMGO
	ld	hl,MUT_E2
	jr	DMGO
DM3:	ld	hl,MUT_R1
	ld	a,(ix+4)
	bit	7,a
	jr	z,DM4
	ld	hl,MUT_L1
DM4:	bit	2,(ix+9)
	jr	z,DMGO
	inc	hl
	inc	hl
	inc	hl
DMGO:	ld	c,(ix+0)
	ld	a,(ix+1)
	sub	3
	ld	b,a
	ld	d,3
	call	SPRITE
DMNEXT:	ld	de,MUTLEN
	add	ix,de
	pop	bc
	djnz	DM0
	ret

; HITMUT - Bob against each mutant (boxes).  Edible: eaten for 80 or 90; otherwise he dies.
HITMUT:	ld	a,(BOBSTATE)
	cp	S_DYING
	ret	z
	cp	S_TRANS
	ret	z
	cp	S_FLY
	ret	z
	ld	ix,MUTTAB
	ld	b,8
HM0:	push	bc
	ld	a,(ix+7)
	cp	1
	jr	nz,HMNEXT
	; overlap in x: mutant x+1 .. x+4 against Bob x+1 .. x+4 (the Atari's collisions are
	;   pixel-exact, so the outer columns of both get the benefit of the doubt)
	ld	a,(BOBX)
	sub	(ix+0)		; bob.x - m.x  in -3 .. 3 means overlap
	add	a,3
	cp	7
	jr	nc,HMNEXT
	; overlap in y: the mutant's body, feet-2 .. feet-1 (its thin top row does not count),
	;   against Bob y .. y+5
	ld	a,(ix+1)
	sub	2		; mutant body top
	ld	hl,BOBY
	sub	(hl)		; m.top - b.top in -1 .. 5
	add	a,1
	cp	7
	jr	nc,HMNEXT
	ld	a,(EDIBLE)
	or	a
	jr	nz,HMEAT
	pop	bc
	jp	KILLBOB
HMEAT:	ld	(ix+7),2
	ld	(ix+8),45
	call	RANDOM
	and	$10
	or	$80		; 80 or 90 points
	ld	c,2
	call	ADDSCORE
	ld	bc,$1018
	call	SOUND
HMNEXT:	ld	de,MUTLEN
	add	ix,de
	pop	bc
	djnz	HM0
	ret

;=============================================================================
;  ITEMS - Bob touching an item collects it: points, and the mutants turn edible
;  ITEMTAB: 9 bytes each: x, y, w, h, points/100, shape, picture (2), present
;=============================================================================
ITEMS:	ld	a,(BOBSTATE)
	cp	S_DYING
	ret	z
	ld	a,(NITEMS)
	or	a
	ret	z
	ld	b,a
	ld	ix,ITEMTAB
IT0:	push	bc
	ld	a,(ix+8)
	or	a
	jr	z,ITNEXT
	; x overlap: item x .. x+w-1 against Bob x+1 .. x+4
	ld	a,(BOBX)
	add	a,4
	cp	(ix+0)
	jr	c,ITNEXT	; Bob's right < item left
	ld	a,(ix+0)
	add	a,(ix+2)
	dec	a
	ld	hl,BOBX
	ld	c,(hl)
	inc	c
	cp	c
	jr	c,ITNEXT	; item right < Bob's left
	; y overlap: item y .. y+h-1 against Bob y .. y+5
	ld	a,(BOBY)
	add	a,BOBH-1
	cp	(ix+1)
	jr	c,ITNEXT
	ld	a,(ix+1)
	add	a,(ix+3)
	dec	a
	ld	hl,BOBY
	cp	(hl)
	jr	c,ITNEXT
	; collected
	ld	(ix+8),0
	call	ITEMERASE
	ld	a,(ix+5)	; the goblet on station 5 is poisoned
	cp	33
	jr	nz,IT1
	ld	a,(STATION)
	cp	5
	jr	nz,IT1
	pop	bc
	jp	KILLBOB
IT1:	ld	a,(ix+5)	; TNT on station 10: its tons go into the charge
	sub	34
	cp	3
	jr	nc,IT2
	ld	a,(TNT)
	add	a,(ix+4)
	ld	(TNT),a
	call	SHOWTNT
IT2:	ld	a,(ix+4)
	call	BINBCD
	ld	c,1
	call	ADDSCORE
	ld	a,80		; the mutants are edible for 80 frames (2.7 s; zone 1)
	ld	(EDIBLE),a
	ld	a,$40		; a falling whistle, played a piece per frame (WHISTLE)
	ld	(WHISTLE),a
ITNEXT:	ld	de,9
	add	ix,de
	pop	bc
	dec	b
	jp	nz,IT0
	ret

;=============================================================================
;  TALLY - count the bonus into the score; GAMEOVER - the end
;=============================================================================
TALLY:	ld	a,(BONUS)
	or	a
	ret	z
	sub	1
	daa
	ld	(BONUS),a
	call	SHOWBONUS
	ld	a,$01
	ld	c,1
	call	ADDSCORE
	ld	bc,$0C10
	call	SOUND
	call	WAITTICK
	jr	TALLY

GAMEOVER:
	ld	hl,VRAM+7*64+24
	ld	de,T_OVER
	call	PRINTV
	call	CLEMENTINE
	ld	b,90
GO1:	push	bc
	call	WAITTICK
	pop	bc
	djnz	GO1
	ret
T_OVER:	db	"  GAME  OVER  ",0

; CLEMENTINE - "Oh My Darling, Clementine" on the cassette port, from the Atari's tune
;   (TUNE, generated from its table).  Each note: B = half period, then the number of cycles;
;   a short gap between notes stands in for the Atari's decay, a longer one ends a phrase.
CLEMENTINE:
	ld	hl,TUNE
CL1:	ld	a,(hl)
	inc	hl
	cp	$FF
	ret	z
	or	a
	jr	nz,CL2
	ld	b,8		; end of a phrase
	call	WAITN
	jr	CL1
CL2:	ld	b,a		; B = half period
	ld	e,(hl)		; DE = cycles
	inc	hl
	ld	d,(hl)
	inc	hl
	push	hl
CL3:	ld	a,d		; 255 cycles at a time
	or	a
	ld	c,255
	jr	nz,CL4
	ld	a,e
	or	a
	jr	z,CL5
	ld	c,e
CL4:	push	bc
	push	de
	call	BEEP
	pop	de
	pop	bc
	ld	a,e
	sub	c
	ld	e,a
	jr	nc,CL3
	dec	d
	jr	CL3
CL5:	pop	hl
	ld	b,2		; the gap between notes
	call	WAITN
	jr	CL1
; WAITN - wait B ticks
WAITN:	push	bc
	push	hl
	call	WAITTICK
	pop	hl
	pop	bc
	djnz	WAITN
	ret

;=============================================================================
;  Tables
;=============================================================================
	include	data.asm

;=============================================================================
;  Variables
;=============================================================================
	include	specials.asm
TABLES	equ	$8300
	include	tables.asm

	org	$8800
SEED:	ds	2
FRAMES:	ds	2
SOUNDON: ds	1
SCORE:	ds	3		; packed BCD, most significant first
LIVES:	ds	1
XLIFE:	ds	1
STATION: ds	1
ZONE:	ds	1
STARTST: ds	1
BONUS:	ds	1		; packed BCD hundreds
BONUSTMR: ds	1
SECTIONS: ds	2
LISTS:	ds	12		; runs, ladders, slides, items, mutants, specials
STNAME:	ds	2
BOBSX:	ds	1
BOBSFEET: ds	1
BOBX:	ds	1
BOBY:	ds	1
BOBDIR:	ds	1
BOBFRAC: ds	1
BOBANIM: ds	1
BOBSTATE: ds	1
JIDX:	ds	1
JDX:	ds	1
FALLROWS: ds	1
LADTOP:	ds	1
LADBOT:	ds	1
SLIDEP:	ds	2
DYTMR:	ds	1
EDIBLE:	ds	1
KEYNOW:	ds	1
KEYOLD:	ds	1
DPTR:	ds	2
NOVRAM:	ds	1
SPCOL:	ds	1
SPODD:	ds	1
NITEMS:	ds	1
TMP1:	ds	1
TMP2:	ds	1
TMP3:	ds	1
TMP4:	ds	1
TMP5:	ds	1
TMP6:	ds	1
TMP7:	ds	1
MELTBUF: ds	6
TRANSON: ds	1		; this station has transporters
TRX0:	ds	1		; booth left wall
TRX1:	ds	1		; booth right wall
TRBLO:	ds	1		; Bob's x range inside a booth
TRBHI:	ds	1
TRF:	ds	4		; feet rows of booths 1-4
TRLOCK:	ds	1		; frames until the transporter is charged
TRDEST:	ds	1
TRTMR:	ds	1
TRPIC:	ds	6
NPLAT:	ds	1
PLATTAB: ds	8*11
HAZON:	ds	1		; something deadly on this station
WALLON:	ds	1		; walls on this station
LIFTON:	ds	1
LIFTDRV: ds	1		; Bob is driving the lift
LIFTX:	ds	1
LIFTROW: ds	1
LIFTXMIN: ds	1
LIFTXMAX: ds	1
LIFTRMIN: ds	1
LIFTRMAX: ds	1
LIFTPH:	ds	1
LIFTFR:	ds	1
PULVON:	ds	1
PULVBEAM: ds	1
PULVTOP: ds	1
PULVBOT: ds	1
PULVTAB: ds	4*4
CANON:	ds	1
CANX:	ds	1
CANXMIN: ds	1
CANXMAX: ds	1
CANROWS: ds	3
CANREST: ds	1
CANST:	ds	1
CANFR:	ds	1
LIFTERA: ds	1
TNT:	ds	1
LASTCX:	ds	1		; where Bob last claimed
LASTCY:	ds	1
SNDB:	ds	1		; queued tone: half period
SNDN:	ds	1		; and cycles left
WHISTLE: ds	1		; pick-up whistle pitch (0 = silent)
FLASHCD: ds	1		; frames before the death flash may come again
INVULN:	ds	1		; the testing cheat
IKEYOLD: ds	1
IDLE:	ds	1
DEMOST:	ds	1
MUTTAB:	ds	8*MUTLEN
ITEMTAB: ds	16*9

	end	START
