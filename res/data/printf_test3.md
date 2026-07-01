func main();
func print(str:String, r:u8, g:u8, b:u8);
func putch(c:char, r:u8, g:u8, b:u8);
func infloop();
func scr_push_byte(b:u8);
func alloc(size:int); // returns a pointer to a memory area of given size
func strcpy(buff:Ref[u8], str:String); // copy string to buffer
func strlen(str:String); 
func print_num(num:int);
func dbg_print_num(num:int);
func dbg_print_s(S:String);
func print_digit(digit:int);
func strrev(str:String); // reverse a string
func printc(ch:char);
func prints(str:String);
func newline();
func printf(fmt:String, args:Ref[u32]);
var adr_scr:Ref[u8] = 67536;
var scr_I:int = 0;
var alloc_p:int = 10000;
var n_tiles_x:int = 56;
var n_tiles_y:int = 36;

main();
print("END PROGRAM", 255,0,0);
infloop();


func main(){
	print("Hello World!", 128,255,0);
	dbg_print_num(12345); newline();
	dbg_print_s("%s");
	var args:Ref[u32] = alloc(10);
	args[0] = "world";
	args[1] = 123;
	printf("x %s \n", args);
	//printf("hello %s, num [%d]\n", args);
	args[0] = strlen("\n");
	printf("strlen( /n ) = %d\n", args);
	printf("Okay.\n",args);
}

func dbg_print_s(S:String){
	var i = 0;
	while(S[i]){
		var c:char = S[i];
		prints("["); dbg_print_num(i); prints("]: ["); 
		printc(c); prints("]"); newline();
		i++;
	}
}
func dbg_print_si(S:String, num:int){
	prints(S); prints("="); dbg_print_num(num);newline();
}

func print(str:String,r:u8,g:u8,b:u8){
	var i:int = 0;	
	var c:char = str[0];
	while(c){
		putch(c, r,g,b);
		i++;
		c = str[i];
	}
}

func putch(c:char, r:u8,g:u8,b:u8){
	scr_push_byte(c); //char
	scr_push_byte(r); // color_fg.r
	scr_push_byte(g); // color_fg.g
	scr_push_byte(b); // color_fg.b
	scr_push_byte(0); // color_bg.r
	scr_push_byte(0); // color_bg.g
	scr_push_byte(0); // color_bg.b
}

func scr_push_byte(b:u8){
	adr_scr[scr_I] = b; scr_I++;
}

func infloop(){while(1){}}

func alloc(size:int){
	var res:int = alloc_p;
	alloc_p = alloc_p + size;
	return res;
}

func strcpy(buff:Ref[u8], str:String){
	var I:int = 0;
	while(str[I]){
		buff[I] = str[I];
		I++;
	}
	buff[I] = 0;
	return buff;
}

func printf(fmt:String, args:Ref[u32]){
	var I:int = 0;
	var argI:int = 0;
	var c:char = fmt[I];
	var arg:u32 = 0;
	while(c){
		I++;
		dbg_print_si(" I",I);
		var c2:char = fmt[I];
		dbg_print_si(" c2",c2);
		if(c2){
			dbg_print_si(" c", c);
			dbg_print_si(" %[0]", ("%"[0]));
			var is_perc:u8 = (c == ("%"[0]));
			var is_bsl:u8 = (c == ("\"[0])); //"
			var is_spec:u8 = is_perc + is_bsl;
			dbg_print_si(" is_perc", is_perc);
			dbg_print_si(" is_bsl", is_bsl);
			if(is_spec){
				I++;
				if(c2 == ("s"[0])){
					arg = args[argI];
					argI = argI + 4;
					prints(arg);
				}
				if(c2 == ("d"[0])){
					arg = args[argI];
					argI = argI+4;
					print_num(arg);
				}
				if(c2 == ("n"[0])){
					newline();
				}
			}else{
				printc(c);
			}
		}else{
			printc(c);
		}
		c = fmt[I];
	}
}

func strlen(str:String){
	var I = 0;
	while(str[I]){I++;}
	return I;
}

func print_num(num){
	var buff:Ref[char] = "aaaaaaaaaaa";
	var buffI:int = 0;
	var nums:String = "0123456789";
	while(num > 0){
		var digit = num % 10;
		num = num / 10;
		var ch = nums[digit];
		buff[buffI] = ch; buffI++;
	}
	buff[buffI] = 0;
	strrev(buff);
	prints(buff);
}
func dbg_print_num(num){
	if(num == 0){print_digit(0);}
	while(num > 0){
		var digit = num % 10;
		num = num / 10;
		print_digit(digit);
	}
}
func print_digit(digit){
	if (digit == 0){prints("0");}
	if (digit == 1){prints("1");}
	if (digit == 2){prints("2");}
	if (digit == 3){prints("3");}
	if (digit == 4){prints("4");}
	if (digit == 5){prints("5");}
	if (digit == 6){prints("6");}
	if (digit == 7){prints("7");}
	if (digit == 8){prints("8");}
	if (digit == 9){prints("9");}
	if (digit > 9){prints("H");}
	if (digit < 0){prints("L");}
}

func strrev(buff){
	var sw:char = 0;
	var len:int = strlen(buff);
	var idx_1:int = 0;
	var idx_2:int = len-1;
	while(idx_1 < idx_2){
		sw = buff[idx_1];
		buff[idx_1] = buff[idx_2];
		buff[idx_2] = sw;
		idx_1++;
		idx_2--;	
	}
}

func printc(ch:char){putch(ch,255,255,255);}
func prints(s:String){print(s,255,255,255);}

func newline(){
	var n_lines = (scr_I/7) / n_tiles_x;
	scr_I = (n_lines+1)*n_tiles_x*7;
}
