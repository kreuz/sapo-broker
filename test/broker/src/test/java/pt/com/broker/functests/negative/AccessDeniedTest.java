package pt.com.broker.functests.negative;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import pt.com.broker.functests.helpers.GenericNetMessageNegativeTest;
import pt.com.broker.types.NetAction;
import pt.com.broker.types.NetAction.ActionType;
import pt.com.broker.types.NetAction.DestinationType;
import pt.com.broker.types.NetBrokerMessage;
import pt.com.broker.types.NetMessage;
import pt.com.broker.types.NetProtocolType;
import pt.com.broker.types.NetPublish;

public class AccessDeniedTest extends GenericNetMessageNegativeTest
{

	private static final Logger log = LoggerFactory.getLogger(AccessDeniedTest.class);

	public AccessDeniedTest(NetProtocolType protocolType)
	{
		super(protocolType);
		log.debug("AccessDeniedTest constructor!");

		setName("Access Denied");

		NetBrokerMessage brokerMsg = new NetBrokerMessage("This is the payload".getBytes());
		NetPublish publish = new NetPublish("/system/foo", DestinationType.TOPIC, brokerMsg);
		NetAction action = new NetAction(ActionType.PUBLISH);
		action.setPublishMessage(publish);
		NetMessage message = new NetMessage(action);
		setMessage(message);

		setFaultCode("3201");
		setFaultMessage("Access denied");
	}

	@Override
	public boolean skipTest()
	{
		return (getEncodingProtocolType() == NetProtocolType.JSON);
	}
}
