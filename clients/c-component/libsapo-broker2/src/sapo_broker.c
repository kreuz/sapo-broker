#include <stdio.h>
#include <stdlib.h>
#include <string.h>


#include "libsapo-broker2.h"
#include "broker_internals.h"
#include "protocol.h"
#include "net.h"


/* private members */
static char _global_broker_err_msg[SB_BUFSIZ];
static int broker_add_destination(sapo_broker_t *sb, broker_destination_t dest);
static int broker_del_destination(sapo_broker_t *sb, broker_destination_t dest);

static _broker_server_t *
broker_get_server_from_msg(sapo_broker_t *sb, broker_msg_t *msg)
{
    uint_t i;
    _broker_server_t *srv = NULL;
    int host_len = strlen(msg->server.hostname);

    for(i = 0; i < sb->servers.server_count; i++) {
        srv = &(sb->servers.server[i]);
        if( srv->srv.port == msg->server.port &&
             !strncmp(srv->srv.hostname, msg->server.hostname, host_len) )
            return srv;
    }
    return srv;
}



sapo_broker_t *
broker_init( broker_server_t server_1)
{
    sapo_broker_t * sb = NULL;

    sb = (sapo_broker_t *) calloc( 1, sizeof(sapo_broker_t) );
    if( !sb ) {
        snprintf(_global_broker_err_msg, SB_BUFSIZ,
                "broker_init() failed to alocate memory.");
        return NULL;
    }

    broker_add_server(sb, server_1);

    sb->destinations.dest = calloc(2, sizeof(broker_destination_t) );
    sb->destinations.array_count = 2;
    sb->destinations.dest_count = 0;


    pthread_mutex_init( sb->lock, NULL);
    return sb;
}


int
broker_add_server( sapo_broker_t *sb, broker_server_t server)
{
    _broker_server_t *srv = NULL;

    if(!sb)
        return SB_NOT_INITIALIZED;

    pthread_mutex_lock(sb->lock);

    if(sb->servers.array_count == sb->servers.server_count ){
        uint_t new_count = 1 + (sb->servers.array_count * 2);
        srv = realloc(sb->servers.server, sizeof(_broker_server_t) * new_count);
        if( ! srv ) {
            log_err(sb, "broker_add_server(): realloc() failed, server not added.");
            return SB_ERROR;
        }
        sb->servers.server = srv;
        sb->servers.array_count = new_count;
    }


    if( server.protocol > THRIFT ) {
        server.protocol = PROTOBUF;
        log_info( sb, "broker_add_server(): bad protocol, defaulting to PROTOCOL BUFFERS");
    }
    if( server.transport > UDP ) {
        server.transport = TCP;
        log_info( sb, "broker_add_server(): bad transport, defaulting to TCP");
    }

    memset( &(sb->servers.server[ sb->servers.server_count ]), 0, sizeof(_broker_server_t));
    sb->servers.server[ sb->servers.server_count ].srv = server;
    pthread_mutex_init( sb->servers.server[ sb->servers.server_count ].lock_r, NULL );
    pthread_mutex_init( sb->servers.server[ sb->servers.server_count ].lock_w, NULL );

    log_debug(sb, "server: { %s, %d, %d, %d }", server.hostname, server.port, (int) server.transport, (int) server.protocol);

    sb->servers.server_count++;

    pthread_mutex_unlock(sb->lock);
    return SB_OK;
}


int
broker_send( sapo_broker_t *sb,
             broker_destination_t dest,
             broker_sendmsg_t sendmsg)
{
    int rc = 0;
    _broker_server_t *srv = NULL;

    if(!sb)
        return SB_NOT_INITIALIZED;

    for(int i=0; i < 3; i++) {
        srv = _broker_server_get_active( sb );
        pthread_mutex_lock(srv->lock_w);
        switch ( srv->srv.protocol ) {
            case SOAP:
                rc = proto_soap_send( sb, srv, &dest, &sendmsg );
                break;
            case PROTOBUF:
                rc = proto_protobuf_send( sb, srv, &dest, &sendmsg );
                break;
            case THRIFT:
                rc = proto_thrift_send( sb, srv, &dest, &sendmsg );
                break;
            default:
                rc = SB_ERROR;
                log_err(sb, "invalid server protocol.");
                break;
        }
        pthread_mutex_unlock(srv->lock_w);
        if( rc != SB_OK ) {
            log_err(sb, "broker_send: failed, trying again.");
            continue;
        }
        break;
    }
    if( rc != SB_OK ) {
        log_err(sb, "broker_send(): failed multiple times sending to server");
    }

    return rc;
}

