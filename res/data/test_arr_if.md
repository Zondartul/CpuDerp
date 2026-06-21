func main();
var x = "he";
var y = "what";
main();

func main(){
	var I = 0;
	var n = 0;
	while(x[I]){
		if(x[I] == y[I]){
			n = n+1;
		}else{
			return 0;
		}
		I = I + 4;
	}
	if(y[I]){return 0;}
	else{return 1;}
}
