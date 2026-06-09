extends Node

## Lightweight per-system frame-time accumulator for debug builds.
## Registered as an autoload so any script can call PerfTimer.begin/end
## without a node reference.
##
## Usage:
##   PerfTimer.begin("towers")
##   ... work ...
##   PerfTimer.end("towers")
##
## The debug overlay calls PerfTimer.flush() each update interval to read
## and reset all buckets. Overhead: two Time.get_ticks_usec() calls per pair.
## No-ops in release builds.

var _buckets: Dictionary = {}  # name -> { accum_us, start_us }
var _enabled: bool = false

func _ready() -> void:
	_enabled = OS.is_debug_build()

func begin(key: String) -> void:
	if not _enabled:
		return
	if not _buckets.has(key):
		_buckets[key] = { "accum_us": 0, "start_us": 0 }
	_buckets[key]["start_us"] = Time.get_ticks_usec()

func end(key: String) -> void:
	if not _enabled:
		return
	if not _buckets.has(key):
		return
	_buckets[key]["accum_us"] += Time.get_ticks_usec() - _buckets[key]["start_us"]

## Read and reset all buckets. Returns accumulated microseconds per name.
## Call once per overlay update interval.
func flush() -> Dictionary:
	var out: Dictionary = {}
	for k in _buckets:
		out[k] = _buckets[k]["accum_us"]
		_buckets[k]["accum_us"] = 0
	return out
