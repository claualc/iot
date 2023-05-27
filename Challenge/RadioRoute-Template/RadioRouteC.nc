
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
    interface Timer<TMilli> as Timer1;
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

  message_t waiting_packet;


  /*****  CONSTANTS  *****/
  uint16_t NODES_COUNT = 7;
  uint16_t DATA = 0;
  uint16_t ROUTE_REQ = 1;
  uint16_t ROUTE_REP = 2;

  /*****  ROUTING TABLE  *****/
  // the index of the arrays is the destination address
  uint16_t rt_next_hop[7]={NULL,NULL,NULL,NULL,NULL,NULL,NULL};
  uint16_t rt_hot_count[7]={NULL,NULL,NULL,NULL,NULL,NULL,NULL};
  
  /*****  ROUTER VARIABLES  *****/
  bool route_req_sent=FALSE;
  bool route_rep_sent=FALSE;
  
  bool locked;
  
  bool actual_send (uint16_t address, message_t* packet);
  bool generate_send (uint16_t address, message_t* packet, uint8_t type);
  bool clear_queue(int8_t type);

  bool clear_queue(int8_t type) {
    uint16_t queue_addr = NULL;
    if (type == ROUTE_REP) { 
      route_rep_sent=FALSE;
    } else if (type == ROUTE_REQ) { 
      route_req_sent = FALSE;
    }
  }
  
  bool generate_send (uint16_t address, message_t* packet, uint8_t type) { 
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
      dbg("radio_rec", "Timer0.isRunning()");
  		return FALSE;
  	}else{
  	if (type == ROUTE_REQ && !route_req_sent ){
      //dbg("radio_rec", "type == 1 && !route_req_sent");
  		route_req_sent = TRUE;
  		call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
  		queued_packet = *packet;
  		queue_addr = address;
  	}else if (type == ROUTE_REP && !route_rep_sent){
      //dbg("radio_rec", "type == 2 && !route_rep_sent");
  	  route_rep_sent = TRUE;
  		call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
  		queued_packet = *packet;
  		queue_addr = address;
  	}else if (type == 0){
      //dbg("radio_rec", "type == 0");
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
      call Timer1.startPeriodic(10000);
    }
    else {
      dbgerror("radio", "\nRadio failed to start, retrying...\n\n");
      call AMControl.start();
    }
  }
  
  event void Timer0.fired() {
  	/*
  	* Timer triggered to perform the send.
  	* MANDATORY: DO NOT MODIFY THIS FUNCTION
  	*/
  	actual_send(queue_addr, &queued_packet);
  }

  event void Timer1.fired() {

    if (TOS_NODE_ID == 1) {
      radio_route_msg_t* msg = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
      msg->type = DATA;
      msg->src = 1;
      msg->dest = 7;

      dbg("boot","..::Timer1.fired -> SENDING FIRST PACKET to %u\n\n", msg->dest);
      actual_send(msg->dest, &packet);
    }
  }
  
  bool actual_send(uint16_t address, message_t* packet) {
    radio_route_msg_t* msg = (radio_route_msg_t*)packet;

      /*
        if destination address not in actual routing_table
      */
      if (rt_next_hop[msg->dest-1] == NULL) {
        // hold on DATA packet and do a route discovery
        waiting_packet = *packet;

        msg->src = TOS_NODE_ID;
        msg->type = ROUTE_REQ;
        address = AM_BROADCAST_ADDR;
        dbg("radio_rec", "\t\tPRESEND -> Route discovery generated from %u to %u type %u\n",msg->src,msg->dest,msg->type);
      } else {
          if (msg->type == DATA) {
              address = rt_next_hop[msg->dest-1];
          } else if (msg->type == ROUTE_REQ) {
              address = AM_BROADCAST_ADDR;
          } else if (msg->type == ROUTE_REP){
              // add +1 in hopcount before sending
              msg->value = msg->value + 1;
              address = rt_next_hop[msg->dest-1];
          } 
      }

    if (call AMSend.send(address, packet, sizeof(radio_route_msg_t)) == SUCCESS) {
      //dbg("radio_send", "\t\tSENT SUCCESS from %d to %u type \n", TOS_NODE_ID, address);	
    }
  }

  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
  }

  event void AMControl.stopDone(error_t err) {
    dbg("boot", "\nRadio stopped!\n");
  }
  
  event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    dbg("radio_rec", "Received packet at time %s\n", sim_time_string());
    if (len != sizeof(radio_route_msg_t)) {return bufPtr;}
    else {
      radio_route_msg_t* msg = (radio_route_msg_t*)payload;

      dbg("radio_rec", "..::RECEIVE at %d -> dest %u src %u type %u\n",TOS_NODE_ID, msg->dest,msg->src,msg->type);
      /*
      divive the receive functionality by the msg type
      */
      if (msg->type == DATA) {
        // add led function
        dbg("radio_rec", "\t\t TYPE DATA");
        generate_send(msg->dest, msg, DATA);
      } else if (msg->type == ROUTE_REQ) {

        if (msg->dest == TOS_NODE_ID) {
          /*
          this is the node the ROUTE_REQ was looking for
          Generate ROUTE_REPLY
          */
          msg->type = ROUTE_REP;
          msg->dest = msg->src;
          msg->src = TOS_NODE_ID;
          msg->value = 0;
          generate_send(msg->dest,bufPtr,ROUTE_REP);
          dbg("radio_rec", "\t\tROUTE_REQ arrived to destination node %d\n", TOS_NODE_ID);
          dbg("radio_rec", "\t\tREPLY_REQ generated to %u\n",msg->dest);
        } else {
          uint16_t temp_src;
          /*
           this is not the node the ROUTE_REQ was looking for
           check if the destination node is in the current table
          */

          if (rt_next_hop[msg->dest-1] != NULL) {
            /* 
            ROUTE_REQ found in routing table
            */

            // create ROUTE_REP with actual routing table info
            msg->type = ROUTE_REP;
            msg->value = rt_hot_count[msg->dest-1];
            // src becomes the dest and the dest the src
            temp_src=msg->src;
            msg->src = msg->dest;
            msg->dest = temp_src;
            dbg("radio_rec", "\t\tROUTE founded at node %d\n", TOS_NODE_ID);
            dbg("radio_rec", "\t\tREPLY_REQ generated to %u\n",msg->dest);
          } else {
            /* 
            ROUTE_REQ not found int table
            keep looking and queue packet
            */
            dbg("radio_rec", "\t\tROUTE_REQ to node %u not found at %d\n", msg->dest,TOS_NODE_ID);
            generate_send(AM_BROADCAST_ADDR,bufPtr,ROUTE_REQ);
          }

        } 
      }  else if (msg->type == ROUTE_REP) {
          uint16_t actual_count;

          /*
            Save data on table if empty or acrual count biguer
          */
          actual_count = rt_hot_count[msg->dest-1];
          if (actual_count==NULL || actual_count>msg->value) {
            // update route in current table
            rt_hot_count[msg->dest-1] = msg->value;
            rt_next_hop[msg->dest-1] = msg->src;

            dbg("radio_pack","\t\tTable update at node %d -> dest: %u next_hop: %u count: %u\n"
                      ,TOS_NODE_ID, msg->dest,msg->src,msg->value );
            clear_queue(ROUTE_REQ);
          }
// comentario pra n da erro tem q ver como guardar direito waiting pakcet
          // check if this is the original src node of the ROUTE_REQ
          // // if (waiting_packet->dest == msg->dest) {
          // //   // if is the same, send the packet waiting the route discovery
          // //   clear_queue(ROUTE_REQ); // request done
          // //   generate_send(waiting_packet->dest,waiting_packet,waiting_packet->TYPE);
          // // } else {
          // //   /* this is the original node who 
          // //     requested the route discovery.
          // //     Send its data packet
          // //   */
          // //   generate_send(msg->dest,bufPtr,msg->type);
          // // }
          
          return bufPtr;
      }
    }
  }
}




