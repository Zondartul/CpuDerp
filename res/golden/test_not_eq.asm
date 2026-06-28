# Begin code block cb_1
:lbl_from_2:
# IR: MOV var_4__x imm_5
mov EAX, 1;
mov *var_4__x, EAX;
# IR: MOV var_6__y imm_7
mov EAX, 2;
mov *var_6__y, EAX;
# IR: MOV var_8__c imm_9
mov EAX, 0;
mov *var_8__c, EAX;
# IR: MOV var_10__d imm_11
mov EAX, 0;
mov *var_10__d, EAX;
# IR: OP NOT_EQUAL var_4__x var_6__y var_12__cmp
cmp *var_4__x, *var_6__y;
mov EAX, CTRL;
band EAX, CMP_NZ;
bnot EAX;
bnot EAX;
mov EBP[-3], EAX;
# IR: IF cb_13 var_12__cmp cb_14
mov EAX, 0;
cmp EBP[-3], EAX;
jz lbl_else_4;
# Begin code block cb_14
:lbl_from_15:
:lbl_to_16:
# End code block cb_14
# IR: MOV var_8__c imm_17
mov EAX, 1;
mov *var_8__c, EAX;
jmp lbl_end_4;
:lbl_else_4:
# Begin code block cb_18
:lbl_from_19:
:lbl_to_20:
# End code block cb_18
# IR: MOV var_8__c imm_21
mov EAX, 2;
mov *var_8__c, EAX;
:lbl_end_4:
# IR: OP EQUAL var_4__x var_6__y var_22__cmp
cmp *var_4__x, *var_6__y;
mov EAX, CTRL;
band EAX, CMP_Z;
bnot EAX;
bnot EAX;
mov EBP[-7], EAX;
# IR: IF cb_23 var_22__cmp cb_24
mov EAX, 0;
cmp EBP[-7], EAX;
jz lbl_else_5;
# Begin code block cb_24
:lbl_from_25:
:lbl_to_26:
# End code block cb_24
# IR: MOV var_10__d imm_27
mov EAX, 2;
mov *var_10__d, EAX;
jmp lbl_end_5;
:lbl_else_5:
# Begin code block cb_28
:lbl_from_29:
:lbl_to_30:
# End code block cb_28
# IR: MOV var_10__d imm_31
mov EAX, 1;
mov *var_10__d, EAX;
:lbl_end_5:
:lbl_to_3:
# End code block cb_1
:var_4__x: db 0;
:var_6__y: db 0;
:var_8__c: db 0;
:var_10__d: db 0;