int
broker_publish( sapo_broker_t *sb,
                char *topic,
                char *msg,
                size_t size)
{
    broker_destination_t dest;
    broker_sendmsg_t sendmsg =  { NULL, 0, 0, 0, NULL };

    sendmsg.payload = msg;
    sendmsg.payload_size = size;

    dest.name = topic;
    dest.type = SB_TOPIC;

    return broker_send(sb, dest, sendmsg);
}

int
broker_enqueue( sapo_broker_t *sb,
                char *queue,
                char *msg,
                size_t size)
{
    broker_destination_t dest;
    broker_sendmsg_t sendmsg = (broker_sendmsg_t) { NULL, 0, 0, 0, NULL };

    sendmsg.payload = msg;
    sendmsg.payload_size = size;

    dest.name = queue;
    dest.type = SB_QUEUE;
    return broker_send(sb, dest, sendmsg);
}


int
broker_subscribe( sapo_broker_t *sb, broker_destination_t dest)
{
    int rc = 0;
    _broker_server_t *srv = NULL;

    if(!sb)
        return SB_NOT_INITIALIZED;

    for(int i=0; i < 3; i++) {
        srv = _broker_server_get_active( sb );
        pthread_mutex_lock(srv->lock_w);
        switch ( srv->srv.protocol ) {
            case SOAP:
                rc = proto_soap_subscribe( sb, srv, &dest );
                break;

            case PROTOBUF:
                rc = proto_protobuf_subscribe( sb, srv, &dest );
                break;

            case THRIFT:
                rc = proto_thrift_subscribe( sb, srv, &dest );
                break;

            default:
                rc = SB_ERROR;
                log_err(sb, "broker_subscribe: invalid server protocol.");
                break;
        }
        pthread_mutex_unlock(srv->lock_w);
        if( rc != SB_OK ) {
            log_err(sb, "broker_subscribe: failed, trying again.");
            continue;
        }
        break;
    }
    if( rc != SB_OK ) {
        log_err(sb, "broker_subscribe(): failed multiple times talking to server");
    } else {

        broker_add_destination(sb, dest);
    }

    return rc;
}


int
broker_subscribe_topic( sapo_broker_t *sb, char *topic)
{
    broker_destination_t dest;

    dest.name = topic;
    dest.type = SB_TOPIC;
    dest.queue_autoack = 0;

    return broker_subscribe(sb, dest);
}

int
broker_subscribe_queue( sapo_broker_t *sb, char *queue, bool queue_autoack)
{
    broker_destination_t dest;

    dest.name = queue;
    dest.type = SB_QUEUE;
    dest.queue_autoack = queue_autoack;

    return broker_subscribe(sb, dest);
}


int
broker_msg_free( broker_msg_t *msg)
{
    if( !msg )
        return 0;
    if( msg->payload )
        free(msg->payload);
    if( msg->message_id )
        free(msg->message_id);
    if( msg )
        free(msg);

    return 0;
}

int
broker_msg_ack( sapo_broker_t *sb, broker_msg_t *msg)
{
    int rc;
    if(!sb)
        return SB_NOT_INITIALIZED;

    if( !msg || !msg->message_id) {
        log_err(sb, "broker_msg_ack(): bad message, cannot acknowledge");
        return SB_ERROR;
    }

    _broker_server_t *srv = broker_get_server_from_msg(sb, msg);
    pthread_mutex_lock(srv->lock_w);
    switch ( msg->server.protocol ) {
        case SOAP:
            rc = proto_soap_send_ack( sb, srv, msg->origin.name, msg->message_id);
            break;
        case PROTOBUF:
            rc = proto_protobuf_send_ack( sb, srv, msg->origin.name, msg->message_id);
            break;
        case THRIFT:
            rc = proto_thrift_send_ack( sb, srv, msg->origin.name, msg->message_id);
            break;
        default:
            rc = SB_ERROR;
            log_err(sb, "broker_msg_ack: invalid server in msg.");
            break;
    }
    pthread_mutex_lock(srv->lock_w);

    broker_msg_free(msg);
    return rc;
}

