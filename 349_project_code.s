; LCD Control Pins on GPIOA
RS      EQU     0x20            ; PA5: Register Select (0=Command, 1=Data)
RW      EQU     0x40            ; PA6: Read/Write (0=Write, 1=Read)
EN      EQU     0x80            ; PA7: Enable Signal
BUTTON  EQU     0x01            ; PA0

    AREA    LabProjData, DATA, READWRITE, ALIGN=2
score      SPACE   4            ; 32bit frame count
random_seed SPACE  4            ; Seed for random number generator
top_delay   SPACE  4            ; Frames until top obstacle appears
bottom_delay SPACE 4            ; Frames until bottom obstacle appears
top_active  SPACE  1            ; Is top obstacle active? (0=no, 1=yes)
bottom_active SPACE 1           ; Is bottom obstacle active?


        AREA    LabProj, CODE, READONLY
        EXPORT  __main

__main  PROC
        ; Initialize LCD display
        BL      LCDInit
        
        ; Initialize random seed
        LDR     R0, =random_seed
        MOV     R1, #1          ; Initial seed (can't be 0)
        STR     R1, [R0]
        
        ; Initialize obstacle delays with minimum spacing
init_delays
        BL      Random
        MOV     R4, R0          ; Store first random value
        
        BL      Random
        MOV     R5, R0          ; Store second random value
        
        ; Ensure minimum difference between delays (at least 5 frames)
        SUBS    R2, R4, R5      ; Calculate difference
        BPL     check_diff      ; If positive, check difference
        RSB     R2, R2, #0      ; Get absolute value if negative
        
check_diff
        CMP     R2, #5          ; Minimum frames between obstacles
        BGE     delays_ok       ; If difference >= 5, we're good
        
        ; If too close, generate new random values
        B       init_delays
        
delays_ok
        ; Store the delays (larger value for top, smaller for bottom)
        CMP     R4, R5
        BGT     store_delays
        ; Swap if bottom would be larger than top
        MOV     R0, R4
        MOV     R4, R5
        MOV     R5, R0
        
store_delays
        LDR     R1, =top_delay
        STR     R4, [R1]        ; Larger delay for top
        
        LDR     R1, =bottom_delay
        STR     R5, [R1]        ; Smaller delay for bottom
        
        ; Initialize obstacle active flags
        MOV     R0, #0
        LDR     R1, =top_active
        STRB    R0, [R1]
        LDR     R1, =bottom_active
        STRB    R0, [R1]
        
        LTORG                   ; First literal pool

        ; Define Custom Character 0 (Obstacle Part 1)
        ; CGRAM Address 0x40 (64 bytes offset)
        MOV     R2, #0x40       ; Set CGRAM address command
        BL      LCDCommand      ; Send to LCD
        MOV     R5, #3          ; Initialize counter for 3 blank rows
blank0_top
        MOV     R3, #0x00       ; Blank row pattern
        BL      LCDData         ; Write to CGRAM
        SUBS    R5, R5, #1      ; Decrement counter
        BNE     blank0_top      ; Loop until 3 rows written
        MOV     R3, #0x18       ; Pattern for row 3: **   (0b00011000)
        BL      LCDData
        MOV     R3, #0x18       ; Pattern for row 4: **   (0b00011000)
        BL      LCDData
        MOV     R5, #3          ; Counter for 3 blank rows
blank0_bot
        MOV     R3, #0x00       ; Blank row pattern
        BL      LCDData
        SUBS    R5, R5, #1
        BNE     blank0_bot

        ; Define Custom Character 1 (Obstacle Part 2)
        ; CGRAM Address 0x48
        MOV     R2, #0x48       ; Set CGRAM address
        BL      LCDCommand
        MOV     R5, #3
blank1_top
        MOV     R3, #0x00
        BL      LCDData
        SUBS    R5, R5, #1
        BNE     blank1_top
        MOV     R3, #0x06       ; Pattern:    ** (0b00000110)
        BL      LCDData
        MOV     R3, #0x06
        BL      LCDData
        MOV     R5, #3
blank1_bot
        MOV     R3, #0x00
        BL      LCDData
        SUBS    R5, R5, #1
        BNE     blank1_bot

        ; Define Custom Character 2 (Obstacle Part 3)
        ; CGRAM Address 0x50
        MOV     R2, #0x50
        BL      LCDCommand
        MOV     R5, #3
