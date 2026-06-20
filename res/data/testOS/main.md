func main();
func print(str, r, g, b);
func putch(c, r, g, b);
func infloop();
func scr_push_byte(b);
func has_char();
func get_char();
var adr_scr = 67536;
var adr_kb = 81648;
var scr_I = 0;

main();
infloop();


func main(){
	print("Hello World!", 128,255,0);
	while(1){
		if(has_char()){
			var c = get_char(); // btw another c exists
			putch(c,255,255,255);
		}
	}
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

func has_char(){
	return adr_kb[0];
}

func get_char(){
	var c = adr_kb[1];
	adr_kb[0] = 1;
	return c;
}
