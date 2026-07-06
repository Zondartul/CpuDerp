#include "lib/screen.md"
func main();
func infloop();
func has_char();
func get_char();
//func malloc(size);
func process_command(buff:String);
func str_eq(str_A:String, str_B:String); // returns 1 if strings are equal 
func str_len(str:String)->int; // returns string length
func str_rev(str:Ref[u32])->int; // reverse string
func dbg_num_print(num:int);
func log10(num:int)->int; // returns floor(log10( positive number )) i.e. num of digits
func printnum(num:int); //better num print
func dbg_print_sns(str:String,num:int,str2:String);
func printnum_dbg(num:int);
func pass_test();
func pass_test2(buff:Ref[u32]);
func itoa(buff:Ref[u32], num:int);
func test_up(buff:Ref[u32]);
var adr_kb:Ref[u8] = 81648;
//var alloc_head = 10000;
//var char_newline = 5;
var char_backspace:u8 = 4;
var buff:Array[80, u32];
var buffI:int = 0;
main();
infloop();

func main(){
	set_col(128,255,0);
	println("Hello World!");
	set_col(255,255,255);
	//var buff = malloc(80);
	//var buffI = 0;
	while(1){
		if(has_char()){
			var c:u8 = get_char(); // btw another c exists
			if (c == '\n'){
				newline();
				process_command(buff);
				buffI = 0;
				buff[buffI] = 0;
			}else{
				buff[buffI] = c;
				buffI += 4;
				buff[buffI] = 0;
				putch(c);
			}
		}
	}
}

func infloop(){while(1){}}

func has_char()->int{
	return adr_kb[0];
}

func get_char()->u8{
	var c = adr_kb[1];
	adr_kb[0] = 1;
	return c;
}

func process_command(buff:String){
	set_col(255,0,255);
	if(str_eq(buff, "what")){
		println("SAY WHAT AGAIN");
	}elif(str_eq(buff,"help")){
		println("Commands: help, what, beep");
	}elif(str_eq(buff,"beep")){
		println("boop");
	}elif(str_eq(buff,"restart")){
		var f = 0;
		f();
	}elif(str_eq(buff,"reverse")){
		str_rev(buff);
		println(buff);
		newline();
		print("str_len(buff) = ");
		dbg_num_print(str_len(buff));
		println(";");
	}elif(str_eq(buff,"number")){
		dbg_num_print(1234);
		newline();
		print("log10(1234) = ");
		dbg_num_print(log10(1234));
		println(";");
		printnum(1234);
		newline();
	}elif(str_eq(buff,"number2")){
		printnum_dbg(1234);
	}elif(str_eq(buff,"up")){
		test_up(buff);
		println(buff);
	}elif(str_eq(buff,"pass")){
		pass_test();
	}else{
		set_col(255,255,0);
		print("unkown command [");
		print(buff);
		println("]");
	}
	set_col(255,255,255);
}

//func malloc(size){
//	var p = alloc_head;
//	alloc_head += size;
//	return p;
//}

func pass_test(){
	var buff:Array[100, u32];
	dbg_num_print(buff);
	buff[0] = 'h';
	buff[1] = 'i';
	buff[2] = 0;
	pass_test2(buff);
}

func pass_test2(buff:Ref){
	dbg_num_print(buff);
	println(buff);
}
func str_eq(str_A:String, str_B:String)->int{
	var I:int = 0;
	while(str_A[I]){
		//var cA = str_A[I];
		//var cB = str_B[I];
		//print("cmp [",255,255,255);
		//putch(cA,255,255,255);
		//print("] [",255,255,255);
		//putch(cB,255,255,255);
		//print("]",255,255,255);
		if(str_A[I] != str_B[I]) //if(cA == cB)
		{ return 0; }
		I += 1;
	}
	return 1;
}

func dbg_num_print(num:int){
	if (num < 0){
		putch("-");
		num = 0 - num;
	}
	while(num > 0){
		var digit = num % 10;
		num = num / 10;
		putch('0'+digit);
	}
}

func log10(num:int)->int{
	var I = 0;
	while(num > 0){
		num = num/10;
		I += 1;	
	}
	return I;
}

func dbg_print_sns(str1, num, str2){
	print(str1);
	dbg_num_print(num);
	println(str2);
}

func printnum_dbg(num:int){
	var buff[40];
	dbg_print_sns("buff = ", buff, ";");
	var I = 0;
	if(num < 0){num = 0 - num; buff[I*4] = '-'; I += 1;}
	var n = log10(num);
	dbg_print_sns("n = ",n,";");
	I += n-1;
	buff[(I+1)*4] = 0;
	while(num > 0){
		var digit = num % 10;
		num = num/10;
		dbg_print_sns("I = ",I,";");
		dbg_print_sns("digit = ",digit,";");
		dbg_print_sns("num = ",num,";");
		buff[I*4] = '0' + digit;
		I -= 1;	
	}
	println("-- printing buff --");
	print(buff);
}

func itoa(buff:Ref[u32], num:int){
	var I = 0;
	if(num < 0){num = 0 - num; buff[I*4] = '-'; I += 1;}
	var n = log10(num);
	I += n-1;
	buff[(I+1)*4] = 0;
	while(num > 0){
		var digit = num % 10;
		num = num/10;
		buff[I*4] = '0' + digit;
		I -= 1;	
	}
}

func printnum(num:int){
	var buff[40];
	dbg_print_sns("buff = ", buff, ";");
	var I = 0;
	if(num < 0){num = 0 - num; buff[I*4] = '-'; I += 1;}
	var n = log10(num);
	dbg_print_sns("n = ",n,";");
	I += n-1;
	buff[(I+1)*4] = 0;
	while(num > 0){
		var digit = num % 10;
		num = num/10;
		dbg_print_sns("I = ",I,";");
		dbg_print_sns("digit = ",digit,";");
		dbg_print_sns("num = ",num,";");
		buff[I*4] = '0' + digit;
		I -= 1;	
	}
	println("-- printing buff --");
	print(buff);
}

func str_len(str:String)->int{
	var I = 0;
	while(str[I*4]){I += 1;}
	return I;
}

func str_rev(str:Ref[u32]){
	var len = str_len(str);
	if (len < 2){return;}
	var I = len/2;
	var J = I+1;
	while(I > (0-1)){
		var C = str[I*4];
		str[I*4] = str[J*4];
		str[J*4] = C;
		I -= 1;
		J += 1;
	}
}

func test_up(buff:Ref){
	buff[0] = 'z';
}