blank2_top
        MOV     R3, #0x00
        BL      LCDData
        SUBS    R5, R5, #1
        BNE     blank2_top
        MOV     R3, #0x03       ; Pattern:     ** (0b00000011)
        BL      LCDData
        MOV     R3, #0x03
        BL      LCDData
        MOV     R5, #3
blank2_bot
        MOV     R3, #0x00
        BL      LCDData
        SUBS    R5, R5, #1
        BNE     blank2_bot

        ; Define Player Character (Full Block)
        ; CGRAM Address 0x58
        MOV     R2, #0x58       ; Set CGRAM address for player character
        BL      LCDCommand
     		
        MOV     R3, #0x00       ; Row 0: blank
        BL      LCDData
        MOV     R3, #0x00       ; Row 1: blank
        BL      LCDData
        MOV     R3, #0x07       ; Row 2: 00111b
        BL      LCDData
        MOV     R3, #0x1C       ; Row 3: 11100b
        BL      LCDData
        MOV     R3, #0x1C       ; Row 4: 11100b
        BL      LCDData
        MOV     R3, #0x07       ; Row 5: 00111b
        BL      LCDData
        MOV     R3, #0x00       ; Row 6: blank
        BL      LCDData
        MOV     R3, #0x00       ; Row 7: blank
        BL      LCDData

        ;— clear score counter —
        LDR     R0, =score
        MOVS    R1, #0
        STR     R1, [R0]

        ; Initialize Game State - always start at left (X=0)
        MOV     R4, #0          ; Top obstacle starts at X=0
        MOV     R9, #0          ; Bottom obstacle starts at X=0
        
        MOV     R7, #0          ; Player Y (previous)
        MOV     R8, #0          ; Top animation frame starts at 0
        MOV     R10, #0         ; Button previous state
        MOV     R11, #0         ; Bottom animation frame starts at 0
        MOV     R12, #0         ; Player Y (current) (0 = top, 1 = bot)

; Main Game Loop
move_loop
        ; Check for Collisions (only if obstacles are active)
        CMP     R12, #0          ; Player on top row?
        BNE.W   check_bottom_collision
        
        ; Top row collision check
        LDR     R0, =top_active
        LDRB    R0, [R0]
        CMP     R0, #0           ; Is top obstacle active?
        BEQ     no_collision      ; Skip if not active
        
        CMP     R4, #15          ; Obstacle at right edge?
        BNE.W   no_collision
        CMP     R8, #0           ; And in left-aligned state?
        BEQ.W   game_over
        
        B.W     no_collision
        
check_bottom_collision
        ; Bottom row collision check
        LDR     R0, =bottom_active
        LDRB    R0, [R0]
        CMP     R0, #0           ; Is bottom obstacle active?
        BEQ     no_collision      ; Skip if not active
        
        CMP     R9, #15          ; Obstacle at right edge?
        BNE.W   no_collision
        CMP     R11, #0          ; And in left-aligned state?
        BEQ.W   game_over

no_collision
        ; Update Top Obstacle
        ; Check if we should activate top obstacle
        LDR     R0, =top_active
        LDRB    R1, [R0]
        CMP     R1, #0           ; Already active?
        BNE     top_is_active
        
        ; Not active yet - check delay
        LDR     R2, =top_delay
        LDR     R3, [R2]
        SUBS    R3, R3, #1       ; Decrement delay counter
        STR     R3, [R2]
        BGT     skip_top          ; Still waiting
        
        ; Delay expired - activate obstacle
        MOV     R1, #1
        STRB    R1, [R0]         ; Set active flag
        B       top_is_active
        
skip_top
        ; Clear top obstacle position if not active
        MOV     R2, #0x80        ; Top row base address
        ADD     R2, R2, R4       ; Add X position
        BL      LCDCommand
        MOV     R3, #' '         ; Clear with space
        BL      LCDData
        B       update_bottom
        
top_is_active
        CMP     R8, #0           ; Check if animation frame is 0
        BNE     draw_top         ; If not, skip clearing previous position
        
        ; Calculate previous position
        SUBS    R6, R4, #1       ; Previous X = Current X - 1
        IT      LT               ; If X-1 < 0 (wrap around)
        MOVLT   R6, #15          ; Set to 15 (rightmost position)
        
        ; Clear previous position
        MOV     R2, #0x80        ; DDRAM base address (top row)
        ADD     R2, R2, R6       ; Add X position
        BL      LCDCommand       ; Set address
        MOV     R3, #' '         ; Clear with space
        BL      LCDData
        
        CMP     R4, #0
        BNE     draw_top
        MOV     R2, #0x8F
        BL      LCDCommand
        MOV     R3, #' '
        BL      LCDData
        
