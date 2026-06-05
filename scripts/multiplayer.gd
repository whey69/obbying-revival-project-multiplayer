extends Node

var peer = WebSocketMultiplayerPeer.new();
var timer = 0;
var target = "ws://127.0.0.1:9997" # temp
var port = 9997

var json = JSON.new()

func _ready():
	if GameManager.is_server:
		var err = peer.create_server(port)
		if err != OK:
			print("[server] failed to create server. ", err)
			return
		
		multiplayer.multiplayer_peer = peer
		print("[server] listening on port ", port)
		
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	else:
		var err = peer.create_client(target)
		if err != OK:
			print("[client] failed to create client: ", err)
			return
	
		multiplayer.multiplayer_peer = peer
		print("[client] connecting to server @ ", target)
	
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(delta):
	timer += 1;
	# send information 25 times a second
	if timer % (Engine.max_fps / 25) == 0:
		timer = 0
		if GameManager.is_server:
			# inject host player
			var player = $%Player
			positions[1] = {
				"pos": [player.position.x, player.position.y, player.position.z], 
				"rot": [player.rotation.x, player.rotation.y, player.rotation.z]
			}
			
			server_process(delta)
			message_upd(positions)
		else:
			client_process(delta)

### server

func _on_peer_connected(id):
	print("[server] peer connected id ", id)
	server_to_client.rpc_id(id, '{"id": "level", "level": "%s"}' % [GameManager.currentLevel])

func _on_peer_disconnected(id):
	print("[server] peer disconnected id ", id)
	positions.erase(id)

var positions = {}
func server_process(delta):
	for id in multiplayer.get_peers():
		#print("[server] ", id)
		# i guess were using positions for client query as well
		var data = {"id": "upd", "positions": positions}
		server_to_client.rpc_id(id, json.stringify(data))

@rpc("any_peer")
func client_to_server(_m):
	var sender_id = multiplayer.get_remote_sender_id()
	# print("[server] message from client %d: %s" % [sender_id, _m])
	var err = json.parse(_m)
	if err != OK:
		print("[server] failed to parse message from client ", sender_id)
		return
	
	var data = json.data
	if data["id"] == "pos":
		positions[sender_id] = {"pos": data["position"], "rot": data["rotation"]}

### client

func _on_connected_to_server():
	print("[client] connected")
	client_to_server.rpc_id(1, '{"id": "hello"}')

func _on_connection_failed():
	print("[client] failed to connect")

func _on_server_disconnected():
	print("[client] server disconnected")
	for i in get_children():
		i.query_free()

# todo: this should be handled in main_menu
func message_level(level):
	if GameManager.currentLevel != level:
		print("[client] changing level: %s -> %s" % [GameManager.currentLevel, level])
		GameManager.currentLevel = level
		
		multiplayer.multiplayer_peer.close()
		get_tree().change_scene_to_file("res://custom.tscn")
		if DiscordRPCManager != null:
			DiscordRPCManager.playing(GameManager.currentLevel)

var character_scene = preload("res://assets/character/Character.glb")
func message_upd(_positions):
	for id in _positions:
		if str(id) == str(multiplayer.get_unique_id()):
			continue
		var obj = get_node_or_null(str(id))
		if obj == null:
			obj = character_scene.instantiate()
			obj.name = str(id)
			obj.scale = Vector3(2, 2, 2)
			add_child(obj)
		
		var raw_pos = _positions[id]["pos"]
		var raw_rot = _positions[id]["rot"]
		obj.position = Vector3(raw_pos[0], raw_pos[1] + 1.5, raw_pos[2])
		obj.rotation = Vector3(raw_rot[0], raw_rot[1], raw_rot[2])
		
	for obj in get_children():
		if obj is MeshInstance3D && !((int(obj.name) in _positions) || (obj.name in _positions)):
			obj.queue_free()

@rpc("authority")
func server_to_client(_m):
	# print("[client] message from server: ", _m)
	var err = json.parse(_m)
	if err != OK:
		print("[client] failed to parse message")
		return
	var data = json.data
	if data["id"] == "level":
		message_level(data["level"])
	if data["id"] == "upd":
		message_upd(data["positions"])

func client_process(delta):
	var player = $%Player
	client_to_server.rpc_id(1, 
		'{"id": "pos", "position": [%f, %f, %f], "rotation": [%f, %f, %f]}' % [player.position[0], player.position[1], player.position[2], player.rotation[0], player.rotation[1], player.rotation[2]])
