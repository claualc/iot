
/*
*	IMPORTANT:
*	The code will be avaluated based on:
*		Code design  
*
*/
 
 
#include "Timer.h"
#include "RadioRoute.h"


module RadioRouteC @safe() {
  uses {
    /****** INTERFACES *****/
    interface Boot;
    //interface for LED
    interface Leds;
    //interface for timers
    interface Timer<TMilli> as Timer0;
    //interfaces for communication
    interface SplitControl as AMControl;
    interface AMSend;
    interface Receive;
    //other interfaces, if needed
    interface Packet;
  }
}
implementation {

  message_t packet;
  
  // Variables to store the message to send
  message_t queued_packet;
  uint16_t queue_addr;
  uint16_t time_delays[7]={61,173,267,371,479,583,689}; //Time delay in milli seconds
  
  /*****  ROUTER VARIABLES  *****/
  bool route_req_sent=FALSE;
  bool route_rep_sent=FALSE;
  
  
  bool locked;
  
  bool actual_send (uint16_t address, message_t* packet);
  bool generate_send (uint16_t address, message_t* packet, uint8_t type);
  
  bool generate_send (uint16_t address, message_t* packet, uint8_t type){
  /*
  * 
  * Function to be used when performing the send after the receive message event.
  * It store the packet and address into a global variable and start the timer execution to schedule the send.
  * It allow the sending of only one message for each REQ and REP type
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

 /****** EVENTS *****/
  event void Boot.booted() {
    dbg("boot","\nNode booted %d.\n\n",TOS_NODE_ID);
    call AMControl.start();
  }

  event void AMControl.startDone(error_t err) {
    if (err == SUCCESS) {
      dbg("radio","\nRadio on on node %d!\n\n", TOS_NODE_ID);
      call Timer0.startPeriodic(250);
    }
    else {
      dbgerror("radio", "\nRadio failed to start, retrying...\n\n");
      call AMControl.start();
    }
  }
  
  event void Timer0.fired() {
  	/*
  	* MANDATORY: DO NOT MODIFY THIS FUNCTION
  	*/
  	actual_send (queue_addr, &queued_packet);
  }
  
  bool actual_send (uint16_t address, message_t* packet){
    radio_route_msg_t* msg = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
    if (msg == NULL) {
		  return;
    }
    msg->value = 253;
    if (call AMSend.send(1, &packet, sizeof(radio_route_msg_t)) == SUCCESS) {
		  dbg("radio_send", "\n..::AMSend.send -> FIRST READY");	
    }
  }

  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
			dbg("radio_send", "\n..::AMSend.sendDone -> PACKET SENT\n\n");	
  }

  event void AMControl.stopDone(error_t err) {
    dbg("boot", "\nRadio stopped!\n");
  }
  
  event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
     dbg("radio_rec", "..::Receive.receive len= ",sizeof(radio_route_msg_t));
    if (len != sizeof(radio_route_msg_t)) {
      dbg("radio_rec", "..::Receive.receive: ERROR: length of buffer incorrect\n");
      return bufPtr;
      }
    else {
      radio_route_msg_t* msg = (radio_route_msg_t*)payload;
      
      dbg("radio_rec", "..::Receive.receive: value %d\n",msg->value);

      return bufPtr;
    }

    
  }

}




