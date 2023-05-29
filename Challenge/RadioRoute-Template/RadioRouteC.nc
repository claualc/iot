
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
  uint16_t time_delays[7]={61,173,267,371,479,583,689}; // Time delay in milli seconds

  message_t waiting_packet; // Packet stored while route discovery is executed

  /*****  CONSTANTS  *****/
  uint16_t NODES_COUNT = 7;
  uint16_t DATA = 0;
  uint16_t ROUTE_REQ = 1;
  uint16_t ROUTE_REP = 2;

  /*****  ROUTING TABLE  *****/
  // the index of the arrays is the destination address
  uint16_t rt_next_hop[7]={NULL,NULL,NULL,NULL,NULL,NULL,NULL};
  uint16_t rt_hot_count[7]={NULL,NULL,NULL,NULL,NULL,NULL,NULL};
  uint16_t route_req_dest_node = 0;

  /*****  LEDs  *****/
  uint16_t leader_code[8] = {1,0,9,1,1,8,1,6};
  uint16_t led_counter;
  uint16_t led_0, led_1, led_2;
  
  /*****  ROUTER VARIABLES  *****/
  bool route_req_sent=FALSE;
  bool route_rep_sent=FALSE;
  bool data_sent=FALSE;
  
  bool locked;
  
  void change_leds();
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
      call Timer1.startOneShot(5000);
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

    // If current node is 1, try to send data message to node 7
    if (TOS_NODE_ID == 1) {
      radio_route_msg_t* msg = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
      msg->type = DATA;
      msg->src = TOS_NODE_ID;
      msg->dest = 7;
      route_req_sent=TRUE;
    
      actual_send(msg->dest, &packet);
    }
  }

  void change_leds() { 
    switch(leader_code[led_counter] % 3){
      case 0:
        call Leds.led0Toggle();
        break;
      case 1:
        call Leds.led1Toggle();
        break;
      case 2:
        call Leds.led2Toggle();
        break;
    }
    led_counter++;
    
    // Get LED status
  	if(!(call Leds.get() & LEDS_LED0)) {led_0 = 0;}
  	else {led_0 = 1;}
  	if(!(call Leds.get() & LEDS_LED1)) {led_1 = 0;}
  	else {led_1 = 1;}
  	if(!(call Leds.get() & LEDS_LED2)) {led_2 = 0;}
  	else {led_2 = 1;}
    
    dbg("led_status", "Node %u LED status: %u%u%u\n", TOS_NODE_ID, led_0, led_1, led_2);
    //if (TOS_NODE_ID == 6) {
    // 	dbg("led_status", "Node 6 LED status: %u%u%u\n", led_0, led_1, led_2);
    //}
    
    // Reset counter
    if (led_counter >= 8) {led_counter = 0;}
  }
  
  bool actual_send(uint16_t address, message_t* current_packet) {
      radio_route_msg_t* msg = (radio_route_msg_t*)call Packet.getPayload(current_packet, sizeof(radio_route_msg_t));;

      /*
        If destination address not in actual routing_table ->
        Start the execution of route discovery
      */
      if (address != AM_BROADCAST_ADDR && rt_next_hop[msg->dest-1] == NULL) {

        // Hold on DATA packet and do a route discovery 
        if (msg->type == DATA) {
          dbg("radio_rec", "\t\tPacket queue in the waiting list at %d dest %u src %u type %u\n",TOS_NODE_ID,msg->dest,msg->src,msg->type);
          waiting_packet = *current_packet;
        }

        // Parameters for route discovery
        msg->src = TOS_NODE_ID;
        msg->type = ROUTE_REQ;
        address = AM_BROADCAST_ADDR;
        dbg("radio_rec", "..::SEND at %d -> Route discovery generated from %u to %u type %u\n",TOS_NODE_ID, msg->src,msg->dest,msg->type);
      
      /*
        Organize message depending on type
      */
      } else {

          // Data message type
          if (msg->type == DATA) {
              address = rt_next_hop[msg->dest-1];
              msg->value = 5;
              data_sent = TRUE;
              dbg("radio_rec", "..::SEND at %d -> DATA generated from %u to %u, next hop %u\n",TOS_NODE_ID, msg->src,msg->dest,address);
          
          // Route Request message type
          } else if (msg->type == ROUTE_REQ) {
              route_req_dest_node = msg->dest; // Store the destination of the route discovery request
              dbg("radio_rec", "..::SEND at %d -> ROUTE_REQ generated from %u to %u\n",TOS_NODE_ID, msg->src,msg->dest);
          
          // Route reply message type
          } else if (msg->type == ROUTE_REP){
              msg->src = TOS_NODE_ID;
              msg->value = msg->value + 1; // Add +1 in hopcount before sending
              if (route_req_dest_node == 0) { msg->dest = TOS_NODE_ID; }
              else { msg->dest = route_req_dest_node; }
              dbg("radio_rec", "..::SEND at %d -> ROUTE_REPLY generated from %u to %u (broadcast)\n",TOS_NODE_ID, msg->src,msg->dest);
          } 
        }

    /*
      Send the message packet
    */  
    if (call AMSend.send(address, current_packet, sizeof(radio_route_msg_t)) == SUCCESS) {
      //dbg("radio_send", "\t\tSENT SUCCESS from %d to %u type \n", TOS_NODE_ID, address, msg->type);	
    }
  }

  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
  }

  event void AMControl.stopDone(error_t err) {
    dbg("boot", "\nRadio stopped!\n");
  }
  
  event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    if (len != sizeof(radio_route_msg_t)) {return bufPtr;}
    else {
      radio_route_msg_t* msg = (radio_route_msg_t*)payload;
      radio_route_msg_t* waiting_data_packet = (radio_route_msg_t*)call Packet.getPayload(&waiting_packet, sizeof(radio_route_msg_t));

      // Update LEDs when receiving any message type
      change_leds();

      /*
        Data message type received
      */
      if (msg->type == DATA) {

        dbg("radio_rec", "..::RECEIVE at %d -> dest %u src %u type %u\n",TOS_NODE_ID, msg->dest,msg->src,msg->type);
        // If destination node is the current node log success
        if (msg->dest == TOS_NODE_ID) {
          dbg("radio_rec", "..::DATA RECEIVED IN DESTINATION SUCCESSFULLY!!! Value: %u",msg->value);
        // Or send message to next hop
        } else {
          generate_send(rt_next_hop[msg->dest-1], bufPtr, DATA);
        }

      /*
        Route request message type received
      */
      } else if (msg->type == ROUTE_REQ && !route_req_sent) {
        dbg("radio_rec", "..::RECEIVE at %d -> dest %u src %u type %u\n",TOS_NODE_ID, msg->dest,msg->src,msg->type);

        //ignore backwards broadcast from next node

        if (msg->dest == TOS_NODE_ID) {
          
          // This is the node the ROUTE_REQ was looking for
          // Generate ROUTE_REPLY
          msg->type = ROUTE_REP;
          msg->dest = NULL;
          msg->value = 0;

          if (!route_rep_sent) {
            dbg("radio_rec", "\t\tROUTE founded at node %d\n", TOS_NODE_ID);
            generate_send(AM_BROADCAST_ADDR,bufPtr,ROUTE_REP);
          }

        } else {
          /*
           This is not the node the ROUTE_REQ was looking for
           check if the destination node is in the current table
          */

          if (rt_next_hop[msg->dest-1] != NULL) {
            /* 
            ROUTE_REQ found in routing table
            */

            // Create ROUTE_REP with actual routing table info
            msg->type = ROUTE_REP;
            msg->value = rt_hot_count[msg->dest-1];
            msg->dest = NULL; //?????

            if (!route_rep_sent) {
              dbg("radio_rec", "\t\tROUTE founded at node %d\n", TOS_NODE_ID);
              generate_send( AM_BROADCAST_ADDR,bufPtr,ROUTE_REP);
            }
           
          } else {
            /* 
            ROUTE_REQ not found int table
            keep looking and queue packet
            */
            dbg("radio_rec", "\t\tROUTE_REQ to node %u not found at %d\n", msg->dest,TOS_NODE_ID);
            generate_send(AM_BROADCAST_ADDR,bufPtr,msg->type);
          }

        } 
      }  else if (msg->type == ROUTE_REP) {
          uint16_t actual_count;
          dbg("radio_rec", "..::RECEIVE at %d -> dest %u src %u type %u\n",TOS_NODE_ID, msg->dest,msg->src,msg->type);

          /*
            Save data on table if empty or actual count bigger
          */
          actual_count = rt_hot_count[msg->src-1];
          if (actual_count == NULL || actual_count > msg->value) {
            // update route in current table
            rt_hot_count[msg->src-1] = 1;
            rt_next_hop[msg->src-1] = msg->src;

            dbg("radio_pack","\t\tTABLE UPDATE at %d -> dest: %u next_hop: %u count: %u\n",TOS_NODE_ID, msg->src,msg->src,1);

            actual_count = rt_hot_count[msg->dest-1];
            // update route table with requested dest
            if ((actual_count != NULL && msg->src != route_req_dest_node && actual_count > msg->value) || (actual_count==NULL && msg->src != route_req_dest_node)) {
              rt_hot_count[msg->dest-1] = msg->value;
              rt_next_hop[msg->dest-1] = msg->src;

              dbg("radio_pack","\t\tTABLE UPDATE at %d -> dest: %u next_hop: %u count: %u\n",TOS_NODE_ID, msg->dest,msg->src,msg->value);
            }
            /*
            dbg("radio_pack","NODE %d\n",TOS_NODE_ID);
            dbg("radio_pack","+------+----------+-----------+\n");
            dbg("radio_pack","| dest | next_hop | hop_count |\n");
            dbg("radio_pack","+------+----------+-----------+\n");
            dbg("radio_pack","|  1   |    %u     |     %u     |\n", rt_next_hop[0],rt_hot_count[0]);
            dbg("radio_pack","+------+----------+-----------+\n");
            dbg("radio_pack","|  2   |    %u     |     %u     |\n", rt_next_hop[1],rt_hot_count[1]);
            dbg("radio_pack","+------+----------+-----------+\n");
            dbg("radio_pack","|  3   |    %u     |     %u     |\n", rt_next_hop[2],rt_hot_count[2]);
            dbg("radio_pack","+------+----------+-----------+\n");
            dbg("radio_pack","|  4   |    %u     |     %u     |\n", rt_next_hop[3],rt_hot_count[3]);
            dbg("radio_pack","+------+----------+-----------+\n");
            dbg("radio_pack","|  5   |    %u     |     %u     |\n", rt_next_hop[4],rt_hot_count[4]);
            dbg("radio_pack","+------+----------+-----------+\n");
            dbg("radio_pack","|  6   |    %u     |     %u     |\n", rt_next_hop[5],rt_hot_count[5]);
            dbg("radio_pack","+------+----------+-----------+\n");
            dbg("radio_pack","|  7   |    %u     |     %u     |\n", rt_next_hop[6],rt_hot_count[6]);
            dbg("radio_pack","+------+----------+-----------+\n\n");
            */
          }

            /*VERIFY WAITING PACKET FOR ROUTE DISCOVERY TO END*/
          if (waiting_data_packet->dest != NULL && rt_next_hop[waiting_data_packet->dest-1] != NULL) {
            // Route found
            dbg("radio_rec", "\n..::DATA PACKET DESTINATIION FOUND\n");
            dbg("radio_pack","\t\tSending data packet... %u hops from %d to %u\n",rt_hot_count[waiting_data_packet->dest-1], TOS_NODE_ID, waiting_data_packet->dest);
            msg->src = waiting_data_packet->src;
            msg->dest = waiting_data_packet->dest;
            msg->type = waiting_data_packet->type;
            msg->value = waiting_data_packet->value;

            generate_send(msg->dest, bufPtr, DATA);
            waiting_data_packet->dest=NULL;
           
          } if (!data_sent && !route_rep_sent) {
            msg->type = ROUTE_REP;
            msg->value = rt_hot_count[msg->dest-1];
            msg->dest = NULL; //?????
            generate_send(AM_BROADCAST_ADDR,bufPtr,ROUTE_REP);
          }
      }
      return bufPtr;
    }
  }
}



