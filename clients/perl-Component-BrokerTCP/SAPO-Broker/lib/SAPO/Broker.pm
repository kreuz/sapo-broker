package SAPO::Broker;

use strict;
use warnings;
use 5.008004;
use IO::Socket::INET;
use XML::LibXML;
use XML::LibXML::XPathContext;
use Sys::Hostname;
use Data::Dumper;
use Carp qw(carp);

our $VERSION = 0.69.1;
our $libxml_parser;

sub new {
    my $class = shift;
    my %args  = @_;

    $args{timeout}        ||= 60;             # timeout de ligacao
    $args{host}           ||= '127.0.0.1';    # host da manta
    $args{port}           ||= 3322;           # porta da manta
    $args{recon_attempts} ||= 5;              # quantas tentativas de reconnect
    $args{DEBUG}          ||= 0;              # msgs de debug e tal...
    
	$args{retstruct}      ||= 0;              # retornar apenas o TextPayload ou uma struct?
		
    my $self = bless \%args, $class;

    $self->_debug("Starting in DEBUG MODE");
		
	# old things...
	$args{msg_type} = 'TOPIC' if exists $args{msg_type} && $args{msg_type} eq 'FF';
    carp("!!!\n\tmsg_type IS DEPRECATED in new(), use it only in publish, subscribe or poll\n!!!\n") if exists $args{msg_type};

    return undef unless $self->_connect;
    
    return $self;
}

# envia eventos
sub publish {
    my $self = shift;
    my %args = @_;

    # TODO: i hate this :/
    my @msg_types = ('Publish', 'Enqueue');
    my %msg_types  = map {$_ => 1} @msg_types;

    $self->_reconnect unless $self->_connected;
    return undef      unless $self->_connected;

    # default message type
    $args{msg_type} ||= 'Publish';

    # check for valid messages types
    if (!exists $msg_types{$args{msg_type}}) {
        carp("Unknown msg_type to publish msg, falling back to Publish type");
        $args{msg_type} = 'Publish';
    }

    return $self->_send_p(%args);
}

# subscreve eventos
sub subscribe {
    my $self = shift;
    my %args = @_;

    $self->_reconnect unless $self->_connected;
    return undef      unless $self->_connected;

    # TODO: i hate this :/
    my @msg_types = ('TOPIC', 'TOPIC_AS_QUEUE');
    my %msg_types  = map {$_ => 1} @msg_types;

    # default msg type
    $args{msg_type} ||= 'TOPIC';

    # check for valid messages types
    if (!exists $msg_types{$args{msg_type}}) {
        carp("Unknown msg_type to subscribe msg, falling back to TOPIC type");
        $args{msg_type} = 'TOPIC';
    }

    # send subscribe notification
    if ( $self->_send_s(%args) ) {
        $self->{_CORE_}->{topics}{ $args{topic} }{msg_type} = $args{topic};
        return 1;
    }
}

# poll
sub poll {
    my ($self, %args) = @_;

    $self->_reconnect unless $self->_connected;
    return undef      unless $self->_connected;

    my $msg_type = $args{msg_type};
    my $destname = $self->_destname($args{topic}, $msg_type);

    my $msg =
        "<soap:Envelope xmlns:soap='http://www.w3.org/2003/05/soap-envelope' xmlns:mq='http://services.sapo.pt/broker'>
        <soap:Body>
        <mq:Poll>
        <mq:DestinationName>$destname</mq:DestinationName>
        </mq:Poll>
        </soap:Body>
        </soap:Envelope>";

    $self->_debug("MSG SENT: $msg");

    _bus_encode( \$msg );
    return undef unless print { $self->{_CORE_}->{sock} } $msg;

    return 1;
}

# recebe eventos
sub receive {
	my $self = shift;

	$self->_debug("Receiving...");

	$self->_reconnect unless $self->_connected;

	my $buf;
	$self->{_CORE_}->{sock}->read( $buf, 4 );
	my $msgsize = unpack( 'N', $buf );
	$self->{_CORE_}->{sock}->read( $buf, $msgsize );

	if (!$buf) {
		$self->_debug("NO BUF?!");
		$self->_reconnect;
		return undef;
	}

    # REDO this line (don't remember why it's here)
	#return undef if $buf =~ m{Exception};

	$self->_debug("Payload: $buf");

	my $event = _parse_soap_message(
		$buf,'http://services.sapo.pt/broker',
		'BrokerMessage', qw(TextPayload MessageId DestinationName)
	);

	return $self->{retstruct} || $self->{msg_type} eq 'TOPIC_AS_QUEUE' ? 
		$event : $event->{TextPayload};
}


# Consumer Ack
sub ack {
	my ($self, $event) = @_;

	my $destname = $event->{DestinationName};
	my $msgid = $event->{MessageId};
	
	my $msg = 
		"<soapenv:Envelope xmlns:soapenv='http://www.w3.org/2003/05/soap-envelope'>
		<soapenv:Body>
		<Acknowledge xmlns='http://services.sapo.pt/broker'>
		<DestinationName>$destname</DestinationName>
		<MessageId>$msgid</MessageId>
		</Acknowledge>
		</soapenv:Body></soapenv:Envelope>";
	
	$self->_debug("ack: $msg");

	_bus_encode(\$msg);
	return undef unless print { $self->{_CORE_}->{sock} } $msg;

	return 1;
}

