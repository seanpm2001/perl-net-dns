package Net::DNS::Resolver;

#
# $Id$
#
use vars qw($VERSION);
$VERSION = (qw$LastChangedRevision$)[1];

=head1 NAME

Net::DNS::Resolver - DNS resolver class

=cut


use strict;

use vars qw(@ISA);

BEGIN {
	for ( $^O, 'UNIX' ) {
		my $class = join '::', __PACKAGE__, $_;
		return @ISA = ($class) if eval "require $class;";
	}
	die 'failed to load platform specific resolver component';
}


1;

__END__


=head1 SYNOPSIS

    use Net::DNS;

    $resolver = new Net::DNS::Resolver();

    # Perform a lookup, using the searchlist if appropriate.
    $reply = $resolver->search( 'example.com' );

    # Perform a lookup, without the searchlist
    $reply = $resolver->query( 'example.com', 'MX' );

    # Perform a lookup, without pre or post-processing
    $reply = $resolver->send( 'example.com', 'MX', 'CH' );

    # Send a prebuilt query packet
    $query = new Net::DNS::Packet( ... );
    $reply = $resolver->send( $packet );

=head1 DESCRIPTION

Instances of the C<Net::DNS::Resolver> class represent resolver objects.
A program can have multiple resolver objects, each maintaining its
own state information such as the nameservers to be queried, whether
recursion is desired, etc.

=head1 METHODS

=head2 new

    # Use the default configuration
    $resolver = new Net::DNS::Resolver();

    # Use my own configuration file
    $resolver = new Net::DNS::Resolver( config_file => '/my/dns.conf' );

    # Set options in the constructor
    $resolver = new Net::DNS::Resolver(
	nameservers => [ '10.1.1.128', '10.1.2.128' ],
	recurse	    => 0,
	debug	    => 1
	);

Returns a resolver object.  If no arguments are supplied, new()
returns an object having the default configuration.

On Unix and Linux systems,
the default values are read from the following files,
in the order indicated:

    /etc/resolv.conf
    $HOME/.resolv.conf
    ./.resolv.conf

The following keywords are recognised in resolver configuration files:

=over 4

=item domain

The default domain.

=item search

A space-separated list of domains to put in the search list.

=item nameserver

A space-separated list of nameservers to query.

=back

Except for F</etc/resolv.conf>, files will only be read if owned by the
effective userid running the program.  In addition, several environment
variables may contain configuration information; see L</ENVIRONMENT>.

On Windows systems, an attempt is made to determine the system defaults
using the registry.  Systems with many dynamically configured network
interfaces may confuse Net::DNS.


You can include a configuration file of your own when creating a
resolver object:

    # Use my own configuration file
    $resolver = new Net::DNS::Resolver( config_file => '/my/dns.conf' );

This is supported on both Unix and Windows.


If a custom configuration file is specified at first instantiation,
both the system configuration and environment variables are ignored.

Explicit arguments to new() override the corresponding configuration
variables.  The following arguments are supported:

=over 4

=item nameservers

A reference to an array of nameservers to query.

=item searchlist

A reference to an array of domains to search for unqualified names.

=item domain

Domain name suffix to be appended to queries of unqualified names.

=item recurse

=item debug

=item port

=item srcaddr

=item srcport

=item tcp_timeout

=item udp_timeout

=item retrans

=item retry

=item usevc

=item stayopen

=item igntc

=item defnames

=item dnsrch

=item persistent_tcp

=item persistent_udp

=item dnssec

=back

For more information on any of these options, please consult the method
of the same name.

=head2 search

    $packet = $resolver->search( 'mailhost' );
    $packet = $resolver->search( 'mailhost.example.com' );
    $packet = $resolver->search( '192.0.2.1' );
    $packet = $resolver->search( 'example.com', 'MX' );
    $packet = $resolver->search( 'annotation.example.com', 'TXT', 'HS' );

Performs a DNS query for the given name, applying the searchlist if
appropriate.  The search algorithm is as follows:

=over 4

=item 1.

If the name contains at least one dot, try it as is.

=item 2.

If the name does not end in a dot, try appending each item in the
search list to the name.  This is only done if C<dnsrch> is true.

=item 3.

If the name does not contain any dots, try it as is.

=back

