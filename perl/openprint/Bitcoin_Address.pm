use strict;
use Data::Dumper;

require openprint::Object_Type;
package openprint::Bitcoin_Address;
our @ISA = qw(openprint::Object);
use vars qw( $debug $table $serial %fields %find_fields %defaults %transforms );

$debug = 0;
$table = 'bitcoin_addresses';
$serial = 'bitcoin_addresses_id_seq';
%fields = (
	id				=>	'id',
	object_type_id	=>	'object_type_id',
	object_type		=>	undef,
	object_id		=>	'object_id',
	address			=>	'address',
);
%find_fields = (
	object_type	=>	'(SELECT name FROM object_types WHERE id=object_type_id)',
);
%defaults = (
	created_on	=>	q`'NOW()'`,
	deleted		=>	0,
	approved	=>	0,
	user_id		=>	q`$session{user_id}`,
	approved	=>	0,
	address		=>	undef,
);

 

sub generate {

	my $ac = sql::start_transaction( $openprint::dbh );
	$openprint::dbh->do( "LOCK TABLE $table IN ACCESS EXCLUSIVE MODE" ) or $openprint::log->error( DBI->errstr );
	if ( $_[1] ) {
		my $Old = openprint::Bitcoin_Address->find_one( object_id=>$_[1]{id}, object_type=>ref $_[1]);
		if ( $Old ) {
			sql::end_transaction( $openprint::dbh, $ac );
			return $Old 
		} # end if
	} # end if
	my $New = openprint::Bitcoin_Address->find_one('object_id is null'=>1);
	if ( ! $New ) {
eval {
		require Finance::Bitcoin;
		require Finance::Bitcoin::API;
		require Finance::Bitcoin::Wallet;
		my $uri     = "http://$openprint::config{bitcoin_user}:$openprint::config{bitcoin_password}\@$openprint::config{bitcoin_server}:$openprint::config{bitcoin_port}/";
$openprint::log->debug($uri);

		my $api     = Finance::Bitcoin::API->new( endpoint => $uri );

		my $label = (ref $_[1]) . ' ' . $_[1]->id();
		#$openprint::log->debug( "URI: $uri label: $label");

		my $wallet = Finance::Bitcoin::Wallet->new($api);
		$_ = Data::Dumper::Dumper($wallet);
		$openprint::log->debug($_);

		my $address = $wallet->create_address( $label );
		$_ = Data::Dumper::Dumper($wallet);
		$openprint::log->debug($_);
		if ( $address and $address->address ) {

			$New = new openprint::Bitcoin_Address();
			$New->save({address=>$address->address(),object_type=>ref $_[1], object_id=>$_[1]{id}});
		} else {
			$openprint::log->error('Error generating an address: ('.$address.') ('.$address->address.')');
			$_ = Data::Dumper::Dumper($address);
			$openprint::log->debug($_);

		} # end if
};
				$openprint::log->error( "Eval error of BitcoinAddress Reason: " . $@ ) if $@;
	} else {
		$New->save({object_type=>ref $_[1], object_id=>$_[1]{id}});
	} # end if ! New
	sql::end_transaction( $openprint::dbh, $ac );
	return $New;
} # end sub generate
1;
__END__