# DEPRECATED...
sub msg_type {
    my ($self, $topic) = @_;
    
    return unless $topic;
    
    $self->{_CORE_}->{topics}{$topic}{msg_type};
    #carp("!!!\n\tDont use this, it's deprecated\n!!!\n");
	#return shift->{msg_type}
}

#---

# mensagens de DEBUG
sub _debug {
    my $self = shift;

    return unless $self->{DEBUG};
    my $msg = shift;

    if ($self->{DEBUG} eq 666) {
        my $detail = "--- MSG: $msg\n";
        my $detailDeep = 0;
        while (my @c = caller($detailDeep++)) {
          $detail .= sprintf ( " %-40s => %s()\n", "$c[0] ($c[2])", $c[3] );
        }
        
        print STDERR "$detail\n";
    }
    else {
        print STDERR "[SAPO::Broker DEBUG] ", $msg, "\n";
    }
}

# adiciona o tamanho da mensagem antes de a enviar, protocol stuff
sub _bus_encode {
    my $buf = shift;
    substr( $$buf, 0, 0 ) = pack( 'N', length($$buf) );
}

sub _destname {
	my ($self, $topic, $msg_type) = @_;
	my $destname;

	if ($msg_type eq 'TOPIC_AS_QUEUE') {
		$destname = ($self->{hostname} || hostname()) . '@'; 
	}
	
	$destname .= $topic;
	
	return $destname;
}

# envia a subscricao de eventos
sub _send_s {
    my $self = shift;
    my %args = @_;

    my $msg_type = $args{msg_type};
    my $destname = $self->_destname($args{topic}, $msg_type);
		
    my $msg = q{<soapenv:Envelope xmlns:soapenv='http://www.w3.org/2003/05/soap-envelope'><soapenv:Body>};
    $msg .= q{<Notify xmlns='http://services.sapo.pt/broker'>};
    $msg .= qq{<DestinationName>$destname</DestinationName>};
    $msg .= "<DestinationType>". $msg_type ."</DestinationType>";
    $msg .= q{</Notify>};
    $msg .= q{</soapenv:Body></soapenv:Envelope>};
    
	$self->_debug("MSG RECV: $msg");
		
	_bus_encode( \$msg );
    return undef unless print { $self->{_CORE_}->{sock} } $msg;

    return 1;
}

# envia eventos
sub _send_p {
    my $self = shift;
    my %args = @_;

    my $msg_type = $args{msg_type};
    
    my $msg = q{<soapenv:Envelope xmlns:soapenv="http://www.w3.org/2003/05/soap-envelope"><soapenv:Body>};
    $msg .= qq{<$msg_type xmlns="http://services.sapo.pt/broker"><BrokerMessage>};
    $msg .= qq{<DestinationName>$args{topic}</DestinationName>};
    $msg .= q{<TextPayload>};
    $msg .= _xml_escape( $args{payload} );
    $msg .= q{</TextPayload>};
    $msg .= qq{</BrokerMessage></$msg_type>};
    $msg .= q{</soapenv:Body></soapenv:Envelope>};
    
    $self->_debug("MSG SENT: $msg");
    
    _bus_encode( \$msg );
    return undef unless print { $self->{_CORE_}->{sock} } $msg;

    return 1;
}

# valida de ainda esta ligado
sub _connected {
    my $self = shift;

    $self->_debug("Am i connected?");

    if ( exists $self->{_CORE_}->{sock} && $self->{_CORE_}->{sock}->connected ) {
        $self->_debug("Yes, still connected...");
        return 1;
    }
}

# liga
sub _connect {
    my $self = shift;

    $self->_debug("Connecting to: " . $self->{host});

    my $sock = IO::Socket::INET->new(
        PeerAddr   => $self->{host},
        PeerPort   => $self->{port},
        Timeout    => $self->{timeout},
        Proto      => 'tcp',
        Reuse      => 1,
        MultiHomed => 1,
        Blocking   => 1,
        Type       => SOCK_STREAM,
    );

    unless ($sock) {
        $self->_debug("Cant connect to: $self->{host} : $@");
        return undef;
    }
    $sock->autoflush(1);
    $self->{_CORE_}->{sock} = $sock;

    $self->_debug("CONNECTED!");

    return 1;    #$sock->connected;
}

# desliga
sub _disconnect {
    my $self = shift;

    $self->_debug("_disconnect");

    #return unless $self->{_CORE_}->{sock};

    $self->{_CORE_}->{sock}->close;
    delete $self->{_CORE_}->{sock};

    #return 1 if !$self->{_CORE_}->{sock}->connected;
}