draw_top
        ; Draw current top obstacle
        MOV     R2, #0x80       ; Top row base address
        ADD     R2, R2, R4      ; Add X position
        BL      LCDCommand
        MOV     R3, R8          ; Use animation frame as character index
        BL      LCDData

        ; Update Bottom Obstacle
update_bottom
        ; Check if we should activate bottom obstacle
        LDR     R0, =bottom_active
        LDRB    R1, [R0]
        CMP     R1, #0           ; Already active?
        BNE     bottom_is_active
        
        ; Not active yet - check delay
        LDR     R2, =bottom_delay
        LDR     R3, [R2]
        SUBS    R3, R3, #1       ; Decrement delay counter
        STR     R3, [R2]
        BGT     skip_bottom      ; Still waiting
        
        ; Delay expired - activate obstacle
        MOV     R1, #1
        STRB    R1, [R0]         ; Set active flag
        B       bottom_is_active
        
skip_bottom
        ; Clear bottom obstacle position if not active
        MOV     R2, #0xC0        ; Bottom row base address
        ADD     R2, R2, R9       ; Add X position
        BL      LCDCommand
        MOV     R3, #' '         ; Clear with space
        BL      LCDData
        B       check_button
        
bottom_is_active
        CMP     R11, #0         ; Check animation frame
        BNE     draw_bottom
        
        ; Calculate previous position
        SUBS    R6, R9, #1      ; Previous X position
        IT      LT
        MOVLT   R6, #15
        
        ; Clear previous position
        MOV     R2, #0xC0       ; DDRAM base for bottom row (0x80 + 0x40)
        ADD     R2, R2, R6
        BL      LCDCommand
        MOV     R3, #' '
        BL      LCDData
        
        CMP     R9, #0
        BNE     draw_bottom
        MOV     R2, #0xCF
        BL      LCDCommand
        MOV     R3, #' '
        BL      LCDData

draw_bottom
        ; Draw current bottom obstacle
        MOV     R2, #0xC0       ; Bottom row base
        ADD     R2, R2, R9      ; Add X position
        BL      LCDCommand
        MOV     R3, R11         ; Animation frame character
        BL      LCDData

        ; Check Button Input
