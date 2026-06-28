# Begin code block cb_1
:lbl_from_2:
# IR: OP INDEX var_5__arr imm_7 var_6__tmp
mov EAX, *var_5__arr;
mov EBX, 4;
mul EAX, EBX;
mov ECX, EAX;
# IR: OP INDEX var_6__tmp imm_9 var_6__tmp
mov EAX, ECX;
mov EBX, 1;
add EAX, EBX;
mov ECX, EAX;
# IR: MOV var_4__x var_6__tmp
mov EAX, ECX;
mov *var_4__x, EAX;
# IR: CALL func_3__test [ ] tmp_10
call func_3__test;
add ESP, 0;
mov *tmp_10, eax;
:lbl_to_3:
# End code block cb_1
# Begin code block cb_11
:func_3__test:
# IR: ENTER scp_12__NULL
sub ESP, 55;
# IR: OP INDEX var_14__arr2 imm_16 var_15__tmp
mov EAX, EBP[-7];
mov EBX, 4;
mul EAX, EBX;
mov ECX, EAX;
# IR: OP INDEX var_15__tmp imm_18 var_15__tmp
mov EAX, ECX;
mov EBX, 1;
add EAX, EBX;
mov ECX, EAX;
# IR: MOV var_13__x2 var_15__tmp
mov EAX, ECX;
mov EBP[-3], EAX;
# IR: LEAVE
sub ESP, -55;
ret;
:lbl_to_5:
# End code block cb_11
:var_4__x: db 0;
:var_5__arr: db 0;
:var_6__y: db 0;
:tmp_10: db 0;
