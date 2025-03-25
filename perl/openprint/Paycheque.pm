use strict;
require openprint::Paycheque_Timetrack;
package openprint::Paycheque;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %defaults %transforms );

$debug = 0;

$table = 'paycheques';
$serial = 'paycheque_id_seq';

%fields = (
	id				=>	'id',
	employer_id		=>	'employer_id',
	employee_id		=>	'employee_id',
	total			=>	'total',
	created_on		=>	'created_on',
	updated_on		=>	'updated_on',
	currency_id		=>	'currency_id',
	internal_notes	=>	'internal_notes',
	external_notes	=>	'external_notes',
	paid_on			=>	'paid_on',
	deleted			=>	'deleted',
);

%transforms = (
);
%defaults = (
	deleted		=>	0,
	created_on	=> q`'NOW()'`,
	updated_on	=> q`'NOW()'`,
	paid_on		=> q`'NOW()'`,
	total		=>	undef,
);


sub Employer {
	return new openprint::Company( $_[0]{employer_id} );
} # end sub Payor

sub Employee {
	return new openprint::User( $_[0]{employee_id} );
} # end sub Recipient

sub add_Timetrack {
	return (new openprint::Paycheque_Timetrack())->save({'paycheque_id'=>$_[0]{id}, 'timetrack_id'=>$_[1]{id}});
} # end sub add_Timetrack

sub del_Timetrack {
	return (new openprint::Paycheque_Timetrack({'paycheque_id'=>$_[0]{id}, 'timetrack_id'=>$_[1]{id}}))->delete();
} # end sub del_Timetrack

sub Timetracks {
	if ( ! $_[0]{Timetracks} ) {
		$_[0]{Timetracks} = [ openprint::Paycheque_Timetrack->find( paycheque_id => $_[0]{id}, order=>'timetrack_id' ) ];
	}
	return @{$_[0]{Timetracks}};
}

sub timetrack_total {
	if ( !exists $_[0]{timetrack_total} ) {
		$_[0]{timetrack_total} = misc::sum( map { $_->Timetrack()->wage() } $_[0]->Timetracks() );
	}
	return $_[0]{timetrack_total};
}

sub destroy {
	if ( ! $_[0]{id} ) {
		$openprint::log->error("Paycheque::destroy with no id!");
		return;
	} # end if
	my $error;
	my $ac = sql::start_transaction( $openprint::dbh );
	foreach ( openprint::Paycheque_Timetrack->find('paycheque_id'=>$_[0]{id}) ) {
		$error .= $_->destroy();
		last if $error;
	} # end foreach
	$error .= $_[0]->SUPER::destroy() if ! $error;
	$openprint::dbh->rollback() if $error;
	sql::end_transaction( $openprint::dbh, $ac );
	return $error;
} # end sub destroy

1;
__END__
