# Begin code block cb_1
:lbl_from_2:
# IR: MOV var_4__x imm_5
mov EAX, 0;
mov *var_4__x, EAX;
# IR: IF cb_6 imm_7 cb_8
:lbl_else_4:
mov EAX, 0;
cmp 1, EAX;
jz lbl_else_4;
# Begin code block cb_8
:lbl_from_9:
:lbl_to_10:
# End code block cb_8
# IR: MOV var_4__x imm_11
mov EAX, 2;
mov *var_4__x, EAX;
jmp lbl_end_4;
:lbl_else_4:
# IR: ELSE_IF cb_12 imm_13 cb_14
cmp 3, EAX;
jz lbl_else_6;
# Begin code block cb_14
:lbl_from_15:
:lbl_to_16:
# End code block cb_14
# IR: MOV var_4__x imm_17
mov EAX, 4;
mov *var_4__x, EAX;
jmp lbl_end_4;
:lbl_else_6:
# Begin code block cb_18
:lbl_from_19:
:lbl_to_20:
# End code block cb_18
# IR: MOV var_4__x imm_21
mov EAX, 5;
mov *var_4__x, EAX;
:lbl_end_4:
:lbl_to_3:
# End code block cb_1
:var_4__x: db 0;
