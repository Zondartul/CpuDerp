func print(str);
func putch(c);
func scr_push_byte(b);
func set_col(R,G,B);
func println(str);
func newline();

var adr_scr:Ref[u8] = 67536;
var scr_I:int = 0;
var col_R:u8 = 255;
var col_G:u8 = 255;
var col_B:u8 = 255;
var scr_width:int = 56;

func println(str:String){
	print(str);
	newline();
}

func newline(){
	var width_I:int = scr_width*7;
	scr_I = scr_I + (width_I - (scr_I % width_I));
}

func print(str:String){
	var i:int = 0;	
	var c:u8 = str[i];
	while(c){
		c = str[i];
		i++;
		putch(c);
	}
}

func putch(c:u8){
	//var arr = [c, col_R, col_G, col_B, 0, 0, 0];
	//var I = 0;
	//while(I < 0){
	//	scr_push_byte(arr[I]);
	//}
	scr_push_byte(c); //char
	scr_push_byte(col_R); // color_fg.r
	scr_push_byte(col_G); // color_fg.g
	scr_push_byte(col_B); // color_fg.b
	scr_push_byte(0); // color_bg.r
	scr_push_byte(0); // color_bg.g
	scr_push_byte(0); // color_bg.b
}

func scr_push_byte(b:u8){
	adr_scr[scr_I] = b; scr_I++;
}

func set_col(R:u8,G:u8,B:u8){
	col_R = R;
	col_G = G;
	col_B = B;
}

