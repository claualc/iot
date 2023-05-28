
/*
*	IMPORTANT:
*	The code will be evaluated based on:
*		Code design  
*
*/
 
 
#include "Timer.h"
#include "RadioRoute.h"


module RadioRouteC @safe() {
  uses {
  
    /****** INTERFACES *****/
	interface Boot;

    //interfaces for communication
    interface Receive;
    interface AMSend;
    interface SplitControl as AMControl;
    
	//interface for timers
	interface Timer<TMilli> as Timer0;
	interface Timer<TMilli> as Timer1;
	
	//interface Timer<TMilli> as Timer2;
	
	//interface for LED
	interface Leds;
	
    //other interfaces, if needed
    interface Packet;
  }
}
implementation {

  message_t packet;
  message_t packet_new;
  
  // Variables to store the message to send
  message_t queued_packet;
  uint16_t queue_addr;
  uint16_t time_delays[7]={61,173,267,371,479,583,689}; //Time delay in milli seconds
  
  // Flags for flow control
  bool route_req_sent=FALSE;
  bool route_rep_sent=FALSE;
  bool data_sent=FALSE; //To sent once the DATA packet (type 0) from node 1 to node 7
  bool timer1_fired=FALSE; //To sent once the ROUTE REQUEST packet (type 1) from node 1
   
  bool locked;
  
  //Variables to store the routing table info
  uint16_t rt_dst[7] = {};
  uint16_t rt_next_hop[7] = {};
  uint16_t rt_cost[7] = {};
  
  // Custom variables
  uint16_t counter = 0; //To index the person code
  uint16_t person_code[8] = {1,0,8,3,2,7,0,4};
  uint16_t led_index, led0, led1, led2;
  
  // Functions to control the logic behind the sending procedure  
  bool actual_send (uint16_t address, message_t* packet);
  bool generate_send (uint16_t address, message_t* packet, uint8_t type);
  
  // Custom functions
  void leds_mngmnt();
  void printRoutingTable(); 
  
  bool generate_send (uint16_t address, message_t* packet, uint8_t type){
  /*
  * 
  * Function to be used when performing the send after the receive message event.
  * It stores the packet and address into a global variable and start the timer execution to schedule the send.
  * It allows the sending of only one message for each REQ and REP type
  * @Input:
  *		address: packet destination address
  *		packet: full packet to be sent (Not only Payload)
  *		type: payload message type
  *
  * MANDATORY: DO NOT MODIFY THIS FUNCTION
  */
  
  	if (call Timer0.isRunning()){
  		return FALSE;
  	}else{
  	if (type == 1 && !route_req_sent ){
  		route_req_sent = TRUE;
  		call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
  		queued_packet = *packet;
  		queue_addr = address;
  	}else if (type == 2 && !route_rep_sent){
  	  	route_rep_sent = TRUE;
  		call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
  		queued_packet = *packet;
  		queue_addr = address;
  	}else if (type == 0){
  		call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
  		queued_packet = *packet;
  		queue_addr = address;	
  	}
  	}
  	return TRUE;
  }
  
  void leds_mngmnt() {
  	led_index = person_code[counter] % 3;
  	
	if (led_index == 0) {
		call Leds.led0Toggle();
    }
    else if (led_index == 1) {
		call Leds.led1Toggle();
    }
    else if (led_index == 2) {
		call Leds.led2Toggle();
    }
    
    //Led statuses
  	if((call Leds.get() & LEDS_LED0) == 0) {led0 = 0;}
  	else {led0 = 1;}
  	if((call Leds.get() & LEDS_LED1) == 0) {led1 = 0;}
  	else {led1 = 1;}
  	if((call Leds.get() & LEDS_LED2) == 0) {led2 = 0;}
  	else {led2 = 1;}
    
    
    if (TOS_NODE_ID == 6) {
    	dbg("led_status", "Led status node 6 is: %u%u%u\n", led0, led1, led2);
    }
    
    counter++;
    
    // Reseting idx of person code
    if (counter >= 8) {
    	counter = 0;
    }
    
  }
  
  event void Timer0.fired() {
  	/*
  	* Timer triggered to perform the send.
  	* MANDATORY: DO NOT MODIFY THIS FUNCTION
  	*/
  	if (queue_addr!=0) {
	  	actual_send (queue_addr, &queued_packet);
  	}
  }
  
  bool actual_send (uint16_t address, message_t* packet){
	/*
	* Implement here the logic to perform the actual send of the packet using the tinyOS interfaces
	*/
	radio_route_msg_t* rrm = (radio_route_msg_t*)call Packet.getPayload(packet, sizeof(radio_route_msg_t));
	radio_route_msg_t* rrm_new = (radio_route_msg_t*)call Packet.getPayload(&packet_new, sizeof(radio_route_msg_t));
    if (locked) {
      //dbg("radio_send", "Packet canceled because LOCKED");
      return FALSE;
    }
    else {
      
      if (rrm == NULL) {
        //dbg("radio_send", "Packet canceled because rrm is NULL");
		return FALSE;
      }
      
      if (call AMSend.send(address, packet, sizeof(radio_route_msg_t)) == SUCCESS) {
		locked = TRUE;
		if (rrm->type == 0){
			dbg("radio_send", "Packet ACTUALLY SENT struct is: type %u, sender %u, destination %u, value %u at time %s\n", rrm->type, rrm->sender, rrm->destination, rrm->value, sim_time_string());
		} else if (rrm->type == 1){
			dbg("radio_send", "Packet ACTUALLY SENT struct is: type %u, node_requested %u at time %s\n", rrm->type, rrm->node_requested, sim_time_string());
		} else if (rrm->type == 2){
			dbg("radio_send", "Packet ACTUALLY SENT struct is: type %u, sender %u, node_requested %u, cost %u at time %s\n", rrm->type, rrm->sender, rrm->node_requested, rrm->cost, sim_time_string());
			
			// if TOS_NODE == 1 and first reply received, send the data packet
		    if (rrm->node_requested == 7 && TOS_NODE_ID == 1 && data_sent==FALSE) {
		    	data_sent=TRUE;
				rrm_new->type = 0;
				rrm_new->sender = TOS_NODE_ID;
				rrm_new->destination = 7;
				rrm_new->value = 5;
				dbg("radio_send", "Packet TO BE SENT struct is: type %u, sender %u, destination %u, value %u\n", rrm_new->type, rrm_new->sender, rrm_new->destination, rrm_new->value);
				generate_send (rt_next_hop[rrm_new->destination-1], &packet_new, 0);
           }						
	    }
	    return TRUE;
	  }
    }
   }
      
  

  
  event void Boot.booted() {
    dbg("boot","Application booted.\n");
    /* Fill it ... */
    call AMControl.start();
  }

  event void AMControl.startDone(error_t err) {
	/* Fill it ... */
	if (err == SUCCESS) {
      dbg("radio","Radio ON on node %d!\n", TOS_NODE_ID);
      //call MilliTimer.startPeriodic(250);////////////////////////////////////
      if (TOS_NODE_ID == 1) {
      	call Timer1.startOneShot(5000);
      }
    }
    else {
      dbgerror("radio", "Radio failed to start, retrying...\n");
      call AMControl.start();
    }
  }

  event void AMControl.stopDone(error_t err) {
    /* Fill it ... */
    dbg("boot", "Radio stopped!\n");
  }
  
  event void Timer1.fired() {
	/*
	* Implement here the logic to trigger the Node 1 to send the first REQ packet
	*/
		
	if (TOS_NODE_ID == 1 && timer1_fired == FALSE) {
		radio_route_msg_t* rrm = (radio_route_msg_t*) call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
		timer1_fired = TRUE;
		rrm->type = 1;
		rrm->node_requested = 7;
		dbg("radio_send", "Packet TO BE SENT struct is: type %u, node_requested %u\n", rrm->type, rrm->node_requested);
		generate_send (AM_BROADCAST_ADDR, &packet, 1);
	} 
  }

  event message_t* Receive.receive(message_t* bufPtr, 
				   void* payload, uint8_t len) {
	/*
	* Parse the receive packet.
	* Implement all the functionalities
	* Perform the packet send using the generate_send function if needed
	* Implement the LED logic and print LED status on Debug
	*/
	if (len != sizeof(radio_route_msg_t)) {return bufPtr;}
    else {
         
      // declaring received packet
      radio_route_msg_t* rrm_rec = (radio_route_msg_t*)payload;
      // declaring created packet
      radio_route_msg_t* rrm = (radio_route_msg_t*) call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
      
      // For every message received change the state of the Leds
	  leds_mngmnt ();
      
      dbg("radio_rec", "Received packet of type %u at time %s\n", rrm_rec->type, sim_time_string());
      
      // Handling DATA packet (Type 0 msg)
      if (rrm_rec->type == 0) {
       dbg("radio_rec", "Packet RECEIVED struct is: type %u, sender %u, destination %u, value %u\n", rrm_rec->type, rrm_rec->sender, rrm_rec->destination, rrm_rec->value);
       if (rrm_rec->destination == TOS_NODE_ID) {
       }
       // Check Routing Table for defining next hop
       else if (rt_dst[rrm_rec->destination-1] == rrm_rec->destination) {
        dbg("radio_send", "Packet TO BE SENT struct is: type %u, sender %u, destination %u, value %u\n", rrm_rec->type, rrm_rec->sender, rrm_rec->destination, rrm_rec->value);
       	generate_send (rt_next_hop[rrm_rec->destination-1], bufPtr, 0);
       }
      }
      // Handling ROUTE REQUEST packet (Type 1 msg)
      else if (rrm_rec->type == 1) {
      	dbg("radio_rec", "Packet RECEIVED struct is: type %u, node_requested %u\n", rrm_rec->type, rrm_rec->node_requested);
      	// I am the node requested
      	if (rrm_rec->node_requested == TOS_NODE_ID) {
			rrm->type = 2;
			rrm->sender = TOS_NODE_ID;
			rrm->node_requested = TOS_NODE_ID;
			rrm->cost = 1;
      		dbg("radio_send", "Packet TO BE SENT struct is: type %u, sender %u, node_requested %u, cost %u\n", rrm->type, rrm->sender, rrm->node_requested, rrm->cost);
      		generate_send (AM_BROADCAST_ADDR, &packet, 2);
      	}
      	// Node requested IS NOT me AND NOT in my routing table
      	else if (rrm_rec->node_requested != TOS_NODE_ID && rt_dst[rrm_rec->node_requested-1] != rrm_rec->node_requested) {
      		dbg("radio_send", "Packet TO BE SENT struct is: type %u, node_requested %u\n", rrm_rec->type, rrm_rec->node_requested);
      		generate_send(AM_BROADCAST_ADDR, bufPtr, 1);
      	} 
      	
      	// Node requested is in my routing table
      	else if (rt_dst[rrm_rec->node_requested-1] == rrm_rec->node_requested) {
			rrm->type = 2;
			rrm->sender = TOS_NODE_ID;
			rrm->node_requested = rrm_rec->node_requested;
			rrm->cost = rrm_rec->node_requested+1;
			dbg("radio_send", "Packet TO BE SENT struct is: type %u, sender %u, node_requested %u, cost %u\n", rrm->type, rrm->sender, rrm->node_requested, rrm->cost);
			
			generate_send (AM_BROADCAST_ADDR, &packet, 2);
        } 
      } 
      // Handling ROUTE REPLY packet (Type 2 msg)
      else if (rrm_rec->type == 2) {
      	dbg("radio_rec", "Packet RECEIVED struct is: type %u, sender %u, node_requested %u, cost %u\n", rrm_rec->type, rrm_rec->sender, rrm_rec->node_requested, rrm_rec->cost);
      	// If I am the requested node in the reply, do nothing
      	if (rrm_rec->node_requested == TOS_NODE_ID) {}
      	// My table does not have entry or if the new cost is lower than my current cost
      	else if (rt_dst[rrm_rec->node_requested-1] != rrm_rec->node_requested || rrm_rec->cost < rt_cost[rrm_rec->node_requested-1]) {
      		// Update routing table
			rt_dst[rrm_rec->node_requested-1] = rrm_rec->node_requested;
			rt_next_hop[rrm_rec->node_requested-1] = rrm_rec->sender;
			rt_cost[rrm_rec->node_requested-1] = rrm_rec->cost;
			
			printRoutingTable();
						
      		// Send modified route reply
			rrm->type = 2;
			rrm->sender = TOS_NODE_ID;
			rrm->node_requested = rrm_rec->node_requested;
			rrm->cost = rrm_rec->cost+1;
			dbg("radio_send", "Packet TO BE SENT struct is: type %u, sender %u, node_requested %u, cost %u\n", rrm->type, rrm->sender, rrm->node_requested, rrm->cost);
			generate_send (AM_BROADCAST_ADDR, &packet, 2);
        }
        else {}
        
      }
    	
	return bufPtr;
	
    }
  }
  
  
  void printRoutingTable() {
	  /*
	  * Function to be used to print the Routing Table of the current node.
	  */

	uint16_t i;

	// List with destinations. Each value corresponds to the destination node address (1-7). 
	for (i = 0; i < 7; i++) {
		if (i < 6) dbg("radio", "%d ", rt_dst[i]);
		else if (i == 6) dbg("radio", "%d\n", rt_dst[i]);
	}
	
	// List with next hops. The index+1 corresponds to the node we want to reach and the value is the address of the node to use as next hop.
	for (i = 0; i < 7; i++) {
		if (i < 6) dbg("radio", "%d ", rt_next_hop[i]);
		else if (i == 6) dbg("radio", "%d\n", rt_next_hop[i]);
	}
	// List with costs. The index+1 corresponds to the node we want to reach and the value is the cost to reach it.
	for (i = 0; i < 7; i++) {
		if (i < 6) dbg("radio", "%d ", rt_cost[i]);
		else if (i == 6) dbg("radio", "%d\n", rt_cost[i]);
	}

    }
	
  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
	/* This event is triggered when a message is sent 
	*  Check if the packet is sent 
	*/ 
	if (&queued_packet == bufPtr) {
      locked = FALSE;
    }
  }
}




