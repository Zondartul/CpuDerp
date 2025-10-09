func main();
func print(str, r, g, b);
func putch(c, r, g, b);
func infloop();
func scr_push_byte(b);
var adr_scr = 67536;
var scr_I = 0;

main();
infloop();


func main(){
	print("Hello World!", 128,255,0);
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
