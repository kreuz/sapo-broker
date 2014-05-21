package pt.com.broker.client.nio.bootstrap;

import io.netty.channel.Channel;
import pt.com.broker.client.nio.codecs.oldframing.BrokerMessageEncoder;
import pt.com.broker.types.BindingSerializer;
import pt.com.broker.types.NetProtocolType;

/**
 * Created by luissantos on 06-05-2014.
 */
public class DatagramChannelInitializer extends BaseChannelInitializer {

    public DatagramChannelInitializer(BindingSerializer serializer) {
        super(serializer);

        if(! (serializer.getProtocolType().equals(NetProtocolType.PROTOCOL_BUFFER) || serializer.getProtocolType().equals(NetProtocolType.THRIFT)) ){
            log.warn("Using non-binary encoding with datagram transport will add some overhead ");
        }
    }

    @Override
    protected void initChannel(Channel ch) throws Exception {

        super.initChannel(ch);

        log.debug("Init");

        if(isOldFraming()){

            log.debug("Old framing");

            BrokerMessageEncoder encoder =  (BrokerMessageEncoder) ch.pipeline().get("broker_message_encoder");
            encoder.setUseFrame(false);
        }


    }
}