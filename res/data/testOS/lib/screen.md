func print(str);
func putch(c);
func scr_push_byte(b);
func set_col(R,G,B);
func println(str);
func newline();

var adr_scr = 67536;
var scr_I = 0;
var col_R = 255;
var col_G = 255;
var col_B = 255;
var scr_width = 56;

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

func set_col(R,G,B){
	col_R = R;
	col_G = G;
	col_B = B;
}