The record type and class can be omitted; they default to A and IN.
If the name looks like an IP address (IPv4 or IPv6),
then an appropriate PTR query will be performed.

Returns a C<Net::DNS::Packet> object, or C<undef> if no answers were found.
If you need to examine the response packet, whether it contains
any answers or not, use the send() method instead.

=head2 query

    $packet = $resolver->query( 'mailhost' );
    $packet = $resolver->query( 'mailhost.example.com' );
    $packet = $resolver->query( '192.0.2.1' );
    $packet = $resolver->query( 'example.com', 'MX' );
    $packet = $resolver->query( 'annotation.example.com', 'TXT', 'HS' );

Performs a DNS query for the given name; the search list is not
applied.  If the name does not contain any dots and C<defnames>
is true, the default domain will be appended.

The record type and class can be omitted; they default to A and IN.
If the name looks like an IP address (IPv4 or IPv6),
an appropriate PTR query will be performed.

Returns a C<Net::DNS::Packet> object, or C<undef> if no answers were found.
If you need to examine the response packet, whether it contains
any answers or not, use the send() method instead.

=head2 send

    $packet = $resolver->send( $packet );
    $packet = $resolver->send( 'mailhost.example.com' );
    $packet = $resolver->send( 'example.com', 'MX' );
    $packet = $resolver->send( 'annotation.example.com', 'TXT', 'HS' );

Performs a DNS query for the given name.  Neither the searchlist
nor the default domain will be appended.

The argument list can be either a C<Net::DNS::Packet> object or a list
of strings.  The record type and class can be omitted; they default to
A and IN.  If the name looks like an IP address (IPv4 or IPv6),
an appropriate PTR query will be performed.

Returns a C<Net::DNS::Packet> object whether there were any answers or not.
Use C<< $packet->header->ancount >> or C<< $packet->answer >> to find out
if there were any records in the answer section.
Returns C<undef> if no response was received.


=head2 axfr

    @zone = $resolver->axfr();
    @zone = $resolver->axfr( 'example.com' );
    @zone = $resolver->axfr( 'example.com', 'HS' );

    $iterator = $resolver->axfr();
    $iterator = $resolver->axfr( 'example.com' );
    $iterator = $resolver->axfr( 'example.com', 'HS' );

    $rr = $iterator->();

Performs a zone transfer using the resolver nameservers list,
attempted in the order listed.

If the zone is omitted, it defaults to the first zone listed
in the resolver search list.

If the class is omitted, it defaults to IN.


When called in list context, axfr() returns a list of C<Net::DNS::RR>
objects or an empty list if the zone transfer failed.
The redundant SOA record that terminates the zone transfer is not
returned to the caller.

Here is an example that uses a timeout and TSIG verification:

    $resolver->tcp_timeout( 10 );
    $resolver->tsig( 'Khmac-sha1.example.+161+24053.private' );
    @zone = $resolver->axfr( 'example.com' );

    die 'Zone transfer failed: ', $resolver->errorstring unless @zone;

    foreach $rr (@zone) {
	$rr->print;
    }


When called in scalar context, axfr() returns an iterator object.
Each invocation of the iterator returns a single C<Net::DNS::RR>
or C<undef> when the zone is exhausted.
The redundant SOA record that terminates the zone transfer is not
returned to the caller.

Here is the example above, implemented using an iterator:

    $resolver->tcp_timeout( 10 );
    $resolver->tsig( 'Khmac-sha1.example.+161+24053.private' );
    $iterator = $resolver->axfr( 'example.com' );

    die 'Zone transfer failed: ', $resolver->errorstring unless $iterator;

    while ( $rr = $iterator->() ) {
	$rr->print;
    }


=head2 nameservers

    @nameservers = $resolver->nameservers();
    $resolver->nameservers( '192.0.2.1', '192.0.2.2', '2001:DB8::3' );

Gets or sets the nameservers to be queried.

Also see the IPv6 transport notes below

=head2 empty_nameservers

    $resolver->empty_nameservers();

Empties the list of nameservers.
 
=head2 print

    $resolver->print;

Prints the resolver state on the standard output.

=head2 string

    print $resolver->string;

Returns a string representation of the resolver state.

=head2 searchlist

    @searchlist = $resolver->searchlist;
    $resolver->searchlist( 'a.example', 'b.example', 'c.example' );

