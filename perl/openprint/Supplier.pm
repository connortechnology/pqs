use strict;
package openprint::Supplier;

require openprint;
require sql;
require openprint::Company;

sub get_or_create {
	my ( $name ) = @_;

	my $ac = sql::start_transaction( $openprint::dbh );
	$openprint::dbh->do( 'LOCK TABLE companies IN SHARE ROW EXCLUSIVE MODE' ) or $openprint::log->error( $openprint::dbh->errstr );
	my $error;

	my $C;

	if ( $name ) {
		my @Companies = openprint::Company->find( name=>$name );
		@Companies = openprint::Company->find( name=>$name, deleted=>1 ) if ! @Companies;
		if ( ! @Companies ) {
			$C = new openprint::Company();
			$error .= $C->save({
					supplier        => 'Y',
					name            => $name,
					business_name   => $name,
					} );
		} elsif ( @Companies == 1 ) {
			$C = $Companies[0];
			if ( $C->supplier() ne 'Y' ) {
				$error .= $C->save( { supplier=>'Y' } );
			} # end if
			if ( $C->deleted() ) {
				$error .= $C->save( { deleted=>0 } );
			} # end if
		} # end if
	} # end if supplier and ! supplier_id
	sql::end_transaction( $openprint::dbh, $ac );
	return $C->id();
} # end get_or_create

1;
__END__
