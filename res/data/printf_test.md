func main();
func print(str, r, g, b);
func putch(c, r, g, b);
func infloop();
func scr_push_byte(b);
func alloc(size); // returns a pointer to a memory area of given size
func strcpy(buff, str); // copy string to buffer
func strlen(str); 
func print_num(num);
//func print_ch(ch);
//func print_digit(d);
func strrev(str); // reverse a string
func printc(ch);
func prints(str);
//func print_iter_string(str);
func newline();
//func print_i_c(i,c);
//func print_s_i(s,i);
//func print_num2(num);
func printf(fmt, args);
var adr_scr = 67536;
var scr_I = 0;
var alloc_p = 10000;
var n_tiles_x = 56;
var n_tiles_y = 36;

main();
print("END PROGRAM", 255,0,0);
infloop();


func main(){
	print("Hello World!", 128,255,0);
	var args = alloc(10);
	args[0] = "world";
	args[4] = 123;
	printf("hello %s, num [%d]\n", args);
	args[0] = strlen("\n");
	printf("strlen( /n ) = %d\n", args);
	printf("Okay.\n",args);
}

func print(str,r,g,b){
	var i = 0;	
	var c = str[0];
	while(c){
		putch(c, r,g,b);
		i++;
		c = str[i*4];
	}
}

func putch(c, r,g,b){
	scr_push_byte(c); //char
	scr_push_byte(r); // color_fg.r
	scr_push_byte(g); // color_fg.g
	scr_push_byte(b); // color_fg.b
	scr_push_byte(0); // color_bg.r
	scr_push_byte(0); // color_bg.g
	scr_push_byte(0); // color_bg.b
}

func scr_push_byte(b){
	adr_scr[scr_I] = b; scr_I++;
}

func infloop(){while(1){}}

func alloc(size){
	var res = alloc_p;
	alloc_p = alloc_p + size;
	return res;
}

func strcpy(buff, str){
	var I = 0;
	while(str[I*4]){
		buff[I*4] = str[I*4];
		I++;
	}
	buff[I*4] = 0;
	return buff;
}

func printf(fmt, args){
	var I = 0;
	var argI = 0;
	var c = fmt[I*4];
	var arg = 0;
	while(c){
		I++;
		var c2 = fmt[I*4];
		if(c2){
			var is_perc = (c == ("%"[0]));
			var is_bsl = (c == ("\"[0])); //"
			var is_spec = is_perc + is_bsl;
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
		c = fmt[I*4];
	}
}

//func sprintf(buff, fmt, args){
//	var I = 0;
//	var argI = 0;
//	var c = fmt[I*4];
//	while(c){
//		var c2 = fmt[I*4+1];
//		if ((c == "%"[0]) and c2){
//			if(c2 == "%"[0]){buff[4*I] = c2; I++;}
//			if(c2 == "s"[0]){
//				var str = args[argI++];
//				var len = strlen(str);
//				sprint(4*I+buff, str);
//				I = I + len;
//			}
//		}else{
//			buff[4*I] = c; I++;
//		}
//	}
//}

func strlen(str){
	var I = 0;
	while(str[4*I]){I++;}
	return I;
}

func print_num(num){
	var buff = "aaaaaaaaaaa";
	var buffI = 0;
	var nums = "0123456789";
	while(num > 0){
		var digit = num % 10;
		num = num / 10;
		var ch = nums[digit*4];
		buff[buffI*4] = ch; buffI++;
	}
	buff[buffI*4] = 0;
	strrev(buff);
	prints(buff);
}

//func print_num2(num){
//	var buff = "aaaaaaaaaaa";
//	var buffI = 0;
//	var nums = "0123456789";
//	while(num > 0){
//		var digit = num % 10;
//		num = num / 10;
//		var ch = nums[digit*4];
//		//buff[buffI*4] = ch; buffI++;
//		printc(ch);
//	}
//	buff[buffI*4] = 0;
//	strrev(buff);
//	prints(buff);
//}

func strrev(buff){
	var sw = 0;
	var len = strlen(buff);
	var idx_1 = 0;
	var idx_2 = len-1;
	//print_s_i("idx_1", idx_1); print_s_i("idx_2", idx_2); newline();
	while(idx_1 < idx_2){
		//print_i_c(idx_1, buff[idx_1*4]);
		sw = buff[idx_1*4];
		buff[idx_1*4] = buff[idx_2*4];
		//print_i_c(idx_2, buff[idx_2*4]);
		buff[idx_2*4] = sw;
		idx_1++;
		idx_2--;	
	}
}

//func print_digit(digit){
//	if(digit == 0){prints("0");}
//	if(digit == 1){prints("1");}
//	if(digit == 2){prints("2");}
//	if(digit == 3){prints("3");}
//	if(digit == 4){prints("4");}
//	if(digit == 5){prints("5");}
//	if(digit == 6){prints("6");}
//	if(digit == 7){prints("7");}
//	if(digit == 8){prints("8");}
//	if(digit == 9){prints("9");}
//}

//func print_ch(ch){
//	var buff = "a";
//	buff[0] = ch;
//	print(buff,255,255,255);
//}

func printc(ch){putch(ch,255,255,255);}
func prints(s){print(s,255,255,255);}

//func print_iter_string(str){
//	var len = strlen(str);
//	var I = 0;
//	while(I < len){
//		var ch = str[I*4];
//		print_i_c(I, ch);
//		I++;
//	}
//}

func newline(){
	var n_lines = (scr_I/7) / n_tiles_x;
	scr_I = (n_lines+1)*n_tiles_x*7;
	//var diff = n_tiles_x - ((scr_I/7) % n_tiles_x);
	//var I = 0;
	//while(I < diff){
	//	prints("A");
	//	I++;	
	//}
}

//func print_i_c(I, ch){
//		prints("["); print_digit(I); prints("] : ["); printc(ch); prints("]"); newline();
//}
//func print_s_i(s,i){
//	prints(s); prints(": "); print_digit(i); prints(" ");
//}