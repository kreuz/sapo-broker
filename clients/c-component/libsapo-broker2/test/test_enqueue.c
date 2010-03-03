#define _XOPEN_SOURCE 600
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <strings.h>
#include <stdlib.h>
#include <stdint.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <errno.h>

#include "sapo_broker.h"

#define HOST        "127.0.0.1"

#define QUEUE       "/my/test/queue"
#define PAYLOAD     "ping"

int main(int argc, char *argv[])
{
    int rc = 0;
    int count = 1;
    char *payload = PAYLOAD;
    sapo_broker_t *sb;
    broker_server_t server;

    server.hostname =   HOST;
    server.port =    SB_PORT;
    server.transport = TCP;
    server.protocol = PROTOBUF;

    sb = broker_init( server );
    if (!sb) {
        printf("%s", broker_error(sb));
        exit(-1);
    }

    if( argc >= 2 ) {
        if( !strncmp("-udp", argv[1], 4 ) ) {
            printf("UDP ");
            server.transport = UDP;
        } else {
            printf("TCP ");
            server.transport = TCP;
        }
        if( argc >= 3 ) {
            payload = argv[2];
        }
        if( argc >= 4 ) {
            count = atoi(argv[3]);
        }
    }


    /* or:
       broker_destination_t dest;
       dest.name = TOPIC_NAME;
       dest.type = TOPIC;
       broker_send ( sb, destination, buf, len )
       */
    printf("enqueue %d times to queue: %s, payload: %s\n", count, QUEUE, payload);
    for(; count > 0; count--) {
        rc = broker_enqueue( sb, QUEUE, payload, strlen(payload) );
        if ( rc != SB_OK) {
            printf("%s", broker_error(sb));
            exit(-1);
        }
    }

    exit(0);
}