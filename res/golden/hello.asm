# Begin code block cb_1
:lbl_from_2:
# IR: MOV var_8__x imm_9
mov EAX, 67536;
mov *var_8__x, EAX;
# IR: MOV var_9__scr_I imm_10
mov EAX, 0;
mov *var_9__scr_I, EAX;
# IR: CALL func_4__main [ ] tmp_11
call func_4__main;
add ESP, 0;
mov *tmp_11, eax;
# IR: CALL func_5__infloop [ ] tmp_12
call func_5__infloop;
add ESP, 0;
mov *tmp_12, eax;
:lbl_to_3:
# End code block cb_1
# Begin code block cb_13
:func_4__main:
# IR: ENTER scp_14__NULL
sub ESP, 68;
# IR: MOV var_15__i imm_16
mov EAX, 0;
mov EBP[-3], EAX;
# IR: MOV var_17__c var_18__str
mov EAX, EBP[-7];
mov EBP[-11], EAX;
# IR: OP INDEX var_17__c imm_20 var_17__c
mov EAX, EBP[-11];
mov EBX, 0;
add EAX, EBX;
# IR: MOV var_21__c var_17__c
mov EAX, EBP[-11];
mov EBP[-15], EAX;
# IR: WHILE cb_22 imm_24 cb_26 lbl_23__while_next lbl_24__while_end
:lbl_23__while_next:
# Begin code block cb_22
:lbl_from_25:
:lbl_to_28:
# End code block cb_22
mov EAX, 0;
cmp EBP[-15], EAX;
jz lbl_24__while_end;
# Begin code block cb_26
:lbl_from_29:
:lbl_to_30:
# End code block cb_26
# IR: OP ADD var_15__i imm_32 var_15__i
mov EAX, EBP[-3];
mov EBX, 1;
add EAX, EBX;
mov EBP[-3], EAX;
# IR: OP MUL var_15__i imm_34 tmp_33
mov EAX, EBP[-3];
mov EBX, 4;
mul EAX, EBX;
mov EBP[-19], EAX;
# IR: OP INDEX var_18__str tmp_33 var_17__c
mov EAX, EBP[-7];
mov EBX, EBP[-19];
add EAX, EBX;
# IR: MOV var_21__c var_17__c
mov EAX, EBP[-11];
mov EBP[-15], EAX;
# IR: CALL func_6__putch var_21__c [ var_27__r var_28__g var_29__b ] tmp_35
push EBP[-23];
push EBP[-27];
push EBP[-31];
push EBP[-15];
call func_6__putch;
add ESP, 16;
mov *tmp_35, eax;
# IR: MOV var_21__c var_17__c
mov EAX, EBP[-11];
mov EBP[-15], EAX;
jmp lbl_23__while_next;
:lbl_24__while_end:
# IR: LEAVE
sub ESP, -68;
ret;
:lbl_to_33:
# End code block cb_13
# Begin code block cb_36
:func_5__infloop:
# IR: ENTER scp_37__NULL
sub ESP, 51;
# IR: WHILE cb_38 imm_40 cb_41 lbl_39__while_next lbl_40__while_end
:lbl_39__while_next:
# Begin code block cb_38
:lbl_from_42:
:lbl_to_43:
# End code block cb_38
mov EAX, 0;
cmp 1, EAX;
jz lbl_40__while_end;
# Begin code block cb_41
:lbl_from_44:
:lbl_to_45:
# End code block cb_41
jmp lbl_39__while_next;
:lbl_40__while_end:
# IR: LEAVE
sub ESP, -51;
ret;
:lbl_to_46:
# End code block cb_36
# Begin code block cb_47
:func_6__putch:
# IR: ENTER scp_48__NULL
sub ESP, 55;
# IR: CALL func_7__scr_push_byte [ var_52__c ] tmp_53
push EBP[-19];
call func_7__scr_push_byte;
add ESP, 4;
mov *tmp_53, eax;
# IR: CALL func_7__scr_push_byte [ var_54__r ] tmp_55
push EBP[-15];
call func_7__scr_push_byte;
add ESP, 4;
mov *tmp_55, eax;
# IR: CALL func_7__scr_push_byte [ var_56__g ] tmp_57
push EBP[-11];
call func_7__scr_push_byte;
add ESP, 4;
mov *tmp_57, eax;
# IR: CALL func_7__scr_push_byte [ var_58__b ] tmp_59
push EBP[-7];
call func_7__scr_push_byte;
add ESP, 4;
mov *tmp_59, eax;
# IR: CALL func_7__scr_push_byte [ imm_62 ] tmp_63
push 0;
call func_7__scr_push_byte;
add ESP, 4;
mov *tmp_63, eax;
# IR: CALL func_7__scr_push_byte [ imm_64 ] tmp_65
push 0;
call func_7__scr_push_byte;
add ESP, 4;
mov *tmp_65, eax;
# IR: CALL func_7__scr_push_byte [ imm_66 ] tmp_67
push 0;
call func_7__scr_push_byte;
add ESP, 4;
mov *tmp_67, eax;
# IR: LEAVE
sub ESP, -55;
ret;
:lbl_to_49:
# End code block cb_47
# Begin code block cb_68
:func_7__scr_push_byte:
# IR: ENTER scp_69__NULL
sub ESP, 51;
# IR: OP INDEX var_8__scr_I var_9__scr_I tmp_70
mov EAX, *var_8__x;
mov EBX, *var_9__scr_I;
add EAX, EBX;
# IR: MOV var_70__tmp tmp_70
mov EAX, EBP[-7];
mov EBP[-11], EAX;
# IR: MOV var_70__tmp var_71__b
mov EAX, EBP[-15];
mov EBP[-11], EAX;
# IR: OP ADD var_9__scr_I imm_73 var_9__scr_I
mov EAX, *var_9__scr_I;
mov EBX, 1;
add EAX, EBX;
mov *var_9__scr_I, EAX;
# IR: LEAVE
sub ESP, -51;
ret;
:lbl_to_72:
# End code block cb_68
:var_8__x: db 0;
:var_9__scr_I: db 0;
:tmp_11: db 0;
:tmp_12: db 0;
:imm_6: db "\nHello World!\n", 0;
:imm_31: db "Hello World!", 0;
