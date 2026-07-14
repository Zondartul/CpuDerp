extends Node

@export var font:Font

var screen:Node = null;
@onready var n_viewport:SubViewport = $SubViewport
@onready var scr_text:Node = $SubViewport/GPU_scene/tile_text;
var is_setup:bool = false;

var debug_gpu:bool = false;

var Img:Texture = null;
var width:int = 0;
var height:int = 0;
var n_tiles_x:int = 56;
var n_tiles_y:int = 36;
var update_queued:bool = false;
const n_tile_params:int = 1+3+3; # char, color, color
const READ_RETURNS_BUFFER:int = true;
var mem:Array[int] = [];

# Called when the node enters the scene tree for the first time.
func _ready()->void:
	mem.resize(getSize());
	pass # Replace with function body.

func getSize()->int:
	return 2000 + n_tile_params*n_tiles_x*n_tiles_y;

func setup(dict:Dictionary)->void:
	assert("screen" in dict);
	screen = dict.screen;
	is_setup = true;
	init_screen();
	scr_clear();
	#scr_print("hello from GPU");
	#update_screen();

func reset()->void:
	scr_clear();
	update_screen();

func _rand_scr_pos()->Vector2i:
	return Vector2i(randi_range(0,55),randi_range(0,35));

func _rand_scr_edge_pos()->Vector2i:
	var edge_idx:int = randi_range(1,4);
	var pos:Vector2i = _rand_scr_pos();
	if(edge_idx == 1): pos.x = 0;
	if(edge_idx == 2): pos.y = 0;
	if(edge_idx == 3): pos.x = 55;
	if(edge_idx == 4): pos.y = 35;
	#print("rsep: idx "+str(edge_idx)+", pos "+str(pos));
	return pos;

func _is_in_scr(v:Vector2i)->bool:
	return Rect2i(0,0,56,36).has_point(v);

func _screensaver_matrix()->void:
	var ch:String =  String.chr(randi_range(0,255));
	if(randf_range(0,1) < 0.9): ch = " ";
	var pos:Vector2i = _rand_scr_pos();
	scr_print(ch,pos.x,pos.y);


class NyanItem:
	var pos:Vector2i;
	var dir:int;
	var phase:int;
	func _init(_pos:Vector2i,_dir:int,_phase:int):
		pos=_pos;dir=_dir;phase=_phase;

var nyan_array:Array[NyanItem] = [];
const nyan_colors:Array[Color] = [
	Color.RED, Color.ORANGE, Color.YELLOW, Color.GREEN, Color.CYAN, Color.BLUE, Color.PURPLE];
const nyan_dirs:Array[Vector2i] = [
	Vector2i(0,1), Vector2i(1,1), Vector2i(1,0), Vector2i(1,-1), Vector2i(0,-1), Vector2i(-1,-1), Vector2i(-1,0), Vector2i(-1,1)];
#         0.N            1.NE          2.E           3.SE            4.S             5.SW              6.W             7.NW

func _screensaver_nyan()->void:
	if(nyan_array.size() < 3):
		# new nyan
		var pos:Vector2i = _rand_scr_edge_pos();
		var dir:int = randi_range(0,7);
		if not _is_in_scr(pos+nyan_dirs[dir]): dir = (dir + 4)%8;
		var nyan:NyanItem = NyanItem.new(pos,dir,0);
		nyan_array.append(nyan);
	for nyan in nyan_array:
		if nyan.phase == 1:
			var pos2:Vector2i = nyan.pos + nyan_dirs[nyan.dir];
			if(_is_in_scr(pos2)):
				var next_nyan:NyanItem = NyanItem.new(pos2,nyan.dir,0);
				nyan_array.append(next_nyan);
		if nyan.phase == 7:
			scr_print(' ', nyan.pos.x, nyan.pos.y);
			nyan_array.erase(nyan);
		else:
			scr_print(' ', nyan.pos.x, nyan.pos.y, null, nyan_colors[nyan.phase]);
		nyan.phase += 1;

class TileAddr:
	var pos:Vector2i;
	var sub_addr:int;
	func _init(_pos:Vector2i,_sub_addr:int):
		pos=_pos;sub_addr=_sub_addr;