Gets or sets the resolver search list.

=head2 empty_searchlist

    $resolver->empty_searchlist();

Empties the searchlist.
 
=head2 port

    print 'sending queries to port ', $resolver->port, "\n";
    $resolver->port(9732);

Gets or sets the port to which queries are sent.
Convenient for nameserver testing using a non-standard port.
The default is port 53.

=head2 srcport

    print 'sending queries from port ', $resolver->srcport, "\n";
    $resolver->srcport(5353);

Gets or sets the port from which queries are sent.
The default is 0, meaning any port.

=head2 srcaddr

    print 'sending queries from address ', $resolver->srcaddr, "\n";
    $resolver->srcaddr('192.0.2.1');

Gets or sets the source address from which queries are sent.
Convenient for forcing queries from a specific interface on a
multi-homed host.
The default is 0.0.0.0, meaning any local address.

=head2 bgsend

    $socket = $resolver->bgsend( $packet ) || die $resolver->errorstring;

    $socket = $resolver->bgsend( 'mailhost.example.com' );
    $socket = $resolver->bgsend( 'example.com', 'MX' );
    $socket = $resolver->bgsend( 'annotation.example.com', 'TXT', 'HS' );

Performs a background DNS query for the given name, i.e., sends a
query packet to the first destination in the C<nameservers> list and
returns immediately without waiting for a response.  The program can
then perform other tasks while awaiting the response from the nameserver.

The argument list can be either a C<Net::DNS::Packet> object or a list
of strings.  The record type and class can be omitted; they default to
A and IN.  If the name looks like an IP address (IPv4 or IPv6),
an appropriate PTR query will be performed.

Returns an C<IO::Socket::INET> object or C<undef> on error in which
case the reason for failure can be found through a call to the
errorstring method.

The program must determine when the socket is ready for reading and
call C<bgread> to get the response packet.  Either C<bgisready> or
C<IO::Select> may be used to find out if the socket is ready.

C<bgsend> does not support persistent sockets.

B<BEWARE>:
C<bgsend> does not support the usevc option (TCP) and operates on UDP only.
Answers may not fit in an UDP packet and might be truncated. Truncated 
packets will B<not> be retried over TCP automatically and should be handled
by the caller.

=head2 bgread

    $packet = $resolver->bgread($socket);
    if ($packet->header->tc) { 
	# Retry over TCP (blocking).
    }
    undef $socket;

Reads the answer from a background query (see L</bgsend>).  The argument
is an C<IO::Socket> object returned by C<bgsend>.

Returns a C<Net::DNS::Packet> object or C<undef> on error.

The programmer should close or destroy the socket object after reading it.

=head2 bgisready

    $socket = $resolver->bgsend( 'foo.example.com' );
    until ($resolver->bgisready($socket)) {
	# do some other processing
    }
    $packet = $resolver->bgread($socket);
    if ($packet->header->tc) { 
	# Retry over TCP (blocking).
    }
    $socket = undef;

Determines whether a socket is ready for reading.  The argument is
an C<IO::Socket> object returned by C<bgsend>.

Returns true if the socket is ready, false if not.


=head2 tsig

    $tsig = $resolver->tsig;
    $resolver->tsig( $tsig );

    $resolver->tsig( 'Khmac-sha1.example.+161+24053.private' );

    $resolver->tsig( 'Khmac-sha1.example.+161+24053.key' );

    $resolver->tsig( 'Khmac-sha1.example.+161+24053.key',
		fudge => 60
		);

    $resolver->tsig( $key_name, $key );

    $resolver->tsig( undef );

Get or set the TSIG record used to automatically sign outgoing
queries and updates.  Call with an undefined argument, 0 or ''
to turn off automatic signing.

The default resolver behavior is not to sign any packets.  You must
call this method to set the key if you would like the resolver to
sign packets automatically.

Packets can also be signed manually; see the L<Net::DNS::Packet>
and L<Net::DNS::Update> manual pages for examples.  TSIG records
in manually-signed packets take precedence over those that the
resolver would add automatically.


=head2 retrans

    print 'retrans interval: ', $resolver->retrans, "\n";
    $resolver->retrans(3);

Get or set the retransmission interval
The default is 5 seconds.

