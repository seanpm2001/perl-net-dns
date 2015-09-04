# $Id$ -*-perl-*-

use strict;
use Test::More;
use t::NonFatal;

use Net::DNS;
use Net::DNS::Resolver::Recurse;


exit( plan skip_all => 'Online tests disabled.' ) if -e 't/online.disabled';
exit( plan skip_all => 'Online tests disabled.' ) unless -e 't/online.enabled';


my @hints = new Net::DNS::Resolver::Recurse()->_hints;


eval {
	my $res = new Net::DNS::Resolver( retry => 1 );
	exit plan skip_all => "No nameservers" unless $res->nameservers;

	my $reply = $res->send( ".", "NS" ) || die;

	my @ns = grep $_->type eq 'NS', $reply->answer, $reply->authority;
	exit plan skip_all => "Local nameserver broken" unless scalar @ns;

	1;
};
# } || exit( plan skip_all => "Non-responding local nameserver" );


eval {
	my $res = new Net::DNS::Resolver( retry => 1 );
	exit plan skip_all => "No nameservers" unless $res->nameservers(@hints);

	my $reply = $res->send( ".", "NS" ) || die;

	my @ns = grep $_->type eq 'NS', $reply->answer, $reply->authority;
	exit plan skip_all => "Unexpected response from root server" unless scalar @ns;

	1;
};
# } || exit( plan skip_all => "Unable to access global root nameservers" );


plan 'no_plan';

NonFatalBegin();

{
	my $res = Net::DNS::Resolver::Recurse->new( debug => 0 );

	ok( $res->isa('Net::DNS::Resolver::Recurse'), 'new() created object' );

	$res->udp_timeout(20);

	my $packet = $res->query_dorecursion( "www.google.com.", "A" );
	ok( $packet, 'got a packet' );
	ok( scalar $packet->answer, 'answer section has RRs' ) if $packet;
}


{
	# test hints()
	my $res = Net::DNS::Resolver::Recurse->new( debug => 0 );

	$res->udp_timeout(20);

	ok( scalar( $res->hints(@hints) ), "hints() set" );

	my $packet = $res->query_dorecursion( 'www.net-dns.org', 'A' );
	ok( $packet, 'got a packet' );
	ok( scalar $packet->answer, 'answer section has RRs' ) if $packet;
}


{
	# test the callback
	my $res = Net::DNS::Resolver::Recurse->new( debug => 0 );

	my $count = 0;

	$res->recursion_callback(
		sub {
			ok( shift->isa('Net::DNS::Packet'), 'callback argument is a packet' );
			$count++;
		} );

	$res->query_dorecursion( 'a.t.net-dns.org', 'A' );

	ok( $count >= 3, "Lookup took $count queries which is at least 3" );
}


{
	my $res = Net::DNS::Resolver::Recurse->new( debug => 0 );

	my $count = 0;

	$res->recursion_callback(
		sub {
			$count++;
		} );

	$res->query_dorecursion( '2a04:b900:0:0:8:0:0:60', 'A' );

	ok( $count >= 3, "Reverse lookup took $count queries" );
}


NonFatalEnd();

exit;
