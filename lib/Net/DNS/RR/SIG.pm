
#	pre-5.14.0 perl inadvertently destroys signal handlers
#	http://rt.perl.org/rt3/Public/Bug/Display.html?id=76138
#
BEGIN {					## capture %SIG before compilation
	@::SIG_BACKUP = %SIG if eval { $] < 5.014 };
}

sub UNITCHECK {				## restore %SIG after compilation
	%SIG = @::SIG_BACKUP if eval { $] < 5.014 };
}


package Net::DNS::RR::SIG;

#
# $Id$
#
use vars qw($VERSION);
$VERSION = (qw$LastChangedRevision$)[1];


use strict;
use base qw(Net::DNS::RR);

=head1 NAME

Net::DNS::RR::SIG - DNS SIG resource record

=cut


use integer;

use warnings;
use Carp;

my $debug = 0;

use Net::DNS::Parameters;
use MIME::Base64;
use Time::Local;

use constant UTIL => eval { require Scalar::Util; } || 0;

use constant PRIVATE => eval { require Net::DNS::SEC::Private; } || 0;

use constant DSA => eval { require Net::DNS::SEC::DSA; 'Net::DNS::SEC::DSA' } || 0;
use constant RSA => eval { require Net::DNS::SEC::RSA; 'Net::DNS::SEC::RSA' } || 0;

use constant DNSSEC => PRIVATE && ( RSA || DSA );

my @field = qw(typecovered algorithm labels orgttl sigexpiration siginception keytag);


sub decode_rdata {			## decode rdata from wire-format octet string
	my $self = shift;
	my ( $data, $offset, @opaque ) = @_;

	my $limit = $offset + $self->{rdlength};
	@{$self}{@field} = unpack "\@$offset n C2 N3 n", $$data;
	( $self->{signame}, $offset ) = decode Net::DNS::DomainName2535( $data, $offset + 18 );
	$self->{sigbin} = substr $$data, $offset, $limit - $offset;

	return if $self->{typecovered};
	croak('misplaced or corrupt SIG') unless $limit == length $$data;
	my $raw = substr $$data, 0, $self->{offset} || return;
	$self->{rawref} = \$raw;
}


sub encode_rdata {			## encode rdata as wire-format octet string
	my $self = shift;
	my ( $offset, @opaque ) = @_;

	my ( $hash, $packet ) = @opaque;

	my $signame = $self->{signame} || return '';

	unless ( $self->{sigbin} ) {
		my $private = $self->{private};
		delete $self->{private};			# one shot is all you get

		die 'missing packet reference' unless $packet;
		my $sigdata = $self->_CreateSigData($packet);
		$self->_CreateSig( $sigdata, $private || die 'missing key reference' );
	}

	pack 'n C2 N3 n a* a*', @{$self}{@field}, $signame->encode, $self->sigbin;
}


sub format_rdata {			## format rdata portion of RR string.
	my $self = shift;

	my @sig64 = split /\s+/, encode_base64( $self->sigbin || return '' );
	my @rdata = map( $self->$_, @field ), $self->{signame}->string, @sig64;
}


sub parse_rdata {			## populate RR from rdata in argument list
	my $self = shift;

	for ( @field, qw(signame) ) {
		$self->$_(shift) if scalar @_;
	}
	$self->signature(@_);
}


sub defaults() {			## specify RR attribute default values
	my $self = shift;

	$self->class('ANY');
	$self->parse_rdata( 'TYPE0', 1, 0, 0 );
}