=head2 retry

    print 'number of tries: ', $resolver->retry, "\n";
    $resolver->retry(2);

Get or set the number of times to try the query.
The default is 4.

=head2 recurse

    print 'recursion flag: ', $resolver->recurse, "\n";
    $resolver->recurse(0);

Get or set the recursion flag.
If true, this will direct nameservers to perform a recursive query.
The default is true.

=head2 defnames

    print 'defnames flag: ', $resolver->defnames, "\n";
    $resolver->defnames(0);

Get or set the defnames flag.
If true, calls to C<query> will append the default domain to names
that contain no dots.
The default is true.

=head2 dnsrch

    print 'dnsrch flag: ', $resolver->dnsrch, "\n";
    $resolver->dnsrch(0);

Get or set the dnsrch flag.
If true, calls to C<search> will apply the search list to resolve
names that are not fully qualified.
The default is true.

=head2 debug

    print 'debug flag: ', $resolver->debug, "\n";
    $resolver->debug(1);

Get or set the debug flag.
If set, calls to C<search>, C<query>, and C<send> will print
debugging information on the standard output.
The default is false.

=head2 usevc

    print 'usevc flag: ', $resolver->usevc, "\n";
    $resolver->usevc(1);

Get or set the usevc flag.
If true, queries will be performed using virtual circuits (TCP)
instead of datagrams (UDP).
The default is false.

=head2 tcp_timeout

    print 'TCP timeout: ', $resolver->tcp_timeout, "\n";
    $resolver->tcp_timeout(10);

Get or set the TCP timeout in seconds.
The default is 120 seconds (2 minutes).
A timeout of C<undef> means indefinite.

=head2 udp_timeout

    print 'UDP timeout: ', $resolver->udp_timeout, "\n";
    $resolver->udp_timeout(10);

Get or set the UDP timeout in seconds.
The default is C<undef>, which means that the retry and retrans
settings will be used to perform the retries until they exhausted.

=head2 persistent_tcp

    print 'Persistent TCP flag: ', $resolver->persistent_tcp, "\n";
    $resolver->persistent_tcp(1);

Get or set the persistent TCP setting.
If true, Net::DNS will keep a TCP socket open for each host:port
to which it connects.
This is useful if you are using TCP and need to make a lot of queries
or updates to the same nameserver.

The default is false unless you are running a SOCKSified Perl,
in which case the default is true.

=head2 persistent_udp

    print 'Persistent UDP flag: ', $resolver->persistent_udp, "\n";
    $resolver->persistent_udp(1);

Get or set the persistent UDP setting.
If true, Net::DNS will keep a single UDP socket open for all queries.
This is useful if you are using UDP and need to make a lot of queries
or updates.

=head2 igntc

    print 'igntc flag: ', $resolver->igntc, "\n";
    $resolver->igntc(1);

Get or set the igntc flag.
If true, truncated packets will be ignored.
If false, the query will be retried using TCP.
The default is false.

=head2 errorstring

    print 'query status: ', $resolver->errorstring, "\n";

Returns a string containing the status of the most recent query.

=head2 answerfrom

    print 'last answer was from: ', $resolver->answerfrom, "\n";

Returns the IP address from which the most recent packet was
received in response to a query.

=head2 answersize

    print 'size of last answer: ', $resolver->answersize, "\n";

Returns the size in bytes of the most recent packet received in
response to a query.


=head2 dnssec

    print "dnssec flag: ", $resolver->dnssec, "\n";
    $resolver->dnssec(0);

The dnssec flag causes the resolver to transmit DNSSEC queries
and to add a EDNS0 record as required by RFC2671 and RFC3225.
The actions of, and response from, the remote nameserver is
determined by the settings of the AD and CD flags.

Calling the dnssec() method with a non-zero value will also set the
UDP packet size to the default value of 2048. If that is too small or
too big for your environment, you should call the udppacketsize()
method immediately after.

   $resolver->dnssec(1);		# DNSSEC using default packetsize
   $resolver->udppacketsize(1250);	# lower the UDP packet size

A fatal exception will be raised if the dnssec() method is called
but the Net::DNS::SEC library has not been installed.


=head2 adflag

    $resolver->dnssec(1);
    $resolver->adflag(1);
    print "authentication desired flag: ", $resolver->adflag, "\n";

