sapo-broker
===========

SAPO Broker is a distributed messaging framework

## What is it?

SAPO Broker is a  highperformance distributed messaging framework. Among other features, it provides minimal administration overhead, Publish-Subscribe and Point-to-Point messaging, guaranteed delivery and wildcard subscriptions.

SAPO Broker is written in Java, but has client libraries for [Perl][pl], [Python][py], [PHP][php], [.NET][net], [C][c] and quite a few [others][o], plus you can talk to it using Thrift, XML or JSON.

To start using SAPO Broker take a look at the Quick Start tutorial, and then please read the User Guide for more in depth information. Both are provided as part of the source tree in DocBook format.

You can access our public broker server at <code>broker.labs.sapo.pt</code> and subscribe to a number of public topics to experiment with.

## How do I get started?

Download the latest distribution bundle and read the Quick Start. To learn more about the design and concepts of SAPO Broker read the User Guide.

You can fetch the latest version of the SAPO Broker source code from our Git repo. For checking out the code use the <code>git</code> command line client as follows:

<pre class="prettyprint">
git clone git@github.com:sapo/sapo-broker.git
</pre>

## License

The SAPO Broker core is distributed under the [BSD license][bsd]. Some dependencies or extensions are under [separate licensing][l].

## How to get involved

Go ahead and [fork][repo] the project or subscribe to the [mailing-list][ml].

----

[repo]: https://github.com/sapo/sapo-broker
[ml]: http://listas.softwarelivre.sapo.pt/mailman/listinfo/broker
[bsd]: https://github.com/sapo/sapo-broker/blob/master/license/LICENSE.txt
[l]: https://github.com/sapo/sapo-broker/tree/master/license
[c]: https://github.com/sapo/sapo-broker/tree/master/clients/c-component
[net]: https://github.com/sapo/sapo-broker/tree/master/clients/dotnet-component
[o]: https://github.com/sapo/sapo-broker/tree/master/clients
[pl]: https://github.com/sapo/sapo-broker/tree/master/clients/perl-component)
[py]: https://github.com/sapo/sapo-broker/tree/master/clients/python-component)
[php]: https://github.com/sapo/sapo-broker/tree/master/clients/php-component)
