use strict;
use openprint ();
require openprint::Shift;
require openprint::User;
require openprint::Performance_Record;

package openprint::Performance_Report;
our @ISA = qw( openprint::Object );

# A performanceReport appliedsto a shift + operator
# It is a collection of PerformanceRecords

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'performance_reports';
$serial = 'performance_reports_id_seq';
%fields = (
	'id'			=>	'id',
	'shift_id'		=>	'shift_id',
	'operator_id'	=>	'operator_id',
	'created_on'	=>	'created_on',
	'updated_on'	=>	'updated_on',
	'deleted'		=>	'deleted',
);

%transforms = (
);
%defaults = (
	'deleted'	=>	0,
);

sub Shift {
	return new openprint::Shift( $_[0]{'shift_id'} );
} # end sub Shift;
sub Operator {
	return new openprint::User( $_[0]{'operator_id'} );
}
sub Records {
	my $self = shift;
	if ( @_ ) {
		my %param = @_;
		$param{'report_id'} = $$self{'id'};
		return openprint::Performance_Record->find(%param);
	}
	if ( ( ! $$self{'Records'} ) and $$self{'id'} ) {
		@{$$self{'Records'}} = openprint::Performance_Record->find('report_id'=>$$self{'id'});
	} # end if
	return @{$$self{'Records'}} if $$self{'Records'};
	return ();
} # end sub Records

sub total {
	if ( ! exists $_[0]{'total'} ) {
#$openprint::log->debug("getting total $_[0]{id}");
		foreach my $Record ( $_[0]->Records() ) {
			$_[0]{'total'} += $Record->total();
		} # end foreach
	} # end if
	return $_[0]{'total'};
} # end sub total

1;
__END__
