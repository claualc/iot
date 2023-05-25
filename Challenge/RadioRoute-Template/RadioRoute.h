

#ifndef RADIO_ROUTE_H
#define RADIO_ROUTE_H

typedef nx_struct radio_route_msg {
	/*
	type: defines the message format
		0 - DATA MSG
		1 - ROUTE_REQ MSG
		2 - ROUTE_REPLY
	*/
	nx_uint16_t typpe;
	nx_uint16_t src;  // Sender
	nx_uint16_t dest; // Node Requested
	/*
	value: defines msg payload
	The meaning of the value attr changes 
	with the type of the msg:
		if DATA MSG  - led value
		if ROUTE_REQ - none
		if REPLY_REQ - hop_count
	*/
	nx_uint16_t value;
} radio_route_msg_t;

enum {
  AM_RADIO_COUNT_MSG = 10,
};

#endif
