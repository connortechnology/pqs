use strict;
require openprint::Performance_Report;
require openprint::Performance_Point;

# A Performance Record is the line item in a Performance Report
package openprint::Performance_Record;
our @ISA = qw( openprint::Object );
use vars qw( $debug $table %fields %find_fields %transforms %defaults @identified_by );
$debug = 0;
$table = 'performance_records';
@identified_by = ( 'report_id', 'type_id', 'docket' );

%fields = (
	'type_id'	=>	'type_id',
	'report_id' =>	'report_id',
	'docket'	=>	'docket',
	'total'		=>	'total',
	'quantity'	=>	'quantity',
);
%find_fields = (
	'shift_id'	=>	'(SELECT shift_id FROM Performance_Reports WHERE Performance_reports.id=report_id)',
);
%transforms = (
	'quantity'	=>	[ 's/[^\d\.\-]//g' ],
);
%defaults = (
	'quantity'	=>	undef,
	'total'		=>	undef,
);

#sub Shift {
	#return new openprint::Shift( $_[0]{'shift_id'} );
#} # end sub Shift;

sub Type {
	return new openprint::Performance_Point_Type( $_[0]{'type_id'} );
} # end sub Type

sub Point {
	if ( ! $_[0]{'Point'} ) {
		$_[0]{'Point'} = new openprint::Performance_Point( { 
				'type_id'		=>	$_[0]{'type_id'}, 
				'equipment_id'	=>	$_[0]->Report()->Shift()->equipment_id(),
				'docket'		=>	$_[0]{'docket'},
				} );
	} # end if
	return $_[0]{'Point'};
} # end sub Point

sub Report {
	return new openprint::Performance_Report( $_[0]{'report_id'} );
} # end sub Report

sub quantity {
$openprint::log->debug("auantity: @_");
	if ( @_ > 1 ) {
		$_[0]{'quantity'} = $_[1];
		$_[0]{'total'} = $_[0]{'quantity'} * $_[0]->Point()->value();
	} # end if
	return $_[0]{'quantity'};
} # end sub quantity

sub total {
	if ( @_ > 1 ) {
		$_[0]{'total'} = $_[1];
	} # end if
	if ( ! defined $_[0]{'total'} ) {
$openprint::log->debug("total: $_[0]{'quantity'} * " . $_[0]->Point()->value() );
		$_[0]{'total'} = $_[0]{'quantity'} * $_[0]->Point()->value();
	} # end if
	return $_[0]{'total'};
} # end sub total

1;
__END__
