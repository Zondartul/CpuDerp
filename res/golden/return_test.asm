# Begin code block cb_1
:lbl_from_2:
# IR: MOV var_4__x imm_5
mov EAX, 0;
mov *var_4__x, EAX;
# IR: CALL func_3__test [ ] tmp_6
call func_3__test;
add ESP, 0;
mov *tmp_6, eax;
# IR: MOV var_4__x tmp_6
mov EAX, *tmp_6;
mov *var_4__x, EAX;
:lbl_to_3:
# End code block cb_1
# Begin code block cb_7
:func_3__test:
# IR: ENTER scp_8__NULL
sub ESP, 51;
# IR: RETURN imm_9
mov EAX, 10;
__LEAVE_scp_8__NULL;
ret;
:lbl_to_5:
# End code block cb_7
:var_4__x: db 0;
:tmp_6: db 0;
