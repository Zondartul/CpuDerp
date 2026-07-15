extends Control
class_name TileText;

const scene_tile:PackedScene = preload("res://scenes/tile_text_tile.tscn")
const char_w:int = 9;
const char_h:int = 16;
const height:int = 512;
const width:int = 512;
const default_colFG:Color = Color(81/255.0,235/255.0,0);
const default_colBG:Color = Color(16/255.0,16/255.0,16/255.0);
var tiles:Array[Array];
var tile_texts:Array[Array];
var n_tiles_x:int;
var n_tiles_y:int;
var default_posX:int = 0;
var default_posY:int = 0;


# Called when the node enters the scene tree for the first time.
func _ready()->void:
	_init_tiles();
	#setChar("A", 1,1,Color.WHITE, Color.BLACK);
	#setChar("A");
	#setString("hello from tile_text");
	pass # Replace with function body.

func clear()->void:
	for ix in range(n_tiles_x):
		for iy in range(n_tiles_y):
			setChar("",ix,iy);

func _err_bad_pos(posX, posY)->void:
	print("GPU/tile_text: bad position argument ("+str(posX)+","+str(posY)+")")

func _is_valid_pos(pos:Vector2i)->bool:
	if((pos.x < 0) || (pos.x >= n_tiles_x)): _err_bad_pos(pos.x, pos.y); return false;
	if((pos.y < 0) || (pos.y >= n_tiles_y)): _err_bad_pos(pos.x, pos.y); return false;
	return true;
	
func _sanitize_coords(posX, posY)->Vector2i:
	if(posX == null): posX = default_posX;
	if(posY == null): posY = default_posY;
	#if((posX < 0) || (posX >= n_tiles_x)): _err_bad_pos(posX, posY); return Vector2i.ZERO;
	#if((posY < 0) || (posY >= n_tiles_y)): _err_bad_pos(posX, posY); return Vector2i.ZERO;
	return Vector2i(posX, posY);

func _advance_default_pos(v:Vector2i)->void:
	default_posX = v.x;
	default_posY = v.y;
	default_posX += 1;
	if(default_posX >= n_tiles_x):
		default_posX = 0;
		default_posY += 1;
		if(default_posY >= n_tiles_y):
			default_posY = 0;

func setString(S:String, posX = null, posY = null, colFG = null, colBG = null)->void:
	if not _is_valid_pos(Vector2i(posX, posY)): return;
	var coords:Vector2i = _sanitize_coords(posX, posY);
	#if coords == null: return;
	if colFG == null: colFG = default_colFG;
	if colBG == null: colBG = default_colBG;
	default_posX = coords.x;
	default_posY = coords.y;
	for c in S:
		setChar(c,null,null,colFG,colBG);

func setChar(C:String, posX = null, posY = null, colFG = null, colBG = null)->void:
	var coords:Vector2i = _sanitize_coords(posX, posY);
	if not _is_valid_pos(coords): return;
	#if coords == null: return;
	if colFG == null: colFG = default_colFG;
	if colBG == null: colBG = default_colBG;
	
	tiles[coords.x][coords.y].color = colBG;
	tile_texts[coords.x][coords.y].add_theme_color_override("font_color", colFG);#.font_color = colFG;
	tile_texts[coords.x][coords.y].text = C.substr(0,1);
	_advance_default_pos(coords);
	
func _init_tiles()->void:
	tiles = [];
	tile_texts = [];
	@warning_ignore("integer_division")
	n_tiles_x = width/char_w; #note: // is not available in GDScript
	@warning_ignore("integer_division")
	n_tiles_y = height/char_h;
	@warning_ignore("integer_division")
	var offset:Vector2i = Vector2i(width % char_w, height % char_h) / 2;
	#print("num tiles: ("+str(n_tiles_x)+", "+str(n_tiles_y)+")");
	for ix in range(n_tiles_x):
		var row:Array[Node] = []
		var texts_row:Array[Node] = []
		for iy in range(n_tiles_y):
			var x:int = char_w*ix;
			var y:int = char_h*iy;
			var tile:Node = scene_tile.instantiate();
			var tile_text:Node = tile.get_node("tile_text");
			tile_text.text = "";
			tile.position = Vector2(x,y) + Vector2(offset);
			add_child(tile);
			row.append(tile);
			texts_row.append(tile_text);
		tiles.append(row);
		tile_texts.append(texts_row);

class CSTileData:
	var c:String;
	var colFG:Color;
	var colBG:Color;
	func _init(_c:String="",_colFG:Color=Color.WHITE,_colBG:Color = Color.BLACK):
		c = _c;
		colFG = _colFG;
		colBG = _colBG;
	static var none:CSTileData = CSTileData.new("");

func getTileData(pos:Vector2i)->CSTileData:
	if not _is_valid_pos(pos): return CSTileData.none;
	var coords:Vector2i = _sanitize_coords(pos.x, pos.y);
	#if coords == null: return null;
	var C:String = tile_texts[coords.x][coords.y].text;
	var colFG:Color = tile_texts[coords.x][coords.y].get_theme_color("font_color");
	var colBG:Color = tiles[coords.x][coords.y].color;
	return CSTileData.new(C,colFG,colBG);

func setTileData(pos:Vector2i, tile_data)->void:
	if not _is_valid_pos(pos): return;
	var coords:Vector2i = _sanitize_coords(pos.x, pos.y);
	#if coords == null: return;
	#print("setTileData(coords = "+str(coords)+", data = "+str(tile_data)+")");
	tile_texts[coords.x][coords.y].text = tile_data.c;
	tile_texts[coords.x][coords.y].add_theme_color_override("font_color", tile_data.colFG);
	tiles[coords.x][coords.y].color = tile_data.colBG;

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
