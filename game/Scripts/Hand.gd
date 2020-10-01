# open-tabletop
# Copyright (c) 2020 Benjamin 'drwhut' Beddows
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

extends Spatial

onready var _area = $Area
onready var _area_collision_shape = $Area/CollisionShape

const CARD_HEIGHT_DIFF = 0.01

var _srv_cards = []

# Add a card to the hand. The card must not be hovering, as the operation makes
# the card hover.
# Returns: If the operation was successful.
# card: The card to add to the hand.
func srv_add_card(card: Card) -> bool:
	var init_pos = _area.global_transform.origin
	var success = card.srv_start_hovering(owner_id(), init_pos, Vector3.ZERO)
	if success:
		# TODO: Figure out which position the card should be in based on its
		# position.
		_srv_cards.append(card)
		_srv_set_card_positions()
		
		card.connect("client_set_hover_position", self, "_on_client_set_card_position")
		
		# Make sure the cards in the hand don't collide with each other.
		card.collision_mask = 2
		
		# Set the rotation of the card to be in line with the hand.
		var new_basis = transform.basis
		if card.transform.basis.y.y < 0:
			new_basis = new_basis.rotated(transform.basis.z, PI)
		card.srv_hover_basis = new_basis
	return success

# Remove all cards from the hand. This does not stop the cards from hovering.
func srv_clear_cards() -> void:
	for i in range(_srv_cards.size() - 1, -1, -1):
		srv_remove_card(_srv_cards[i])

# Remove a card from the hand. This does not stop the card from hovering.
# card: The card to remove from the hand.
func srv_remove_card(card: Card) -> void:
	_srv_cards.erase(card)
	_srv_set_card_positions()
	
	card.disconnect("client_set_hover_position", self, "_on_client_set_card_position")
	
	card.collision_mask = 1

# Get the ID of the player who owns this hand. The ID is based of the name of
# the node.
# Returns: The player's ID.
func owner_id() -> int:
	return int(name)

# Set the hover positions of the hand's cards.
func _srv_set_card_positions() -> void:
	if _srv_cards.size() == 0:
		return
	
	var total_width = 0
	var widths = []
	for card in _srv_cards:
		var card_width = card.piece_entry["scale"].x
		total_width += card_width
		widths.append(card_width)
	
	var hand_width = _area_collision_shape.scale.x
	var offset_begin = max((hand_width-total_width) / 2, 0) + (widths[0] / 2)
	var offset_other = 0
	if _srv_cards.size() > 1:
		offset_other = min((hand_width-total_width) / (_srv_cards.size()-1), 0)
	
	var dir = _area.global_transform.basis.x
	if total_width > hand_width:
		dir.y += CARD_HEIGHT_DIFF
		dir = dir.normalized()
	var origin = _area.global_transform.origin - dir * (hand_width / 2)
	
	_srv_cards[0].srv_hover_position = origin + dir * offset_begin
	
	var cumulative_width = widths[0]
	for i in range(1, _srv_cards.size()):
		var k = offset_begin + cumulative_width + offset_other
		_srv_cards[i].srv_hover_position = origin + dir * k
		
		cumulative_width += widths[i] + offset_other

func _on_Area_body_entered(body: Node):
	if body.get("over_hand") != null:
		body.over_hand = owner_id()

func _on_Area_body_exited(body: Node):
	if body.get("over_hand") != null:
		body.over_hand = 0

func _on_client_set_card_position(card: Card):
	srv_remove_card(card)