# re-liga
sub _reconnect {
    my $self = shift;

    $self->_debug("_reconnect");

    $self->_disconnect if $self->_connected;

    for ( 1 .. $self->{recon_attempts} ) {
        $self->_debug("Reconnecting ...");
        if ( $self->_connect ) {
            $self->_debug("Connected!");

            $self->_debug("ReSubscribing...") if defined $self->{_CORE_}->{topics};

            for my $topic ( keys %{ $self->{_CORE_}->{topics} } ) {
                $self->_debug("... $topic");
                $self->subscribe( topic => $topic );
            }

            return 1;
        }
        sleep 1;
    }

    return undef;
}

# gamado do modulo do melo
sub _parse_soap_message {
    my ( $xml, $ns, $tag, @fields ) = @_;
    my %fields;

    my $message = _parse_with_libxml($xml);
    $message->registerNs( def => $ns );
    $message->registerNs( wsa => 'http://www.w3.org/2005/08/addressing' );

    return unless $message->findnodes("//def:$tag");

    foreach my $elem (@fields) {
        my $value = $message->findvalue("//def:$tag/def:$elem");
        $fields{$elem} = $value if defined $value;
    }

    $fields{source} = $message->findvalue('//wsa:From/wsa:Address');
    
    # extra info, i hope, some day, this fields come from the broker
    if ($fields{source}) {
        ($fields{host}, $fields{topic}) = _proc_source($fields{source});
    }

    return \%fields;
}

# processa o campo source, onde está o host e o topic
sub _proc_source {
    my $source = shift;
    
    my ($host, $topic) = $source =~ m!topic\@broker-([^-]+)-\d+://(.*)!;
    
    # until we don't have a better and secure way to get this info
    $host   ||= '___I CANT GET THE HOST___';
    $topic  ||= '___I CANT GET THE TOPIC___';
    
    return $host, $topic;
}

sub _parse_with_libxml {
    my ($xml) = @_;

    $libxml_parser ||= XML::LibXML->new;

    my $xpath = XML::LibXML::XPathContext->new( $libxml_parser->parse_string($xml) );
    
    # trying to find a very voodoo error :/
    #:146: parser error : Premature end of data in tag Envelope line 1
    die "!!!!!!!!!!!!!!!!!!!!!!!!!!\n$xml" unless $xpath;

    return $xpath;
}

sub _xml_escape {
    my ($xml) = @_;

    return $xml unless $xml;

    # Please remmember that the order is important
    $xml =~ s/&/&amp;/g;
    $xml =~ s/</&lt;/g;
    $xml =~ s/>/&gt;/g;

    return $xml;
}

1;    # End of SAPO::Broker

__END__

=head1 NAME

SAPO::Broker - The great new SAPO::Broker!

=head1 VERSION

Version 0.69

=cut

=head1 SYNOPSIS

Publish and Consume events from SAPO Broker.

    use SAPO::Broker;
    
    my $topic = "/test";

    my $broker = SAPO::Broker->new(
        host=> '127.0.0.1',
        DEBUG=>0,                   # 1 or 666
    );

    die "Cant connect? CAUSE: $@\n" unless $broker;

    print "SUBSCRIBING...\n";
    $broker->subscribe(
        topic   => $topic,
    );

    print "PUBLISHING...\n";
    $broker->publish(
        topic   => $topic,
        payload => 'TAU TAU',
    );

    print "RECEIVING...\n";
    while (1) {
        my $payload = $broker->receive;

        print "Message received: ", $payload, "\n";
    }






=head1 EXPORT

Nothing exported.

=head1 FUNCTIONS

=head2 new

=head3 OPTIONS:

	$args{timeout} 		||= 60;			# timeout de ligacao
	$args{host} 		||= '127.0.0.1';	# host da manta
	$args{port}		||= 3322;		# porta da manta
	$args{recon_attempts}	||= 5;			# quantas tentativas de reconnect
	$args{msg_type}		||= 'FF';		# se e' "file and forget' ou QUEUE
	$args{DEBUG}		||= 0;			# msgs de debug e tal...

=head3 RETURNS:

   1 => OK, subscribed
   undef => NOK

=head2 publish (topic => <TOPIC>, payload => <PAYLOAD>)

Send the payload to some topic.

=head3 RETURNS:

   1 => OK, subscribed
   undef => NOK

=cut

=head2 subscribe (topic => <TOPIC>)

Subscribe a topic. 

=head3 RETURNS: 

   1 => OK, subscribed
   undef => NOK

=cut

=head2 receive

Receive events from subscribed topics.

=head3 RETURNS:
   payload sent

=cut

=head1 AUTHORS

Delfim Machado, C<< <dbcm at co.sapo.pt> >>

Pedro Melo

Jose Cerdeira

Andre Cruz

=head1 BUGS

Bugs? Define BUGS!

Ok ok, here: http://softwarelivre.sapo.pt/broker/newticket

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc SAPO::Broker

=head1 ACKNOWLEDGEMENTS

Some code powered by Melo L<melo@co.sapo.pt> (POE Module)

=head1 COPYRIGHT & LICENSE

Copyright 2006 Delfim Machado, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut