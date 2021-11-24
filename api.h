#ifndef API_H
#define API_H

#include <stdint.h>
#include <stddef.h>

struct thud_component {
	const char *name;
	size_t (*cbk)(uint8_t slot, const char *fmt, char *buf, size_t size);
};

struct event_handler {
	const char *event;
	void (*cbk)(void *data);
};

struct mod_info {
	const char *name;
	const char *version;
	const char **deps; // terminated by NULL
	const struct thud_component *thud_components; // terminated by { NULL, NULL }
	const struct event_handler *event_handlers; // terminated by { NULL, NULL }
};

#endif
