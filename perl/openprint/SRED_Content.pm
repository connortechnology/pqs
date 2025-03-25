use strict;
package openprint::SRED_Content;
our @ISA = qw(openprint::Object);
require openprint::Object;
require openprint::Object_Asset;
require openprint::SRED_Project;
require openprint::SRED_Content_Type;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'sred_contents';
$serial = 'sred_contents_id_seq';

%fields = (
	'id'			=>	'id',
	'created_by'	=>	'created_by',
	'created_on'	=>	'created_on',
	'updated_on'	=>	'updated_on',
	'starting'			=>	'starting',
	'ending'			=>	'ending',
	'project_id'		=>	'project_id',
	'description'		=>	'description',
	'unknown_time'		=>	'unknown_time',
	'all_day_event'		=>	'all_day_event',
	'user_id'			=>	'user_id',
	'deleted'			=>	'deleted',
	'duration'			=>	'duration',
	'cost'				=>	'cost',
	'cost_units'		=>	'cost_units',
	'total'				=>	'total',
	'quantity'			=>	'quantity',
	'quantity_units'	=>	'quantity_units',
	'weight'			=>	'weight',
	'mweight'			=>	'mweight',
	'weight_units'		=>	'weight_units',
	'type_id'			=>	'type_id',
	'docket'			=>	'docket',
	'notes'				=>	'notes',
);

%transforms = (
	'created_on'	=>	'NOW()',
	'updated_on'	=>	'NOW()',
	'name'			=>	[ 's/^\s+//', 's/\s+$//' ],
	'cost'			=>	[ 's/[^\-\.\d]//g' ],
	'total'			=>	[ 's/[^\-\.\d]//g' ],
	'quantity'		=>	[ 's/[^\-\.\d]//g' ],
	'weight'		=>	[ 's/[^\-\.\d]//g' ],
	'mweight'		=>	[ 's/[^\-\.\d]//g' ],
	'docket'		=>	[ 's/\D//g' ],
);

%defaults = (
	'created_on'		=>	'NOW()',
	'updated_on'		=>	'NOW()',
	'deleted'			=>	0,
	'project_id'		=>	undef,
	'user_id'			=>	undef,
	'unknown_time'		=>	1,
	'all_day_event'		=>	0,
	'duration'			=>	undef,
	'cost'				=>	undef,
	'total'				=>	undef,
	'quantity'			=>	undef,
	'weight'			=>	undef,
	'mweight'			=>	undef,
	'quantity_units'	=>	undef,
	'docket'			=>	undef,
);

sub view_url {
	my $path = '/employee/sred/project.html';
	if ( ref $_[0] eq 'openprint::SRED_Content' ) {
		return $path.'?project_id='.$_->Object()->Project()->id();
	} elsif ( $_[0] eq 'openprint::SRED_Content' ) {
		return $path.'?project_id='.(new openprint::SRED_Content( $_[1] ))->Project()->id();
	} # end if
}

sub duration {
	if ( @_ > 1 ) {
		$_[0]{duration} = $_[1];
		delete $_[0]{Duration};
	} # end if
	if ( ( ! $_[0]{duration} ) and ( $_[0]{unknown_time} ) ) {
		if ( $_[0]{all_day_event} ) {
			return Date::Parse::str2time( $_[0]{ending} ) - Date::Parse::str2time( $_[0]{starting} );
		} else {
			my ($start) = $_[0]{starting} =~ /(\d\d\d\d-\d\d-\d\d)/;
			my ($end) = $_[0]{ending} =~ /(\d\d\d\d-\d\d-\d\d)/;
			return Date::Parse::str2time( $end ) - Date::Parse::str2time( $start );
		} # end if
	} # end if
	return $_[0]{duration};
} # end sub duration

sub duration_days {
	my $parser = 'DateTime::Format::Pg';
	my $duration = $parser->parse_interval( $_[0]{duration} );
	return $duration->days();
} # end sub duration_days

sub duration_hours {
	my $parser = 'DateTime::Format::Pg';
	my $duration = $parser->parse_interval( $_[0]{duration} );
	return $duration->hours();
} # end sub duration_hours
sub duration_minutes {
	my $parser = 'DateTime::Format::Pg';
	my $duration = $parser->parse_interval( $_[0]{duration} );
	return $duration->minutes();
} # end sub duration_minutes

sub Duration {
	if ( @_ > 1 ) {
		$_[0]{Duration} = $_[1];
	} # end if
	if ( ! $_[0]{Duration} ) {
		$_[0]{Duration} = DateTime::Format::Pg->parse_interval( $_[0]{duration} );
	} # end if
	return $_[0]{Duration};
} # end sub Duration

sub Assets {
	my $self = shift;
	my %params = @_;
	$params{object_id} = $$self{id};
	$params{object_type} = 'openprint::SRED_Content';
	if ( @_ ) {
		return openprint::Object_Asset->find(%params);
	} # end if
	if ( ! exists $_[0]{Assets} ) {
		$_[0]{Assets} = [ openprint::Object_Asset->find(%params) ];
	} # end if
	return @{$_[0]{Assets}};
} # end sub Assets

sub Type {
	return new openprint::SRED_Content_Type( $_[0]{type_id} );
} # end sub Type

sub Project {
	return new openprint::SRED_Project( $_[0]{project_id} );
} # end sub Project

sub Starting {
	if ( @_ > 1 ) {
		$_[0]{Starting} = $_[1];
	} # end if
	if ( ! $_[0]{Starting} ) {
		$_[0]{Starting} = DateTime::Format::Pg->parse_datetime( $_[0]{starting} );
	} # end if
	return $_[0]{Starting};
} # end sub Starting

sub created_by {
	if ( @_ > 1 ) {
		$_[0]{created_by} = $_[1];
	}
	if ( ! $_[0]{created_by} ) {
		$_[0]{created_by} = $openprint::session{user_id};
	} # end if
	return $_[0]{created_by};
} # end sub created_by

1;
__END__
