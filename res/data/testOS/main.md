#include "lib/screen.md"
func main();
func infloop();
func has_char();
func get_char();
func malloc(size);
func process_command(buff);
func str_eq(str_A, str_B); // returns 1 if strings are equal 
var adr_kb = 81648;
var alloc_head = 10000;
//var char_newline = 5;
var char_backspace = 4;
var buff[80];
var buffI = 0;
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
			var c = get_char(); // btw another c exists
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

func has_char(){
	return adr_kb[0];
}

func get_char(){
	var c = adr_kb[1];
	adr_kb[0] = 1;
	return c;
}

func process_command(buff){
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
	}else{
		set_col(255,255,0);
		print("unkown command [");
		print(buff);
		println("]");
	}
	set_col(255,255,255);
}

func malloc(size){
	var p = alloc_head;
	alloc_head += size;
	return p;
}

func str_eq(str_A, str_B){
	var I = 0;
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
		I += 4;
	}
	return 1;
}

