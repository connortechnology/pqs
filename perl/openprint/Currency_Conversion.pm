use strict;
package openprint::Currency_Conversion;
our @ISA = qw(openprint::Object);
require Math::Round;

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'currency_conversions';
$serial	= 'currency_conversions_id_seq';
%fields = (
	id		    		=>	'id',
	to_id			    =>	'to_id',
	from_id			  =>	'from_id',
	period_start	=>	'period_start',
	period_end		=>	'period_end',
	rate		    	=>	'rate',
);
%transforms = (
	rate	=>	[ 's/[^\-\.\d]//g' ],
);
%defaults = (
	period_start	=>	undef,
	period_end		=>	undef,
	rate	    		=>	undef,
);

sub amount {
	return Math::Round::nearest(0.0001, $_[0]{rate});
} # end sub amount

sub To {
	return new openprint::Currency($_[0]{to_id});
} # end sub To

sub From {
	return new openprint::Currency($_[0]{from_id});
} # end sub From

1;
__END__
