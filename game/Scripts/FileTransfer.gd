# tabletop-club
# Copyright (c) 2020-2022 Benjamin 'drwhut' Beddows.
# Copyright (c) 2021-2022 Tabletop Club contributors (see game/CREDITS.tres).
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

class_name FileTransfer
extends Node

const DOWNLOAD_DIR = "user://"

signal file_received(tmp_path, file_name, metadata)
signal received_send_request(sender_id, file_name, file_size, metadata)
signal send_request_accepted(peer_id)
signal send_request_denied(peer_id)

var _client_incoming_requests = {}
var _server_outgoing_requests = {}

var _send_thread = Thread.new()

# Request to send a file to another peer.
# id: The id of the peer to send the file to.
# file_path: The file path of the file to send.
func request_send_file(id: int, file_path: String, metadata = null) -> void:
	if not _server_outgoing_requests.has(id):
		var file = File.new()
		if file.file_exists(file_path):
			var file_name = file_path.get_file()
			
			file.open(file_path, File.READ)
			var file_size = file.get_len()
			file.close()
			
			rpc_id(id, "receive_send_request", file_name, file_size, metadata)
			var request = {
				"file_path": file_path,
				"metadata": metadata
			}
			_server_outgoing_requests[id] = request
		else:
			push_error("File '%s' does not exist!" % file_path)
	else:
		push_error("Already sent a request to peer %d!" % id)

# Called by a remote peer when they request to send a file.
# file_name: The name of the file.
# file_size: The size of the file in bytes.
# metadata: The metadata of the request.
remotesync func receive_send_request(file_name: String, file_size: int, metadata) -> void:
	if not file_name.is_valid_filename():
		push_error("Received file name (%s) is invalid!" % file_name)
		return
	
	if file_size < 0:
		push_error("Received file size (%d) is invalid!" % file_size)
		return
	
	var request = {
		"file_name": file_name,
		"file_size": file_size,
		"metadata": metadata
	}
	
	var sender_id = get_tree().get_rpc_sender_id()
	if _client_incoming_requests.has(sender_id):
		push_error("Already handling a request from peer %d!" % sender_id)
		decline_send_request(sender_id)
		return
	
	_client_incoming_requests[sender_id] = request
	
	emit_signal("received_send_request", sender_id, file_name, file_size, metadata)

# Accept the send request sent by the given peer.
# id: The id of the peer who sent the request.
func accept_send_request(id: int) -> void:
	if _client_incoming_requests.has(id):
		pass
	else:
		push_error("No record of send request from %d!" % id)

# Decline the send request sent by the given peer.
# id: The id of the peer who sent the request.
func decline_send_request(id: int) -> void:
	if _client_incoming_requests.has(id):
		_client_incoming_requests.erase(id)
	else:
		push_error("No record of send request from %d!" % id)

# Called by the peer if the send request was accepted.
remotesync func send_request_accepted() -> void:
	var id = get_tree().get_rpc_sender_id()
	if _server_outgoing_requests.has(id):
		emit_signal("send_request_accepted", id)
		_send_thread.start(self, "_send_file", {
			"file_path": _server_outgoing_requests["file_path"],
			"peer_id": id
		})
		_server_outgoing_requests.erase(id)

# Called by the peer if the send request was declined.
remotesync func send_request_denied() -> void:
	var id = get_tree().get_rpc_sender_id()
	if _server_outgoing_requests.has(id):
		_server_outgoing_requests.erase(id)
		emit_signal("send_request_denied", id)

# A threaded function to send the file to the client.
# data: A dictionary containing the file path and the recipient's ID.
func _send_file(data: Dictionary) -> void:
	# We let the packet layer split up the file.
	var file = File.new()
	file.open(data["file_path"], File.READ)
	var buffer = file.get_buffer(file.get_len())
	file.close()
	
	rpc_id(data["peer_id"], "_receive_file", buffer)

# A function called by the server when the file contents are sent.
# buffer: The contents of the file.
remotesync func _receive_file(buffer: PoolByteArray) -> void:
	var id = get_tree().get_rpc_sender_id()
	if _client_incoming_requests.has(id):
		var file = File.new()
		var file_path = DOWNLOAD_DIR + "/" + str(id)
		file.open(file_path, File.WRITE)
		file.store_buffer(buffer)
		file.close()
		
		var request = _client_incoming_requests[id]
		emit_signal("file_received", file_path, request["file_name"], request["metadata"])
		_client_incoming_requests.erase(id)
	else:
		push_error("Received a file from peer %d when we weren't expecting to!" % id)

func _exit_tree():
	_send_thread.wait_to_finish()