#
# source: http://www.iana.org/assignments/dns-sec-alg-numbers
#
{
	my @algbyname = (		## Reserved	=> 0,	# [RFC4034][RFC4398]
		'RSAMD5'	     => 1,			# [RFC3110][RFC4034]
		'DH'		     => 2,			# [RFC2539]
		'DSA'		     => 3,			# [RFC3755][RFC2536]
					## Reserved	=> 4,	# [RFC6725]
		'RSASHA1'	     => 5,			# [RFC3110][RFC4034]
		'DSA-NSEC3-SHA1'     => 6,			# [RFC5155]
		'RSASHA1-NSEC3-SHA1' => 7,			# [RFC5155]
		'RSASHA256'	     => 8,			# [RFC5702]
					## Reserved	=> 9,	# [RFC6725]
		'RSASHA512'	     => 10,			# [RFC5702]
					## Reserved	=> 11,	# [RFC6725]
		'ECC-GOST'	     => 12,			# [RFC5933]
		'ECDSAP256SHA256'    => 13,			# [RFC6605]
		'ECDSAP384SHA384'    => 14,			# [RFC6605]

		'INDIRECT'   => 252,				# [RFC4034]
		'PRIVATEDNS' => 253,				# [RFC4034]
		'PRIVATEOID' => 254,				# [RFC4034]
					## Reserved	=> 255,	# [RFC4034]
		);

	my %algbyval = reverse @algbyname;

	my @algbynum = map { ( $_, 0 + $_ ) } ( 1 .. 250, keys %algbyval );

	my %algbyname = map { s/[^A-Za-z0-9]//g; $_ } @algbyname, @algbynum;

	sub algbyname {
		my $name = shift;
		my $key	 = uc $name;				# synthetic key
		$key =~ s/[^A-Z0-9]//g;				# strip non-alphanumerics
		return $algbyname{$key} || croak "unknown algorithm $name";
	}

	sub algbyval {
		my $value = shift;
		return $algbyval{$value} || $value;
	}
}


my %SEC = (
	1 => RSA,
	3 => DSA,
	5 => RSA,
	6 => DSA,
	7 => RSA,
	);


sub typecovered {
	my $self = shift;
	$self->{typecovered} = typebyname(shift) if scalar @_;
	return typebyval( $self->{typecovered} );
}


sub algorithm {
	my ( $self, $arg ) = @_;

	unless ( ref($self) ) {		## class method or simple function
		my $argn = pop || croak 'undefined argument';
		return $argn =~ /[^0-9]/ ? algbyname($argn) : algbyval($argn);
	}

	return $self->{algorithm} unless defined $arg;
	return algbyval( $self->{algorithm} ) if $arg =~ /MNEMONIC/i;
	return $self->{algorithm} = algbyname($arg);
}


sub labels {
	my $self = shift;
	$self->{labels} = 0 + shift if scalar @_;
	return $self->{labels} || 0;
}


sub orgttl {
	my $self = shift;
	$self->{orgttl} = 0 + shift if scalar @_;
	return $self->{orgttl} || 0;
}


sub sigexpiration {
	my $self = shift;
	$self->{sigexpiration} = _string2time(shift) if scalar @_;
	return unless defined wantarray;
	my $time = $self->{sigexpiration};
	return UTIL ? Scalar::Util::dualvar( $time, _time2string($time) ) : _time2string($time);
}

sub siginception {
	my $self = shift;
	$self->{siginception} = _string2time(shift) if scalar @_;
	return unless defined wantarray;
	my $time = $self->{siginception};
	return UTIL ? Scalar::Util::dualvar( $time, _time2string($time) ) : _time2string($time);
}


sub keytag {
	my $self = shift;

	$self->{keytag} = 0 + shift if scalar @_;
	return $self->{keytag} || 0;
}


sub signame {
	my $self = shift;

	$self->{signame} = new Net::DNS::DomainName2535(shift) if scalar @_;
	$self->{signame}->name if defined wantarray && $self->{signame};
}


sub signature {
	my $self = shift;

	return encode_base64( $self->sigbin, '' ) unless scalar @_;
	return $self->sigbin( decode_base64( join '', @_ ) );
}

sub sig { &signature; }


sub sigbin {
	my $self = shift;

	$self->{sigbin} = shift if scalar @_;
	$self->{sigbin} || "";
}


sub create {
	my ( $class, $data, $priv_key, %args ) = @_;

	croak 'Net::DNS::SEC support not available' unless DNSSEC;

	my $private = ref($priv_key) ? $priv_key : Net::DNS::SEC::Private->new($priv_key);
	croak 'Unable to parse private key' unless ref($private) eq 'Net::DNS::SEC::Private';

	my $self = new Net::DNS::RR(
		type	    => 'SIG',
		typecovered => 'TYPE0',
		siginception  => $args{sigin} || time(),
		sigexpiration => $args{sigex} || 0,
		algorithm     => $private->algorithm,
		keytag	      => $private->keytag,
		signame	      => $private->signame,
		);

	$args{sigval} ||= 10 unless $self->{sigexpiration};
	if ( $args{sigval} ) {
		my $sigin = $self->{siginception};
		my $sigval = eval { no integer; int( $args{sigval} * 60 ) };
		$self->sigexpiration( $sigin + $sigval );
	}

	unless ($data) {					# mark packet for SIG0 generation
		$self->{private} = $private;
		return $self;
	}

	my $sigdata = $self->_CreateSigData($data);
	$self->_CreateSig( $sigdata, $private );

	return $self;
}


sub verify {
	my ( $self, $dataref, $keyref ) = @_;

	# Reminder...

	# $dataref may be either a data string or a reference to a
	# Net::DNS::Packet object.
	#
	# $keyref is either a key object or a reference to an array
	# of keys.

	if ( my $isa = ref($dataref) ) {
		print "First argument is of class $isa\n" if $debug;
		croak "verify argument can not be $isa"	  unless $isa =~ /Net::DNS::/;
		croak 'SIG RR deprecated except for SIG0' unless $dataref->isa('Net::DNS::Packet');
	}

	print "Second argument is of class ", ref($keyref), "\n" if $debug;
	if ( ref($keyref) eq "ARRAY" ) {

		#  We will recurse for each key that matches algorithm and key-id
		#  and return when there is a successful verification.
		#  If not, we'll continue so that we even survive key-id collision.
		#  The downside of this is that the error string only matches the
		#  last error.

		my $errorstring = "";
		print "Iterating over ", scalar @$keyref, " keys\n" if $debug;
		my $i = 0;
		foreach my $keyrr (@$keyref) {
			$i++;
			unless ( $self->algorithm == $keyrr->algorithm ) {
				print "key $i: algorithm does not match\n" if $debug;
				$errorstring .= "key $i: algorithm does not match ";
				next;
			}
			unless ( $self->keytag == $keyrr->keytag ) {
				print "key $i: keytag does not match (", $keyrr->keytag, " ", $self->keytag, ")\n"
						if $debug;
				$errorstring .= "key $i: keytag does not match ";
				next;
			}

			my $result = $self->verify( $dataref, $keyrr );
			print "key $i: ", $self->{vrfyerrstr} if $debug;
			return $result if $result;
			$errorstring .= "key $i:" . $self->vrfyerrstr . " ";
		}

		$self->{vrfyerrstr} = $errorstring;
		return (0);

	} elsif ( $keyref->isa('Net::DNS::RR::DNSKEY') || $keyref->isa('Net::DNS::RR::KEY') ) {

		print "Validating using key with keytag: ", $keyref->keytag, "\n" if $debug;

	} else {
		$self->{vrfyerrstr} = join ' ', ref($keyref), 'can not be used as SIG0 key';
		return (0);
	}


	$self->{vrfyerrstr} = '';
	if ($debug) {
		print "\n ---------------------- SIG DEBUG ------------------------------";
		print "\n  SIG:\t", $self->string;
		print "\n  KEY:\t", $keyref->string;
		print "\n ---------------------------------------------------------------\n";
	}

	croak "Trying to verify SIG0 using non-SIG0 signature" unless $self->typecovered eq 'TYPE0';

	if ( $self->algorithm != $keyref->algorithm ) {
		$self->{vrfyerrstr} = join ' ',
				'signature created using algorithm',   $self->algorithm,
				'can not be verified using algorithm', $keyref->algorithm;
		return 0;
	}

	# The data that is to be verified
	my $sigdata = $self->_CreateSigData($dataref);

	my $verified = $self->_VerifySig( $sigdata, $keyref ) || return 0;

	# time to do some time checking.
	my $t = time;

	if ( _ordered( $self->{sigexpiration}, $t ) ) {
		$self->{vrfyerrstr} = join ' ', 'Signature expired at', $self->sigexpiration;
		return 0;
	} elsif ( _ordered( $t, $self->{siginception} ) ) {
		$self->{vrfyerrstr} = join ' ', 'Signature valid from', $self->siginception;
		return 0;
	}

	return 1;
}								#END verify


sub vrfyerrstr {
	my $self = shift;
	$self->{vrfyerrstr} || '';
}


########################################

sub _ordered($$) {			## irreflexive 32-bit partial ordering
	use integer;
	my ( $a, $b ) = @_;

	return defined $b unless defined $a;			# ( undef, any )
	return 0 unless defined $b;				# ( any, undef )

	# unwise to assume 32-bit arithmetic, or that integer overflow goes unpunished
	if ( $a < 0 ) {						# translate $a<0 region
		$a = ( $a ^ 0x80000000 ) & 0xFFFFFFFF;		#  0	 <= $a < 2**31
		$b = ( $b ^ 0x80000000 ) & 0xFFFFFFFF;		# -2**31 <= $b < 2**32
	}

	return $a < $b ? ( $a > ( $b - 0x80000000 ) ) : ( $b < ( $a - 0x80000000 ) );
}


my $y1998 = timegm( 0, 0, 0, 1, 0, 1998 );
my $y2026 = timegm( 0, 0, 0, 1, 0, 2026 );
my $y2082 = $y2026 << 1;
my $y2054 = $y2082 - $y1998;

sub _string2time {			## parse time specification string
	my $arg = shift;
	croak 'undefined time' unless defined $arg;
	return int($arg) if length($arg) < 12;
	my ( $y, $m, @dhms ) = unpack 'a4 a2 a2 a2 a2 a2', $arg . '00';
	unless ( $arg gt '20380119031407' ) {			# calendar folding
		return timegm( reverse(@dhms), $m - 1, $y ) if $y < 2026;
		return timegm( reverse(@dhms), $m - 1, $y - 56 ) + $y2026;
	} elsif ( $y > 2082 ) {
		my $z = timegm( reverse(@dhms), $m - 1, $y - 84 );    # expunge 29 Feb 2100
		return $z < 1456790400 ? $z + $y2054 : $z + $y2054 - 86400;
	}
	return ( timegm( reverse(@dhms), $m - 1, $y - 56 ) + $y2054 ) - $y1998;
}


sub _time2string {			## format time specification string
	my $arg = shift;
	croak 'undefined time' unless defined $arg;
	unless ( $arg < 0 ) {
		my ( $yy, $mm, @dhms ) = reverse( ( gmtime $arg )[0 .. 5] );
		return sprintf '%d%02d%02d%02d%02d%02d', $yy + 1900, $mm + 1, @dhms;
	} elsif ( $arg > $y2082 ) {
		$arg += 86400 unless $arg < $y2054 + 1456704000;      # expunge 29 Feb 2100
		my ( $yy, $mm, @dhms ) = reverse( ( gmtime( $arg - $y2054 ) )[0 .. 5] );
		return sprintf '%d%02d%02d%02d%02d%02d', $yy + 1984, $mm + 1, @dhms;
	}
	my ( $yy, $mm, @dhms ) = reverse( ( gmtime( $arg - $y2026 ) )[0 .. 5] );
	return sprintf '%d%02d%02d%02d%02d%02d', $yy + 1956, $mm + 1, @dhms;
}


sub _CreateSigData {
	my ( $self, $message ) = @_;

	if ( ref($message) ) {
		die 'missing packet reference' unless $message->isa('Net::DNS::Packet');
		my @unsigned = grep ref($_) ne ref($self), @{$message->{additional}};
		local $message->{additional} = \@unsigned;	# remake header image
		my @part = qw(question answer authority additional);
		my @size = map scalar( @{$message->{$_}} ), @part;
		my $rref = $self->{rawref};
		delete $self->{rawref};
		my $data = $rref ? $$rref : $message->data;
		my ( $id, $status ) = unpack 'n2', $data;
		my $hbin = pack 'n6 a*', $id, $status, @size;
		$message = $hbin . substr $data, length $hbin;
	}

	my @field = qw(typecovered algorithm labels orgttl sigexpiration siginception keytag);
	my $sigdata = pack 'n C2 N3 n a*', @{$self}{@field}, $self->{signame}->encode;
	print "\npreamble\t", unpack( 'H*', $sigdata ), "\nrawdata\t", unpack( 'H100', $message ), " ...\n" if $debug;
	return join '', $sigdata, $message;
}


########################################

sub _CreateSig {
	my $self = shift;

	my $algorithm = $self->algorithm;

	eval {
		my $class = $SEC{$algorithm} || die "algorithm $algorithm not supported";
		$self->sigbin( $class->sign(@_) );
	} || croak 'signature generation failed', $@ ? "\n\t$@" : '';
}


sub _VerifySig {
	my $self = shift;

	my $algorithm = $self->algorithm;

	my $retval = eval {
		my $class = $SEC{$algorithm} || die "algorithm $algorithm not supported";
		$class->verify( @_, $self->sigbin );
	} || do {
		$self->{vrfyerrstr} = 'signature verification failed';
		$self->{vrfyerrstr} .= "\n\t$@" if $@;
		print "\n", $self->{vrfyerrstr}, "\n" if $debug;
		return 0;
	};

	croak "unknown error in algorithm $algorithm verify" unless $retval == 1;
	print "\nalgorithm $algorithm verification successful\n" if $debug;
	return 1;
}


1;
__END__


=head1 SYNOPSIS

    use Net::DNS;
    $rr = new Net::DNS::RR('name SIG typecovered algorithm labels
				orgttl sigexpiration siginception
				keytag signame signature');

    use Net::DNS::SEC;
    $sigrr = create Net::DNS::RR::SIG( $string, $keypath,
					sigval => 10	# minutes
					);

    $sigrr->verify( $string, $keyrr ) || die $sigrr->vrfyerrstr;
    $sigrr->verify( $packet, $keyrr ) || die $sigrr->vrfyerrstr;

=head1 DESCRIPTION

Class for DNS digital signature (SIG) resource records.

In addition to the regular methods inherited from Net::DNS::RR the
class contains a method to sign packets and scalar data strings
using private keys (create) and a method for verifying signatures.

The SIG RR is an implementation of RFC2931. 
See L<Net::DNS::RR::RRSIG> for an implementation of RFC4034.

=head1 METHODS

The available methods are those inherited from the base class augmented
by the type-specific methods defined in this package.

Use of undocumented package features or direct access to internal data
structures is discouraged and could result in program termination or
other unpredictable behaviour.


=head2 algorithm

    $algorithm = $rr->algorithm;

The algorithm number field identifies the cryptographic algorithm
used to create the signature.

algorithm() may also be invoked as a class method or simple function
to perform mnemonic and numeric code translation.

=head2 sigexpiration and siginception time

    $expiration = $rr->sigexpiration;
    $expiration = $rr->sigexpiration( $value );

    $inception = $rr->siginception;
    $inception = $rr->siginception( $value );

The signature expiration and inception fields specify a validity
time interval for the signature.

The value may be specified by a string with format 'yyyymmddhhmmss'
or a Perl time() value.

Return values are dual-valued, providing either a string value or
numerical Perl time() value.

=head2 keytag

    $keytag = $rr->keytag;
    $rr->keytag( $keytag );

The keytag field contains the key tag value of the KEY RR that
validates this signature.

=head2 signame

    $signame = $rr->signame;
    $rr->signame( $signame );

The signer name field value identifies the owner name of the KEY
RR that a validator is supposed to use to validate this signature.

=head2 signature

    $signature = $rr->signature;

The Signature field contains the cryptographic signature that covers
the SIG RDATA (excluding the Signature field) and the subject data.

=head2 sigbin

    $sigbin = $rr->sigbin;
    $rr->sigbin( $sigbin );

Binary representation of the cryptographic signature.

=head2 create

Create a signature over scalar data.

    use Net::DNS::SEC;

    $keypath = '/home/olaf/keys/Kbla.foo.+001+60114.private';

    $sigrr = create Net::DNS::RR::SIG( $data, $keypath );

    $sigrr = create Net::DNS::RR::SIG( $data, $keypath,
					sigval => 10
					);
    $sigrr->print;


    # Alternatively use Net::DNS::SEC::Private 

    $private = Net::DNS::SEC::Private->new($keypath);

    $sigrr= create Net::DNS::RR::SIG( $data, $private );


create() is an alternative constructor for a SIG RR object.  

This method returns a SIG with the signature over the data made with
the private key stored in the key file.

The first argument is a scalar that contains the data to be signed.

The second argument is a string which specifies the path to a file
containing the private key as generated with dnssec-keygen, a program
that comes with the ISC BIND distribution.

The optional remaining arguments consist of ( name => value ) pairs
as follows:

	sigin  => 20151201010101,	# signature inception
	sigex  => 20151201011101,	# signature expiration
	sigval => 10,			# validity window (minutes)

The sigin and sigex values may be specified as Perl time values or as
a string with the format 'yyyymmddhhmmss'. The default for sigin is
the time of signing. 

The sigval argument specifies the signature validity window in minutes
( sigex = sigin + sigval ).

By default the signature is valid for 10 minutes.

=over 4

=item *

Do not change the name of the file generated by dnssec-keygen, the
create method uses the filename as generated by dnssec-keygen to
determine the keyowner, algorithm and the keyid (keytag).

=back

=head2 verify

    $verify = $sigrr->verify( $data, $keyrr );
    $verify = $sigrr->verify( $data, [$keyrr, $keyrr2, $keyrr3] );

The verify() method performs SIG0 verification of the specified data
against the signature contained in the $sigrr object itself using
the public key in $keyrr.

If a reference to a Net::DNS::Packet is supplied, the method performs
a SIG0 verification on the packet data.

The second argument can either be a Net::DNS::RR::KEYRR object or a
reference to an array of such objects. Verification will return
successful as soon as one of the keys in the array leads to positive
validation.

Returns false on error and sets $sig->vrfyerrstr

=head2 vrfyerrstr

    $sig0 = $packet->sigrr || die 'not signed';
    print $sig0->vrfyerrstr unless $sig0->verify( $packet, $keyrr );

    $sigrr->verify( $packet, $keyrr ) || die $sigrr->vrfyerrstr;

=head1 REMARKS

The code is not optimized for speed.

If this code is still around in 2100 (not a leapyear) you will need
to check for proper handling of times ...

=head1 ACKNOWLEDGMENTS

Andy Vaskys (Network Associates Laboratories) supplied the code for
handling RSA with SHA1 (Algorithm 5).

T.J. Mather, the Crypt::OpenSSL::DSA maintainer, for his quick
responses to bug report and feature requests.


=head1 COPYRIGHT

Copyright (c)2001-2005 RIPE NCC,   Olaf M. Kolkman

Copyright (c)2007-2008 NLnet Labs, Olaf M. Kolkman

Portions Copyright (c)2014 Dick Franks

All rights reserved.

Package template (c)2009,2012 O.M.Kolkman and R.W.Franks.


=head1 LICENSE

Permission to use, copy, modify, and distribute this software and its
documentation for any purpose and without fee is hereby granted, provided
that the above copyright notice appear in all copies and that both that
copyright notice and this permission notice appear in supporting
documentation, and that the name of the author not be used in advertising
or publicity pertaining to distribution of the software without specific
prior written permission.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.


=head1 SEE ALSO

L<perl>, L<Net::DNS>, L<Net::DNS::RR>, L<Net::DNS::SEC>,
RFC4034, RFC3755, RFC2535, RFC2931, RFC3110, RFC3008,
L<Net::DNS::SEC::DSA>,
L<Net::DNS::SEC::RSA>

L<Algorithm Numbers|http://www.iana.org/assignments/dns-sec-alg-numbers>

L<BIND 9 Administrator Reference Manual|http://www.bind9.net/manuals>

=cut
