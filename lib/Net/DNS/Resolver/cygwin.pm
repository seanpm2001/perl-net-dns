package Net::DNS::Resolver::cygwin;

#
# $Id$
#
use vars qw($VERSION);
$VERSION = (qw$LastChangedRevision$)[1];

=head1 NAME

Net::DNS::Resolver::cygwin - Cygwin Resolver Class

=cut


use strict;
use base qw(Net::DNS::Resolver::Base);


sub getregkey {
	my $key	  = $_[0] . $_[1];
	my $value = '';

	local *LM;

	if ( open( LM, "<$key" ) ) {
		$value = <LM>;
		$value =~ s/\0+$// if $value;
		close(LM);
	}

	return $value;
}


sub init {
	my ($class) = @_;
	my $defaults = $class->defaults;

	local *LM;

	my $root = '/proc/registry/HKEY_LOCAL_MACHINE/SYSTEM/CurrentControlSet/Services/Tcpip/Parameters/';

	unless ( -d $root ) {

		# Doesn't exist, maybe we are on 95/98/Me?
		$root = '/proc/registry/HKEY_LOCAL_MACHINE/SYSTEM/CurrentControlSet/Services/VxD/MSTCP/';
		-d $root || Carp::croak "can't read registry: $!";
	}

	# Best effort to find a useful domain name for the current host
	# if domain ends up blank, we're probably (?) not connected anywhere
	# a DNS server is interesting either...
	my $domain = getregkey( $root, 'Domain' ) || getregkey( $root, 'DhcpDomain' ) || '';

	# If nothing else, the searchlist should probably contain our own domain
	# also see below for domain name devolution if so configured
	# (also remove any duplicates later)
	my $searchlist = "$domain ";
	$searchlist .= getregkey( $root, 'SearchList' );

	# This is (probably) adequate on NT4
	my @nt4nameservers = split getregkey( $root, 'NameServer' ) || getregkey( $root, 'DhcpNameServer' );
	my @nameservers;

	#
	# but on W2K/XP the registry layout is more advanced due to dynamically
	# appearing connections. So we attempt to handle them, too...
	# opt to silently fail if something isn't ok (maybe we're on NT4)
	# If this doesn't fail override any NT4 style result we found, as it
	# may be there but is not valid.
	# drop any duplicates later
	my $dnsadapters = $root . 'DNSRegisteredAdapters/';
	if ( opendir( LM, $dnsadapters ) ) {
		my @adapters = grep( $_ ne "." && $_ ne "..", readdir(LM) );
		closedir(LM);
		foreach my $adapter (@adapters) {
			my $regadapter = $dnsadapters . $adapter . '/';
			if ( -e $regadapter ) {
				my $ns = getregkey( $regadapter, 'DNSServerAddresses' ) || '';
				while ( length($ns) >= 4 ) {
					my $addr = join( '.', unpack( "C4", substr( $ns, 0, 4, "" ) ) );
					push @nameservers, $addr;
				}
			}
		}
	}

	my $interfaces = $root . 'Interfaces/';
	if ( opendir( LM, $interfaces ) ) {
		my @ifacelist = grep( $_ ne '.' && $_ ne '..', readdir(LM) );
		closedir(LM);
		foreach my $iface (@ifacelist) {
			my $regiface = $interfaces . $iface . '/';
			if ( opendir( LM, $regiface ) ) {
				closedir(LM);

				my $ns;
				my $ip;
				$ip = getregkey( $regiface, 'DhcpIPAddress' ) || getregkey( $regiface, 'IPAddress' );
				$ns = getregkey( $regiface, 'NameServer' )
					|| getregkey( $regiface, 'DhcpNameServer' )
					|| ''
					unless !$ip || ( $ip =~ /0\.0\.0\.0/ );

				push @nameservers, $ns if $ns;
			}
		}
	}

	@nameservers = @nt4nameservers unless @nameservers;
	$defaults->nameservers(@nameservers);

	$defaults->{domain} = $domain if $domain;

	my $usedevolution = getregkey( $root, 'UseDomainNameDevolution' );
	if ($searchlist) {

		# fix devolution if configured, and simultaneously make sure no dups (but keep the order)
		my @a;
		my %h;
		foreach my $entry ( split( m/[\s,]+/, $searchlist ) ) {
			push( @a, $entry ) unless $h{$entry}++;

			if ($usedevolution) {

				# as long there are more than two pieces, cut
				while ( $entry =~ m#\..+\.# ) {
					$entry =~ s#^[^\.]+\.(.+)$#$1#;
					push( @a, $entry ) unless $h{$entry}++;
				}
			}
		}
		$defaults->{searchlist} = [@a];
	}


	$class->read_env;


	if ( !$defaults->{domain} && @{$defaults->{searchlist}} ) {
		$defaults->{domain} = $defaults->{searchlist}[0];
	} elsif ( !@{$defaults->{searchlist}} && $defaults->{domain} ) {
		$defaults->{searchlist} = [$defaults->{domain}];
	}
}

1;
__END__


=head1 SYNOPSIS

    use Net::DNS::Resolver;

=head1 DESCRIPTION

This class implements the OS specific portions of C<Net::DNS::Resolver>.

No user serviceable parts inside, see L<Net::DNS::Resolver|Net::DNS::Resolver>
for all your resolving needs.

=head1 COPYRIGHT

Copyright (c)1997-2002 Michael Fuhr.

Portions Copyright (c)2002-2004 Chris Reinhardt.

All rights reserved.  This program is free software; you may redistribute
it and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<perl>, L<Net::DNS>, L<Net::DNS::Resolver>

=cut
