# Begin code block cb_1
:lbl_from_2:
# IR: MOV var_12__adr_scr imm_13
mov EAX, 67536;
mov *var_12__adr_scr, EAX;
# IR: MOV var_14__scr_I imm_15
mov EAX, 0;
mov *var_14__scr_I, EAX;
# IR: MOV var_16__alloc_p imm_17
mov EAX, 10000;
mov *var_16__alloc_p, EAX;
# IR: MOV var_18__n_tiles_x imm_19
mov EAX, 56;
mov *var_18__n_tiles_x, EAX;
# IR: MOV var_20__n_tiles_y imm_21
mov EAX, 36;
mov *var_20__n_tiles_y, EAX;
# IR: CALL func_4__main [ ] tmp_22
call func_4__main;
add ESP, 0;
mov *tmp_22, eax;
# IR: CALL func_5__print [ imm_24 imm_25 imm_26 imm_27 ] tmp_28
push 0;
push 255;
push 0;
push 255;
push imm_24;
call func_5__print;
add ESP, 20;
mov *tmp_28, eax;
# IR: CALL func_6__infloop [ ] tmp_29
call func_6__infloop;
add ESP, 0;
mov *tmp_29, eax;
:lbl_to_3:
# End code block cb_1
# ... (additional code blocks omitted for brevity - full output would be very long)
# End code block cb_1
:var_12__adr_scr: db 0;
:var_14__scr_I: db 0;
:var_16__alloc_p: db 0;
:var_18__n_tiles_x: db 0;
:var_20__n_tiles_y: db 0;
:tmp_22: db 0;
:tmp_28: db 0;
:tmp_29: db 0;
:imm_23: db "END PROGRAM", 0;
:imm_24: db "Hello World!", 0;
