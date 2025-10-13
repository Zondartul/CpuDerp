extends Control

const scene_tile = preload("res://scenes/tile_text_tile.tscn")
const char_w = 9;
const char_h = 16;
const height = 512;
const width = 512;
const default_colFG = Color(81/255.0,235/255.0,0);
const default_colBG = Color(16/255.0,16/255.0,16/255.0);
var tiles;
var tile_texts;
var n_tiles_x;
var n_tiles_y;
var default_posX = 0;
var default_posY = 0;


# Called when the node enters the scene tree for the first time.
func _ready():
	_init_tiles();
	#setChar("A", 1,1,Color.WHITE, Color.BLACK);
	#setChar("A");
	#setString("hello from tile_text");
	pass # Replace with function body.

func clear():
	for ix in range(n_tiles_x):
		for iy in range(n_tiles_y):
			setChar("",ix,iy);

func _err_bad_pos(posX, posY):
	print("GPU/tile_text: bad position argument ("+str(posX)+","+str(posY)+")")

func _sanitize_coords(posX, posY):
	if(posX == null): posX = default_posX;
	if(posY == null): posY = default_posY;
	if((posX < 0) || (posX >= n_tiles_x)): _err_bad_pos(posX, posY); return null;
	if((posY < 0) || (posY >= n_tiles_y)): _err_bad_pos(posX, posY); return null;
	return Vector2i(posX, posY);

func _advance_default_pos(v:Vector2i):
	default_posX = v.x;
	default_posY = v.y;
	default_posX += 1;
	if(default_posX >= n_tiles_x):
		default_posX = 0;
		default_posY += 1;
		if(default_posY >= n_tiles_y):
			default_posY = 0;

func setString(S:String, posX = null, posY = null, colFG = null, colBG = null):
	var coords = _sanitize_coords(posX, posY);
	if coords == null: return;
	if colFG == null: colFG = default_colFG;
	if colBG == null: colBG = default_colBG;
	default_posX = coords.x;
	default_posY = coords.y;
	for c in S:
		setChar(c,null,null,colFG,colBG);

func setChar(C:String, posX = null, posY = null, colFG = null, colBG = null):
	var coords = _sanitize_coords(posX, posY);
	if coords == null: return;
	if colFG == null: colFG = default_colFG;
	if colBG == null: colBG = default_colBG;
	
	tiles[coords.x][coords.y].color = colBG;
	tile_texts[coords.x][coords.y].add_theme_color_override("font_color", colFG);#.font_color = colFG;
	tile_texts[coords.x][coords.y].text = C.substr(0,1);
	_advance_default_pos(coords);
	
func _init_tiles():
	tiles = [];
	tile_texts = [];
	@warning_ignore("integer_division")
	n_tiles_x = width/char_w; #note: // is not available in GDScript
	@warning_ignore("integer_division")
	n_tiles_y = height/char_h;
	var offset = Vector2i(width % char_w, height % char_h) / 2;
	#print("num tiles: ("+str(n_tiles_x)+", "+str(n_tiles_y)+")");
	for ix in range(n_tiles_x):
		var row = []
		var texts_row = []
		for iy in range(n_tiles_y):
			var x = char_w*ix;
			var y = char_h*iy;
			var tile = scene_tile.instantiate();
			var tile_text = tile.get_node("tile_text");
			tile_text.text = "";
			tile.position = Vector2(x,y) + Vector2(offset);
			add_child(tile);
			row.append(tile);
			texts_row.append(tile_text);
		tiles.append(row);
		tile_texts.append(texts_row);

func getTileData(pos:Vector2i):
	var coords = _sanitize_coords(pos.x, pos.y);
	if coords == null: return null;
	var C = tile_texts[coords.x][coords.y].text;
	var colFG = tile_texts[coords.x][coords.y].get_theme_color("font_color");
	var colBG = tiles[coords.x][coords.y].color;
	return {"c":C, "colFG":colFG, "colBG":colBG};

func setTileData(pos:Vector2i, tile_data):
	var coords = _sanitize_coords(pos.x, pos.y);
	if coords == null: return null;
	#print("setTileData(coords = "+str(coords)+", data = "+str(tile_data)+")");
	tile_texts[coords.x][coords.y].text = tile_data.c;
	tile_texts[coords.x][coords.y].add_theme_color_override("font_color", tile_data.colFG);
	tiles[coords.x][coords.y].color = tile_data.colBG;

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
