func main();
func print(str, r, g, b);
func putch(c, r, g, b);
func infloop();
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
		c = str[i++];
		putch(c, r,g,b);
	}
}

func putch(c, r,g,b){
	adr_scr[scr_I+0] = c;
	adr_scr[scr_I+1] = r;
	adr_scr[scr_I+2] = g;
	adr_scr[scr_I+3] = b;
	scr_I = scr_I+4;
}

func infloop(){while(1){}}
