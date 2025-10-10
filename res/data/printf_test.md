func main();
func print(str, r, g, b);
func putch(c, r, g, b);
func infloop();
func scr_push_byte(b);
func alloc(size); // returns a pointer to a memory area of given size
func sprint(buff, str); // copy string to buffer
func strlen(str); 
func print_num(num);
func print_ch(ch);
func print_digit(d);
var adr_scr = 67536;
var scr_I = 0;
var alloc_p = 3000;

main();
infloop();


func main(){
	print("Hello World!", 128,255,0);
	var buff = alloc(4*80);
	var args = alloc(10);
	args[0] = "derpy";
	var str = "durp";
	print(str, 255,255,255);
	print_digit(5);
	print_ch(87);
	print_ch("W"[0]);
	print_num(247);
	sprint(buff, "hoi %s friends", args);
	print(buff, 255,255,0);
}

func print(str,r,g,b){
	var i = 0;	
	var c = str[i];
	while(c){
		c = str[i*4];
		i++;
		putch(c, r,g,b);
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

func sprint(buff, str){
	var I = 0;
	while(str[I]){
		buff[I] = str[I];
		I++;
	}
	buff[I] = 0;
	return buff;
}

func sprintf(buff, fmt, args){
	var I = 0;
	var argI = 0;
	var c = fmt[I];
	while(c){
		var c2 = fmt[I+1];
		if ((c == "%"[0]) and c2){
			if(c2 == "%"[0]){buff[I++] = c2;}
			if(c2 == "s"[0]){
				var str = args[argI++];
				var len = strlen(str);
				sprint(buff+I, str);
				I = I + len;
			}
		}else{
			buff[I++] = c;
		}
	}
}

func strlen(str){
	var I = 0;
	while(str[I++]){}
	return I;
}

func print_num(num){
	var buff = "a";
	var nums = "0123456789";
	while(num > 0){
		var digit = num % 10;
		if(digit < 0){
			print("L.",255,255,255);
		}elif(digit > 9){
			print("G.",255,255,255);
		}else{
			print_digit(digit);
		}
		num = num / 10;
		print("uh.",255,255,255);
		print_ch(nums[digit]);
	}
}

func print_digit(digit){
	print("eh.",255,255,255);
	if(digit == 0){print("0",255,255,255);}
	if(digit == 1){print("1",255,255,255);}
	if(digit == 2){print("2",255,255,255);}
	if(digit == 3){print("3",255,255,255);}
	if(digit == 4){print("4",255,255,255);}
	if(digit == 5){print("5",255,255,255);}
	if(digit == 6){print("6",255,255,255);}
	if(digit == 7){print("7",255,255,255);}
	if(digit == 8){print("8",255,255,255);}
	if(digit == 9){print("9",255,255,255);}
}

func print_ch(ch){
	var buff = "a";
	buff[0] = ch;
	print(buff,255,255,255);
}
