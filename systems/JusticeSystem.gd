class_name JusticeSystem
extends Node

# Violence tracking, lives, and escalation system

const CORES_PER_STRIKE: int = 3
const STARTING_LIVES: int = 2

var cores_squished: int = 0
var violence_level: int = 0
var lives: int = STARTING_LIVES
var is_game_over: bool = false

# Stats for game over screen
var total_cores_squished: int = 0
var total_people_broken: int = 0

signal core_squished(total_squished: int, cores_until_strike: int)
signal violence_escalated(new_level: int, lives_remaining: int)
signal life_lost(lives_remaining: int)
signal game_over()


func report_core_squished():
	cores_squished += 1
	total_cores_squished += 1

	var remaining = CORES_PER_STRIKE - cores_squished
	core_squished.emit(cores_squished, remaining)
	print("CORE SQUISHED! %d/%d until strike. Violence level: %d" % [cores_squished, CORES_PER_STRIKE, violence_level])

	if cores_squished >= CORES_PER_STRIKE:
		cores_squished = 0
		violence_level += 1
		lives -= 1

		violence_escalated.emit(violence_level, lives)
		life_lost.emit(lives)

		if lives <= 0:
			is_game_over = true
			game_over.emit()
			print("GAME OVER - too much violence")
		else:
			print("STRIKE %d! Car destroyed. Lives remaining: %d" % [violence_level, lives])


func report_person_broken():
	total_people_broken += 1


func reset():
	cores_squished = 0
	violence_level = 0
	lives = STARTING_LIVES
	is_game_over = false
	total_cores_squished = 0
	total_people_broken = 0
