func main();
func print(str:String, r:u8, g:u8, b:u8);
func putch(c:char, r:u8, g:char, b:u8);
func infloop();
func scr_push_byte(b:char);
var adr_scr:Ref[char] = 67536;
var scr_I:int = 0;

main();
infloop();


func main(){
	print("Hello World!", 128,255,0);
}

func print(str:String,r:u8,g:u8,b:u8){
	var i = 0;	
	var c:char = str[i];
	while(c){
		c = str[i];
		i++;
		putch(c, r,g,b);
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
