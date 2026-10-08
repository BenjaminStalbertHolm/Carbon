extends RefCounted
## Debug guard (spec 21). Every debug entry point checks enabled() first. True only in debug builds
## (editor runs and debug templates); release exports never reach a debug path.

static func enabled() -> bool:
	return OS.is_debug_build()