Gets or sets the AD bit for dnssec queries.  This bit indicates that
the caller is interested in the returned AD (authentic data) bit but
does not require any dnssec RRs to be included in the response.
The default value is 0.


=head2 cdflag

    $resolver->dnssec(1);
    $resolver->cdflag(1);
    print "checking disabled flag: ", $resolver->cdflag, "\n";

Gets or sets the CD bit for dnssec queries.  This bit indicates that
authentication by upstream nameservers should be suppressed.
Any dnssec RRs required to execute the authentication procedure
should be included in the response.
The default value is 0.


=head2 udppacketsize

    print "udppacketsize: ", $resolver->udppacketsize, "\n";
    $resolver->udppacketsize(2048);

udppacketsize will set or get the packet size. If set to a value
greater than the default DNS packet size, an EDNS extension will be
added indicating support for UDP fragment reassembly.


=head1 ENVIRONMENT

The following environment variables can also be used to configure
the resolver:

=head2 RES_NAMESERVERS

    # Bourne Shell
    RES_NAMESERVERS="192.0.2.1 192.0.2.2 2001:DB8::3"
    export RES_NAMESERVERS

    # C Shell
    setenv RES_NAMESERVERS "192.0.2.1 192.0.2.2 2001:DB8::3"

A space-separated list of nameservers to query.

=head2 RES_SEARCHLIST

    # Bourne Shell
    RES_SEARCHLIST="a.example.com b.example.com c.example.com"
    export RES_SEARCHLIST

    # C Shell
    setenv RES_SEARCHLIST "a.example.com b.example.com c.example.com"

A space-separated list of domains to put in the search list.

=head2 LOCALDOMAIN

    # Bourne Shell
    LOCALDOMAIN=example.com
    export LOCALDOMAIN

    # C Shell
    setenv LOCALDOMAIN example.com

The default domain.

=head2 RES_OPTIONS

    # Bourne Shell
    RES_OPTIONS="retrans:3 retry:2 debug"
    export RES_OPTIONS

    # C Shell
    setenv RES_OPTIONS "retrans:3 retry:2 debug"

A space-separated list of resolver options to set.  Options that
take values are specified as C<option:value>.


=head1 IPv6 TRANSPORT

The Net::DNS::Resolver library will enable IPv6 transport if the
appropriate libraries (Socket6 and IO::Socket::INET6) are available
and the destination nameserver has at least one IPv6 address.

The force_v4(), force_v6() and prefer_v6() methods with a non-zero
argument may be used to configure transport selection.

The behaviour of the nameserver() method illustrates the transport
selection mechanism.  If, for example, IPv6 is not available or IPv4
transport has been forced, the nameserver() method will only return
IPv4 addresses:

    $resolver->nameservers( '192.0.2.1', '192.0.2.2', '2001:DB8::3' );
    $resolver->force_v4(1);
    print join ' ', $resolver->nameservers();

will print

    192.0.2.1 192.0.2.2


=head1 CUSTOMISED RESOLVERS

Net::DNS::Resolver is actually an empty subclass.  At compile time a
super class is chosen based on the current platform.  A side benefit of
this allows for easy modification of the methods in Net::DNS::Resolver.
You can simply add a method to the namespace!

For example, if we wanted to cache lookups:

    package Net::DNS::Resolver;

    my %cache;

    sub search {
	$self = shift;

	$cache{"@_"} ||= $self->SUPER::search(@_);
    }


=head1 BUGS

The current implementation supports TSIG only on outgoing packets.
No validation of server replies is performed.

bgsend() does not honour the usevc flag and only uses UDP for transport.

=head1 COPYRIGHT

Copyright (c)1997-2002 Michael Fuhr.

Portions Copyright (c)2002-2004 Chris Reinhardt.

Portions Copyright (c)2005 Olaf M. Kolkman, NLnet Labs.

Portions Copyright (c)2014 Dick Franks.

All rights reserved.  This program is free software; you may redistribute
it and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl>, L<Net::DNS>, L<Net::DNS::Packet>, L<Net::DNS::Update>,
L<Net::DNS::Header>, L<Net::DNS::Question>, L<Net::DNS::RR>,
L<resolver(5)>, RFC 1035, RFC 1034 Section 4.3.5

=cut