func _calc_tile_addr(adr:int)->TileAddr:
	assert(adr >= 2000);
	adr -= 2000;
	var sub_addr:int = adr % n_tile_params;
	@warning_ignore("integer_division")
	var scr_pos:int = (adr - sub_addr) / n_tile_params;
	var scr_x:int = scr_pos % n_tiles_x;
	@warning_ignore("integer_division")
	var scr_y:int = (scr_pos - scr_x) / n_tiles_x;
	if(scr_y > n_tiles_y): return null;
	assert((scr_x >= 0) && (scr_x <= n_tiles_x));
	assert((scr_y >= 0) && (scr_y <= n_tiles_y));
	var vpos:Vector2i = Vector2i(scr_x, scr_y);
	return TileAddr.new(vpos, sub_addr);

func _char_to_int(C:String)->int:
	if(C == ""): return 0;
	else: return C.to_ascii_buffer()[0];
	
func _int_to_char(N:int)->String:
	if(N == 0): return "";
	else: return PackedByteArray([N]).get_string_from_ascii();

func _set_tile_param(tile_data:TileText.CSTileData, sub_addr:int, val:int)->void:
	match(sub_addr):
		0: tile_data.c = _int_to_char(val)
		1: tile_data.colFG.r = int(val/255.0);
		2: tile_data.colFG.g = int(val/255.0);
		3: tile_data.colFG.b = int(val/255.0);
		4: tile_data.colBG.r = int(val/255.0);
		5: tile_data.colBG.g = int(val/255.0);
		6: tile_data.colBG.b = int(val/255.0);

func _get_tile_param(tile_data:TileText.CSTileData, sub_addr)->int:
	var res:int = 0;
	match(sub_addr):
		0: res = _char_to_int(tile_data.c);
		@warning_ignore("narrowing_conversion")
		1: res = tile_data.colFG.r*255;
		@warning_ignore("narrowing_conversion")
		2: res = tile_data.colFG.g*255;
		@warning_ignore("narrowing_conversion")
		3: res = tile_data.colFG.b*255;
		@warning_ignore("narrowing_conversion")
		4: res = tile_data.colBG.r*255;
		@warning_ignore("narrowing_conversion")
		5: res = tile_data.colBG.g*255;
		@warning_ignore("narrowing_conversion")
		6: res = tile_data.colBG.b*255;
	return res;
	
func writeCell(adr:int, val:int)->void:
	if(debug_gpu):print("GPU: writeCell("+str(adr)+") <- "+str(val));
	#print("writeCell("+str(adr)+", "+str(val)+")");
	if adr >= 2000:
		mem[adr] = val;
		# write framebuffer or textbuffer data
		var ref:TileAddr = _calc_tile_addr(adr);
		if ref == null: return;
		#print("ref = (pos "+str(ref.pos)+", sub "+str(ref.sub_addr)+")");
		
		var tile_data:TileText.CSTileData = scr_text.getTileData(ref.pos);
		_set_tile_param(tile_data, ref.sub_addr, val);
		scr_text.setTileData(ref.pos, tile_data);
		update_queued = true;


func readCell(adr:int)->int:
	if adr >= 2000:
		if READ_RETURNS_BUFFER:
			return mem[adr];
		else:
			# read framebuffer or textbuffer
			var ref:TileAddr = _calc_tile_addr(adr);
			if ref == null: return 0;
			
			var tile_data:TileText.CSTileData = scr_text.getTileData(ref.pos);
			var val:int = _get_tile_param(tile_data, ref.sub_addr);
			#if val == null: val = 0;
			return val;
	return 0;

func _process(_delta)->void:
	#for i in range(20):
	#	_screensaver_matrix();
	#for i in range(3):
	#	_screensaver_nyan();
	#update_screen();
	if update_queued:
		update_queued = false;
		update_screen();
	pass

func init_screen()->void:
	screen.texture = n_viewport.get_texture();
	#also see ImageTexture.update(Img)

func update_screen()->void:
	n_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE;
	#screen.queue_redraw();

func scr_clear()->void:
	scr_text.clear();

func scr_print(text:String, posX=null, posY=null, colFG=null, colBG=null)->void:
	#scr_text.text = text;
	scr_text.setString(text, posX, posY, colFG, colBG);
	pass;
