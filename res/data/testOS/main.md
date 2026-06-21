func main();
func print(str);
func putch(c);
func infloop();
func scr_push_byte(b);
func has_char();
func get_char();
func malloc(size);
func process_command(buff);
func str_eq(str_A, str_B); // returns 1 if strings are equal 
func set_col(R,G,B);
func println(str);
func newline();
var adr_scr = 67536;
var adr_kb = 81648;
var scr_I = 0;
var alloc_head = 10000;
var char_newline = 5;
var char_backspace = 4;
var col_R = 255;
var col_G = 255;
var col_B = 255;
var scr_width = 56;

main();
infloop();

func main(){
	set_col(128,255,0);
	println("Hello World!");
	set_col(255,255,255);
	var buff = malloc(80);
	var buffI = 0;
	while(1){
		if(has_char()){
			var c = get_char(); // btw another c exists
			if (c == char_newline){
				newline();
				process_command(buff);
				buffI = 0;
				buff[buffI] = 0;
			}else{
				buff[buffI] = c;
				buffI = buffI + 4;
				buff[buffI] = 0;
				putch(c);
			}
		}
	}
}

func println(str){
	print(str);
	newline();
}

func newline(){
	var width_I = scr_width*7;
	scr_I = scr_I + (width_I - (scr_I % width_I));
}

func print(str){
	var i = 0;	
	var c = str[i];
	while(c){
		c = str[i*4];
		i++;
		putch(c);
	}
}

func putch(c){
	scr_push_byte(c); //char
	scr_push_byte(col_R); // color_fg.r
	scr_push_byte(col_G); // color_fg.g
	scr_push_byte(col_B); // color_fg.b
	scr_push_byte(0); // color_bg.r
	scr_push_byte(0); // color_bg.g
	scr_push_byte(0); // color_bg.b
}

func scr_push_byte(b){
	adr_scr[scr_I] = b; scr_I++;
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
	alloc_head = alloc_head + size;
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
		if((str_A[I]) == (str_B[I])) //if(cA == cB)
		{}
		else
		{ return 0; }
		I = I + 4;
	}
	return 1;
}

func set_col(R,G,B){
	col_R = R;
	col_G = G;
	col_B = B;
}
