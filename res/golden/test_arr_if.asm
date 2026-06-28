# Begin code block cb_1
:lbl_from_2:
# IR: MOV var_5__x imm_6
mov EAX, imm_6;
mov *var_5__x, EAX;
# IR: MOV var_7__y imm_8
mov EAX, imm_8;
mov *var_7__y, EAX;
# IR: CALL func_4__main [ ] tmp_9
call func_4__main;
add ESP, 0;
mov *tmp_9, eax;
:lbl_to_3:
# End code block cb_1
# Begin code block cb_10
:func_4__main:
# IR: ENTER scp_11__NULL
sub ESP, 67;
# IR: MOV var_12__I imm_13
mov EAX, 0;
mov EBP[-3], EAX;
# IR: MOV var_14__n imm_15
mov EAX, 0;
mov EBP[-23], EAX;
# IR: WHILE cb_16 var_17__x cb_18 lbl_17__while_next lbl_18__while_end
:lbl_17__while_next:
# Begin code block cb_16
:lbl_from_19:
:lbl_to_20:
# End code block cb_16
# IR: OP INDEX var_17__x var_12__I var_21__tmp
mov EAX, *var_5__x;
mov EBX, EBP[-3];
add EAX, EBX;
mov EBP[-27], EAX;
# IR: OP EQUAL var_21__tmp var_22__tmp var_23__cmp
cmp EBP[-27], EBP[-15];
mov EBP[-27], CTRL;
band EBP[-27], CMP_Z;
bnot EBP[-27];
bnot EBP[-27];
mov EBP[-31], EBP[-27];
# IR: IF cb_24 var_23__cmp cb_25
:lbl_else_4:
mov EAX, 0;
cmp EBP[-31], EAX;
jz lbl_else_4;
# Begin code block cb_25
:lbl_from_26:
:lbl_to_27:
# End code block cb_25
# IR: OP ADD var_14__n imm_29 var_14__n
mov EAX, EBP[-23];
mov EBX, 1;
add EAX, EBX;
mov EBP[-23], EAX;
jmp lbl_end_4;
:lbl_else_4:
# Begin code block cb_28
:lbl_from_30:
:lbl_to_31:
# End code block cb_28
# IR: RETURN imm_32
mov EAX, 0;
__LEAVE_scp_11__NULL;
ret;
:lbl_end_4:
# IR: OP ADD var_12__I imm_34 var_12__I
mov EAX, EBP[-3];
mov EBX, 4;
add EAX, EBX;
mov EBP[-3], EAX;
jmp lbl_17__while_next;
:lbl_18__while_end:
# IR: OP INDEX var_7__y var_12__I var_21__tmp
mov EAX, *var_7__y;
mov EBX, EBP[-3];
add EAX, EBX;
mov EBP[-27], EAX;
# IR: IF cb_35 var_21__tmp cb_36
mov EAX, 0;
cmp EBP[-27], EAX;
jz lbl_else_5;
# Begin code block cb_36
:lbl_from_37:
:lbl_to_38:
# End code block cb_36
# IR: RETURN imm_39
mov EAX, 0;
__LEAVE_scp_11__NULL;
ret;
jmp lbl_end_5;
:lbl_else_5:
# Begin code block cb_40
:lbl_from_41:
:lbl_to_42:
# End code block cb_40
# IR: RETURN imm_43
mov EAX, 1;
__LEAVE_scp_11__NULL;
ret;
:lbl_end_5:
# IR: LEAVE
sub ESP, -67;
ret;
:lbl_to_21:
# End code block cb_10
:var_5__x: db 0;
:var_7__y: db 0;
:tmp_9: db 0;
:imm_6: db "he", 0;
:imm_8: db "what", 0;