broker_msg_t *
broker_receive( sapo_broker_t *sb, struct timeval *timeout)
{
    broker_msg_t *msg;
    _broker_server_t *srv = NULL;
    int rc = 0;

    if(!sb)
        return NULL;

    for(int i = 0; i < 3; i++) {
        /* assure that we are connected to at least one server */
        srv = _broker_server_get_active(sb);

        srv = net_poll( sb, timeout);
        if( srv == NULL ) {
            log_debug(sb, "receive(): net_poll() -> NULL");
            return NULL;
        }

        log_debug(sb, "receive(): data from: %s:%d",
                srv->srv.hostname, srv->srv.port);
        pthread_mutex_lock(srv->lock_r);
        switch ( srv->srv.protocol ) {
            case SOAP:
                msg = proto_soap_read_msg( sb, srv );
                break;

            case PROTOBUF:
                msg = proto_protobuf_read_msg( sb, srv );
                break;

            case THRIFT:
                msg = proto_thrift_read_msg( sb, srv );
                break;

            default:
                rc = SB_ERROR;
                log_err(sb, "broker_receive: invalid server protocol in received packet.");
        }
        pthread_mutex_unlock(srv->lock_r);
        if( NULL == msg ) {
            log_err(sb, "broker_receive: failed, trying again.");
            continue;
        }
        break;
    }

    return msg;
}


int
broker_destroy(sapo_broker_t *sb)
{
    if( !sb )
        return SB_NOT_INITIALIZED;

    /* close all open connections to servers */
    _broker_server_disconnect_all(sb);

    /* deallocate all memory */
    if( NULL != sb->servers.server ) {
        free(sb->servers.server);
        sb->servers.server = NULL;
    }

    if( NULL != sb->destinations.dest ) {
        free(sb->destinations.dest );
        sb->destinations.dest = NULL;
    }

    free( sb );

   return SB_OK;
}


char *
broker_error( sapo_broker_t *sb)
{
    if( !sb )
        return _global_broker_err_msg;
    return sb->last_error_msg;
}

static int
broker_add_destination(sapo_broker_t *sb, broker_destination_t dest)
{
    if(!sb)
        return SB_NOT_INITIALIZED;

    pthread_mutex_lock(sb->lock);

    int rc = 0;
    /* any space left on destinations array ? */
    if( sb->destinations.dest_count == sb->destinations.array_count ) {
        broker_destination_t *dst = NULL;
        uint_t new_count = 1 + (sb->destinations.array_count * 2);
        dst = realloc( sb->destinations.dest, sizeof(broker_destination_t) * new_count );
        if( dst == NULL ) {
            log_err(sb, "broker_subscribe(): realloc() failed, can't save destination");
            return rc; // maybe everything will work just fine...
        }
        sb->destinations.dest = dst;
        sb->destinations.array_count = new_count;
    }

    sb->destinations.dest[ sb->destinations.dest_count++ ] = dest;

    pthread_mutex_unlock(sb->lock);
    return rc;
}

/* saved destinations have auto_ack settings that should be respected, gotta fetch it */
broker_destination_t
broker_get_destination( sapo_broker_t *sb, const char *dest_name, uint8_t type)
{
    pthread_mutex_lock(sb->lock);

    broker_destination_t *dest;
    for(uint_t i = 0; i < sb->destinations.dest_count; i++) {
        dest = &(sb->destinations.dest[i]);
        if( dest->type == type && !strcmp(dest->name, dest_name) )
            return *dest;
    }
    /* not found? .. log error and return destination without auto-ack */
    broker_destination_t dst = (broker_destination_t) { dest_name, type, 0 };
    log_err(sb, "broker_get_destination: cannot find this destination on destination list.");

    pthread_mutex_unlock(sb->lock);
    return dst;
}