check_button
        LDR     R0, =0x40020000 ; GPIOA base
        LDR     R1, [R0, #0x10] ; Read button state
        ANDS    R1, #BUTTON     ; Isolate PA0
        
        ; Check for press (0 = pressed)
        CMP     R1, #0
        BNE     button_released
        
        ; Only toggle if previously released
        CMP     R10, #1
        BNE     button_done
        BL      TogglePlayerY   ; Change player position
        MOV     R10, #0         ; Mark as pressed
        
        ; Debounce delay
        PUSH    {R0-R3}         ; Protect registers
        MOV     R0, #50000      ; Adjust this number for delay length
debounce_loop
        SUBS    R0, R0, #1
        BNE     debounce_loop
        POP     {R0-R3}
        B       button_done

button_released
        MOV     R10, #1         ; Mark as released
button_done

        ; Update Animation States (only for active obstacles)
        ; Toggle animation frames for active obstacles
        LDR     R0, =top_active
        LDRB    R0, [R0]
        CMP     R0, #0
        BEQ     skip_top_anim
        EORS    R8, R8, #1      ; Flip top animation bit (0/1)
        
        ; Move top obstacle when animation wraps
        CMP     R8, #0
        BNE     skip_top_move
        ADD     R4, R4, #1      ; Increment X position
        CMP     R4, #16         ; Check for screen edge
        IT      GE
        MOVGE   R4, #0          ; Wrap to left side
        
        ; When top obstacle wraps, set new random delay
        BNE     skip_top_move
        BL      Random
        LDR     R1, =top_delay
        STR     R0, [R1]        ; Store normal random value
        MOV     R0, #0
        LDR     R1, =top_active
        STRB    R0, [R1]        ; Deactivate
        
skip_top_move
skip_top_anim

        LDR     R0, =bottom_active
        LDRB    R0, [R0]
        CMP     R0, #0
        BEQ     skip_bottom_anim
        EORS    R11, R11, #1    ; Flip bottom animation bit
        
        ; Move bottom obstacle when animation wraps
        CMP     R11, #0
        BNE     skip_bottom_move
        ADD     R9, R9, #1      ; Increment X position
        CMP     R9, #16
        IT      GE
        MOVGE   R9, #0
        
        ; When bottom obstacle wraps, set new random delay
        BNE     skip_bottom_move
        BL      Random
        LDR     R1, =bottom_delay
        STR     R0, [R1]        ; Store normal random value
        MOV     R0, #0
        LDR     R1, =bottom_active
        STRB    R0, [R1]        ; Deactivate
        
skip_bottom_move
skip_bottom_anim

        ; Update Player Position (Clear Old, Draw New)
        ; Only clear if position changed
        CMP     R7, R12
        BEQ     draw_new_player
        
        ; Clear old position
        MOV     R2, #0x80       ; Base address
        LSLS    R0, R7, #6      ; Previous Y * 64
        ADD     R2, R2, R0      ; Add row offset
        ADD     R2, R2, #15     ; X=15
        BL      LCDCommand
        MOV     R3, #' '        ; Clear with space
        BL      LCDData

draw_new_player
        ; Draw new position
        MOV     R2, #0x80
        LSLS    R0, R12, #6     ; Current Y
        ADD     R2, R2, R0
        ADD     R2, R2, #15
        BL      LCDCommand
        MOV     R3, #3          ; Player character
        BL      LCDData
        
        ; Update previous position
        MOV     R7, R12         ; Store current Y as new previous

        ;— increment score —
        LDR     R0, =score
        LDR     R1, [R0]
        ADDS    R1, R1, #1
        STR     R1, [R0]

        ; Frame Delay
        BL      delay
        B       move_loop

        LTORG                   ; Second literal pool

; Game Over Routine
game_over
        ; Clear the screen
        MOV     R2, #0x01       ; Clear display command
        BL      LCDCommand
        BL      delay           ; Wait for command to complete
        
        ; Display "GAME OVER" on first line
        MOV     R2, #0x83       ; DDRAM address for first line
        BL      LCDCommand
        
        ; Display "GAME OVER"
        MOV     R3, #'G'
        BL      LCDData
        MOV     R3, #'A'
        BL      LCDData
        MOV     R3, #'M'
        BL      LCDData
        MOV     R3, #'E'
        BL      LCDData
        MOV     R3, #' '
        BL      LCDData
        MOV     R3, #'O'
        BL      LCDData
        MOV     R3, #'V'
        BL      LCDData
        MOV     R3, #'E'
        BL      LCDData
        MOV     R3, #'R'
        BL      LCDData
		MOV		R3, #'!'
		BL		LCDData
		
		; — move cursor to start of 2nd line —
		MOV     R2, #0xC3       ; DDRAM base for line 2, col 0
		BL      LCDCommand

		; — print label "SCORE=" —
		MOV     R3, #'S'
		BL  LCDData
		MOV     R3, #'C'
		BL  LCDData
		MOV     R3, #'O'
		BL  LCDData
		MOV     R3, #'R'
		BL  LCDData
		MOV     R3, #'E'
		BL  LCDData
		MOV     R3, #':'
		BL  LCDData
		MOV		R3, #' '
		BL	LCDData

		; load score
        LDR     R0, =score
        LDR     R1, [R0]        ; R1 = score

        MOVS    R2, #0          ; hundreds = 0
hundreds_loop
        CMP     R1, #100
        BLT     tens_calc
        SUBS    R1, R1, #100
        ADDS    R2, R2, #1
        B       hundreds_loop

tens_calc
        MOVS    R3, #0          ; tens = 0
tens_loop
        CMP     R1, #10
        BLT     ones_calc
        SUBS    R1, R1, #10
        ADDS    R3, R3, #1
        B       tens_loop

ones_calc
        ; R1 now = ones (0–9)

        ;convert to ASCII and stash
        ADDS    R2, R2, #'0'    ; ASCII hundreds
        MOV     R8, R2
        ADDS    R3, R3, #'0'    ; ASCII tens
        MOV     R9, R3
        ADDS    R1, R1, #'0'    ; ASCII ones
        MOV     R10, R1

        ;print the three digits
        MOV     R3, R8          ; hundreds
        BL      LCDData
        MOV     R3, R9          ; tens
        BL      LCDData
        MOV     R3, R10         ; ones
        BL      LCDData
		
        ; Infinite loop (game over state)
game_over_loop
        BL      delay
        B       game_over_loop
        ENDP


; Random Number Generator (Simple LCG) - Modified for 0-15 range
; Returns: R0 = random number (0-15)
; Uses: R1, R2
Random PROC
        PUSH    {R1-R2, LR}
        LDR     R0, =random_seed
        LDR     R1, [R0]        ; Load current seed
        
        ; Linear Congruential Generator parameters
        LDR     R2, =1103515245
        MUL     R1, R1, R2     ; Multiply by a
        ADD     R1, R1, #12288  ; Add c
		ADD		R1, R1, #57
        STR     R1, [R0]        ; Store new seed
        
        AND     R0, R1, #0x0F   ; Mask to get 0-15
        POP     {R1-R2, PC}
        ENDP

; Toggle Player Y Position (0/1)
; Uses: R12 (player Y), preserves other registers

TogglePlayerY   PROC
        PUSH    {R0-R3, LR}     ; Preserve all used registers

        ; Clear old position (top or bottom)
        MOV     R2, #0x80       ; Base address
        LSLS    R0, R12, #6     ; Current Y * 64
        ADD     R2, R2, R0      ; Add row offset
        ADD     R2, R2, #15     ; X=15
        BL      LCDCommand
        MOV     R3, #' '        ; Clear with space
        BL      LCDData

        ; Additional clear for bottom row if switching from bottom
        CMP     R12, #1         ; Were we on bottom?
        BNE     ToggleContinue
        MOV     R2, #0xCF       ; Explicit bottom-right address
        BL      LCDCommand
        MOV     R3, #' '
        BL      LCDData

ToggleContinue
        ; Toggle Y position
        EOR     R12, R12, #1    ; Flip Y position (0->1 or 1->0)
        POP     {R0-R3, PC}     ; Restore and return
		ENDP


; LCD Initialization
LCDInit FUNCTION
        ; Enable GPIO clocks (A and C)
        LDR     R0, =0x40023830 ; RCC AHB1ENR register
        MOV     R1, #0x00000005 ; Enable GPIOA (bit 0) and GPIOC (bit 2)
        STR     R1, [R0]

        ; Configure PA5-7 as outputs (RS, RW, EN)
        LDR     R0, =0x40020000 ; GPIOA base
        LDR     R2, =0x28005400 ; MODER settings: PA5-7 as outputs
        STR     R2, [R0,#0x00]  ; Write to GPIOA_MODER

        ; Configure PC0-7 as outputs (Data bus)
        LDR     R1, =0x40020800 ; GPIOC base
        LDR     R2, =0x00015555 ; PC0-7 as outputs
        STR     R2, [R1,#0x00]  ; Write to GPIOC_MODER

        ; Initialize LCD
        PUSH    {LR}
        MOV     R2, #0x38       ; Function Set: 8-bit, 2-line, 5x8 font
        BL      LCDCommand
        MOV     R2, #0x0C       ; Display ON, Cursor OFF
        BL      LCDCommand
        MOV     R2, #0x01       ; Clear Display
        BL      LCDCommand
        MOV     R2, #0x06       ; Entry Mode: Increment, No Shift
        BL      LCDCommand
        POP     {LR}
        BX      LR
        ENDP


; LCD Command Write
; Input: R2 = command

LCDCommand FUNCTION
        ; Load GPIO addresses EVERY TIME
        LDR     R0, =0x40020000 ; GPIOA base
        LDR     R1, =0x40020800 ; GPIOC base
        
        STRB    R2, [R1,#0x14]  ; Write command to GPIOC_ODR (data bus)
        MOV     R2, #EN         ; Pulse EN pin
        STRB    R2, [R0,#0x14]  ; Write to GPIOA_ODR
        PUSH    {LR}
        BL      delay
        MOV     R2, #0          ; Clear EN
        STRB    R2, [R0,#0x14]
        POP     {LR}
        BX      LR
        ENDP


; LCD Data Write
; Input: R3 = data

LCDData FUNCTION
        ; Load GPIO addresses EVERY TIME
        LDR     R0, =0x40020000 ; GPIOA base
        LDR     R1, =0x40020800 ; GPIOC base
        
        STRB    R3, [R1,#0x14]  ; Write data to GPIOC_ODR
        MOV     R2, #(RS|EN)    ; Set RS + EN
        STRB    R2, [R0,#0x14]
        PUSH    {LR}
        BL      delay
        MOV     R2, #0          ; Clear EN
        STRB    R2, [R0,#0x14]
        POP     {LR}
        BX      LR
        ENDP


; Delay Subroutine (~1ms)

delay   FUNCTION
        LDR     R6, =100
outer   LDR     R7, =100
inner   SUBS    R7, R7, #1
        BNE     inner
        SUBS    R6, R6, #1
        BNE     outer
        BX      LR
        ENDP

        END