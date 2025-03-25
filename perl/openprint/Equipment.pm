use strict;
use warnings;
package openprint::Equipment;
our @ISA = qw( openprint::Object );
require openprint::Object;
use openprint ();
require openprint::EquipmentSpecification;
require openprint::ServiceType;
#require openprint::Fold;
#require openprint::Location;
#require openprint::Equipment_Stock_Setting;
#require openprint::Equipment_Operator;
#require openprint::Equipment_Shift;
require openprint::misc;
require sql;

#use Memoize;
#memoize('fits');
#memoize('Specification');

use vars qw( $debug $log $dbh $table $serial %fields %find_fields %transforms %defaults $cache_field $default_sort );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
$default_sort = 'lower(strid)';
$table = 'tbl_Equipment';
$serial = 'Equipment_Index_seq';
$cache_field = 'strid';
sub cache_field {
    return $cache_field;
}
my %Specification_cache;

$debug = 1;
use constant DEBUG_FOLDING => 0;

%fields = (
	id					=>	'lngindex',
	strid				=>	'strid',
	name				=>	'strname',
	description			=>	'strdescription',
	category_id			=>	'category_id',
	supplier			=>	'strsupplier',
	useinestimating		=>	'useinestimating',
	useinscheduling		=>	'useinscheduling',
	image				=>	'image',
	jmf_enabled			=>	'jmf_enabled',
	instantgate_enabled	=>	'instantgate_enabled',
	cost_center			=>	'cost_center',
	jdf_id				=> 	'jdf_id',
	jdf_name			=> 	'jdf_name',
	location_id			=>	'location_id',
	cip3_in				=>	'cip3_in',
	cip3_out			=>	'cip3_out',
	cip3_hold			=>	'cip3_hold',
	cip3_merge			=>	'cip3_merge',
	cip3_monitor		=>	'cip3_monitor',
	smartscheduling		=>	'smartscheduling',
	servicetype_id		=>	'servicetype_id',
	sorting				=>	'sorting',
	message				=>	'message',
	deleted				=>	'deleted',
);
%find_fields = (
	Specifications => '(SELECT strValue FROM tbl_Equipment_Specifications WHERE lngEquipmentIndex=tbl_Equipment.'.$fields{id}.' AND strName=? LIMIT 1)',
	category		=>	'(SELECT name FROM Equipment_Categories WHERE id=ANY(category_id))',
	servicetype		=>	'(SELECT strid FROM '.$openprint::ServiceType::table.' WHERE lngindex = ANY(servicetype_id))',
);
%transforms = (
	id			=>	[ 's/\D//g', '<2147483647' ],
	strid		=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	description	=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
	deleted			=>	0,
	location_id		=>	undef,
	servicetype_id	=>	undef,
	sorting			=>	undef,
	category_id		=>	undef,
	useinestimating	=>	undef,
	useinscheduling	=>	undef,
  smartscheduling => 0,
);

sub fits {
	my ( $self, $width, $height, $calliper, $service ) = @_;

	$service = ' '.$service if $service;
	if ( $width and $height ) {
		my $max_width = $self->specification("Maximum$service Sheet Width");
		my $max_length = $self->specification("Maximum$service Sheet Length");
		my $max_height = $self->specification("Maximum$service Sheet Height");

		if ( $max_width and $max_length ) {
			my $imp = openprint::imposition::fit( $width, $height, $max_width, $max_length );
	#$log->debug("Impo: $$imp{imposition} $$imp{rows}x$$imp{columns} on $$self{strid}");
			if ( ! $$imp{imposition} ) {
				return sprintf('Too big %s x %s on %s x %s', $width, $height, $max_width, $max_length );
			} # end if
		} elsif ( $max_width ) {
			if ( ( $width > $max_width ) and ( $height > $max_width ) ) {
				return sprintf('Too big %s x %s on %s', $width, $height, $max_width );
			} # end if
		} elsif ( $max_height ) {
			if ( ( $width > $max_height ) and ( $height > $max_height ) ) {
				return sprintf('Too big %s x %s on %s', $width, $height, $max_height );
			} # end if
		} # end if

		my $min_width = $self->specification("Minimum$service Sheet Width");
		my $min_length = $self->specification("Minimum$service Sheet Length");

		if ( $min_width and $min_length ) {
			my $imp = openprint::imposition::fit( $min_width, $min_length, $width, $height );
			if ( ! $$imp{imposition} ) {
				return sprintf('Too small %s x %s on %s x %s', $width, $height, $min_width, $min_length);
			} # end if
		} elsif ( $min_width ) {
			if (
					( $width < $min_width ) and
					( $height < $min_width ) 
				) {
				return sprintf('Too big %s x %s on %s', $width, $height, $min_width);
			} # end if
		} elsif ( $min_length ) {
			if (
					( $width < $min_length ) and
					( $height < $min_length ) 
				) {
				return sprintf('Too big %s x %s on %s', $width, $height, $min_length);
			} # end if
		} # end if
	} # end if

	if ( $calliper ) {
    my $min_calliper = $self->specification("Minimum$service Calliper");

		if ($min_calliper and ($calliper < $min_calliper)) {
			return "Project is too thin. Project Calliper: $calliper Inches, Equipment Min Calliper: $min_calliper Inches.";
		} # end if
    my $max_calliper = $self->specification("Maximum$service Calliper");
		if ($max_calliper and ($calliper > $max_calliper)) {
			return "Project is too thick. Project Calliper: $calliper Inches, Equipment Max Calliper: $max_calliper Inches.";
		} # end if
    #$openprint::log->debug("Calliper is ok $min_calliper < $calliper < $max_calliper");
	} # end if
	return '';

} # end sub fits

sub Folds {
	if ( ! $_[0]{Folds} ) {
		%{$_[0]{Folds}} = ();
		foreach my $F ( openprint::Fold->find( equipment_id=>$_[0]{id} ) ) {
			push @{$_[0]{Folds}{$$F{type}}}, $F;
		} # end foreach;
	} # end if
	return %{$_[0]{Folds}};
} # end sub Folds

sub Fold {
	my ( $self, $params ) = @_;

	$self->Folds() if ! $$self{Folds};
	if ( DEBUG_FOLDING ) {
		$openprint::log->debug("Param" . ref $params );
		foreach my $k ( sort { $a cmp $b } keys %$params ) {
			$openprint::log->debug("Param: $k => $$params{$k}");
		}
		foreach my $F ( @{$$self{Folds}{$$params{type}}} ) {
			$openprint::log->debug("Fold for $$params{type} " . $F->to_string() );
		}
	}

	if ( ( ! $$params{type} ) and $$params{pages} ) {
		$$params{type} = $$params{pages}.'PageFold';
    $openprint::log->debug("Form type auto set to $$params{type}");
	}

  if (!($$self{Folds}{$$params{type}} and @{$$self{Folds}{$$params{type}}})) {
    $openprint::log->debug("No folds for type $$params{type} on $$self{strid}");
  }
	foreach my $Fold ( $$params{type} ? @{$$self{Folds}{$$params{type}}} : map { @{$$self{Folds}{$_}} } keys %{$$self{Folds}} ) {

		if ( $$params{type} and ( $$Fold{type} ne $$params{type} ) ) {
			$openprint::log->debug("Wrong type at fold: " . $Fold->name() ) if DEBUG_FOLDING;
			next;
		} else {
			$openprint::log->debug("Found fold: " . $Fold->name() . ' ... examining') if DEBUG_FOLDING;
		} # end if

		if ( $$params{gsm} and ( ( $Fold->min_gsm() and ($$params{gsm} < $Fold->min_gsm()) ) or ( $Fold->max_gsm() and ($$params{gsm} > $Fold->max_gsm()) ) ) ) {
			$openprint::log->debug("Wanted gsm: $$params{gsm}, have ($$Fold{min_gsm}) ($$Fold{max_gsm})") if DEBUG_FOLDING;
			next;
		} # end if

		if ( $$params{stitching} ) {
			if ( ( defined $$Fold{stitching} ) and ! $$Fold{stitching} ) {
				$openprint::log->debug("Wanted stitching: $$params{stitching}, have $$Fold{stitching}") if DEBUG_FOLDING;
				next;
			} # end if
		} elsif ( $$Fold{stitching} ) {
			$openprint::log->debug("Wanted stitching: $$params{stitching}, have $$Fold{stitching}") if DEBUG_FOLDING;
			next;
		} # end if

		if ( $$params{perfectbind} ) {
			if ( defined $$Fold{perfectbind} and ! $$Fold{perfectbind} ) {
				$openprint::log->debug("Wanted perfectbind: $$params{perfectbind}, have $$Fold{perfectbind}") if DEBUG_FOLDING;
				next;
			} #end if
		} elsif ( $$Fold{perfectbind} ) {
			$openprint::log->debug("Wanted perfectbind: $$params{perfectbind}, have $$Fold{perfectbind}") if DEBUG_FOLDING;
			next;
		} # end if

		if ( $$params{spinepaste} ) {
			if ( ( defined $$Fold{spinepaste} ) and ! $$Fold{spinepaste} ) {
				$openprint::log->debug("Wanted spinepaste: $$params{spinepaste}, have $$Fold{spinepaste}") if DEBUG_FOLDING;
				next;
			} # end if
		} elsif ( $$Fold{spinepaste} ) {
			$openprint::log->debug("Wanted spinepaste: $$params{spinepaste}, have $$Fold{spinepaste}") if DEBUG_FOLDING;
			next;
		} # end if

		if ( $$Fold{folds} and $$params{folds} and ($$Fold{folds} != $$params{folds} ) ) {
			$openprint::log->debug("Wanted folds: $$params{folds}, have $$Fold{folds}") if DEBUG_FOLDING;
			next;
		} # end if
		if ( $$Fold{angles} and $$params{angles} and ($$Fold{angles} != $$params{angles} ) ) {
			$openprint::log->debug("Wanted angles: $$params{angles}, have $$Fold{angles}") if DEBUG_FOLDING;
			next;
		} # end if
		if ( $$Fold{page_columns} and $$params{page_columns} and ($$Fold{page_columns} != $$params{page_columns} ) ) {
			$openprint::log->debug("Wanted Page_columns: $$params{page_columns}, have $$Fold{page_columns}") if DEBUG_FOLDING;
			next;
		} # end if
		if ( $$Fold{page_rows} and $$params{page_rows} and ($$Fold{page_rows} != $$params{page_rows} ) ) {
			$openprint::log->debug("Wanted Page_rows: $$params{page_rows}, have $$Fold{page_rows}") if DEBUG_FOLDING;
			next;
		} # end if

		if ( $$params{page_width} and (
				( $$Fold{min_width} and ( $$Fold{min_width} > $$params{page_width} ) ) or
				( $$Fold{max_width} and ( $$Fold{max_width} < $$params{page_width} ) )
				)) {
			$openprint::log->debug("Wanted Page_width: $$params{page_width}, have min:$$Fold{min_width} max:$$Fold{max_width}") if DEBUG_FOLDING;
			next;
		} # end if
		if ( $$params{page_height} and (
				( $$Fold{min_height} and $$Fold{min_height} > $$params{page_height} ) or
				( $$Fold{max_height} and $$Fold{max_height} < $$params{page_height} )
				) ) {
			$openprint::log->debug("Wanted Page_height: $$params{page_height}, have min:$$Fold{min_height} max:$$Fold{max_height}") if DEBUG_FOLDING;
			next;
		} # end if
		if ( $$params{calliper} and (
				( $$Fold{min_calliper} and $$Fold{min_calliper} > $$params{calliper} ) or
				( $$Fold{max_calliper} and $$Fold{max_calliper} < $$params{calliper} )
				) ) {
			$openprint::log->debug("Wanted Calliper: $$params{calliper}, have min:$$Fold{min_calliper} max:$$Fold{max_calliper}") if DEBUG_FOLDING;
			next;
		} # end if
		if ( $$params{imposition} ) {
			if ( defined $$Fold{min_imposition} and ($$Fold{min_imposition} > $$params{imposition}) ) {
				$openprint::log->debug("Wanted imposition: $$params{imposition}, have min $$Fold{min_imposition} x max $$Fold{max_imposition}") if DEBUG_FOLDING;
				next;
			} # end if
			if ( defined $$Fold{max_imposition} and ($$Fold{max_imposition} < $$params{imposition}) ) {
				$openprint::log->debug("Wanted imposition: $$params{imposition}, have min $$Fold{min_imposition} x max $$Fold{max_imposition}") if DEBUG_FOLDING;
				next;
			} # end if
		} # end if
		if ( defined $$Fold{min_imposition_columns} and $$params{columns} and ($$Fold{min_imposition_columns} > $$params{columns}) ) {
			$openprint::log->debug("Wanted imposition columns: $$params{columns}, have $$Fold{min_imposition_columns} x $$Fold{max_imposition_columns}") if DEBUG_FOLDING;
			next;
		} # end if
		if ( defined $$Fold{max_imposition_columns} and $$params{columns} and ($$Fold{max_imposition_columns} < $$params{columns}) ) {
			$openprint::log->debug("Wanted imposition: $$params{columns}, have $$Fold{min_imposition_columns} x $$Fold{max_imposition_columns}") if DEBUG_FOLDING;
			next;
		} # end if
		if ( defined $$Fold{min_imposition_rows} and $$params{rows} and ($$Fold{min_imposition_rows} > $$params{rows}) ) {
			$openprint::log->debug("Wanted imposition columns: $$params{rows}, have $$Fold{min_imposition_rows} x $$Fold{max_imposition_rows}") if DEBUG_FOLDING;
			next;
		} # end if
		if ( defined $$Fold{max_imposition_rows} and $$params{rows} and ($$Fold{max_imposition_rows} < $$params{rows}) ) {
			$openprint::log->debug("Wanted imposition: $$params{rows}, have $$Fold{min_imposition_rows} x $$Fold{max_imposition_rows}") if DEBUG_FOLDING;
			next;
		} # end if

		if ( $$Fold{spine_direction} and $$params{spine_direction} ) {
#$openprint::log->debug("spine direction:: $$Fold{spine_direction} $$params{spine_direction} $$params{grain_direction} width_folds: $$Fold{width_folds} $$Fold{height_folds}");
			if ( $$Fold{spine_direction} eq 'With Grain' ) {
				if ( $$Fold{folds} ) {
					if ( ($$params{spine_direction} eq 'Vertical') and ($$params{grain_direction} eq 'width') ) {
						$openprint::log->debug("Wanted spinedirection: $$params{spine_direction}, have $$Fold{spine_direction} grain: $$params{grain_direction}") if DEBUG_FOLDING;
						next;
					} elsif ( ($$params{spine_direction} eq 'Horizontal') and ($$params{grain_direction} eq 'height') ) {
						$openprint::log->debug("Wanted spinedirection: $$params{spine_direction}, have $$Fold{spine_direction} grain: $$params{grain_direction}") if DEBUG_FOLDING;
						next;
					} 
				} elsif ( $$Fold{anglea} ) {
					if ( ($$params{spine_direction} eq 'Vertical') and ($$params{grain_direction} eq 'height') ) {
						$openprint::log->debug("Wanted spinedirection: $$params{spine_direction}, have $$Fold{spine_direction} grain: $$params{grain_direction}") if DEBUG_FOLDING;
						next;
					} elsif ( ($$params{spine_direction} eq 'Horizontal') and ($$params{grain_direction} eq 'width') ) {
						$openprint::log->debug("Wanted spinedirection: $$params{spine_direction}, have $$Fold{spine_direction} grain: $$params{grain_direction}") if DEBUG_FOLDING;
						next;
					} 
				} # end fold direction
			} elsif ( $$Fold{spine_direction} ne $$params{spine_direction} ) {
				$openprint::log->debug("Wanted spinedirection: Impo $$params{spine_direction}, have Fold $$Fold{spine_direction}") if DEBUG_FOLDING;
				next;
			} # end if with_grain or vertical or horizontal
		} # end if spine_direction

		if ( $$Fold{orientation} ) {
			my %orientations = map { $_, $_ } split(',', $$Fold{orientation});
			if ( $$params{page_width} < $$params{page_height} ) { 
				if ( ! $orientations{Portrait} ) {
					$openprint::log->debug("Wanted orientation portrait $$params{page_width} <=> $$params{page_height} $$Fold{orientation} $orientations{portrait}") if DEBUG_FOLDING;
					next ;
				}
			} elsif ( $$params{page_width} > $$params{page_height} ) { 
				if ( ! $orientations{Landscape} ) {
					$openprint::log->debug("Wanted orientation landscape $$params{page_width} <=> $$params{page_height}") if DEBUG_FOLDING;
					next;
				}
			} else {
				if ( ! $orientations{Square} ) {
					$openprint::log->debug("Wanted orientation square") if DEBUG_FOLDING;
					next;
				}
			}
		}

		if ( $$params{printing_type} and $$Fold{printing_type} and ! sets::isin( $$params{printing_type}, [ split(',', $$Fold{printing_type}) ] ) ) {
			$openprint::log->debug("Fold no good due to PrintingType ($$params{printing_type}) != " . $$Fold{printing_type} ) if DEBUG_FOLDING;
			next;
		} # end if
		if ( exists $$params{gsm} ) {
			$openprint::log->debug("Wanted gsm: $$params{gsm}") if DEBUG_FOLDING;
			my $RunSpeed = $Fold->RunSpeed( $$params{gsm} );
			if ( ! $RunSpeed ) {
				$openprint::log->debug("Didn't find runspeed for $$params{gsm}gsm(" . openprint::Paper::gsm_to_weight($$params{gsm})."lbs) on fold " . $Fold->name() . ' on ' . $self->name() ) if DEBUG_FOLDING;
				next;
			#} else {
#$openprint::log->debug("Got runspeed $$RunSpeed{runspeed}") if $debug;
			} # end if
		} # end if
$openprint::log->debug('Got fold' . $Fold->to_string()) if DEBUG_FOLDING;
		return $Fold;
#$openprint::log->debug("NEVER Got fold" . $Fold->description()) if $debug;
	} # end foreach Fold
	return;
} # end sub Fold

sub Specifications {
	my $self = shift;
	return openprint::EquipmentSpecification->find( equipment_id=>$$self{id}, order=>'sorting NULLS FIRST,strname, dblmin NULLS FIRST', @_ );
} # end sub Specifications

sub specification {
	my $Specification = Specification( @_ );
	if ( ! $Specification ) {
		return;
	} # end if
	return $$Specification{value};
} # end sub specification

sub Specification {
	my ( $self, $name, $range, $s_debug ) = @_;

	my $key = join(',', $$self{id}, $name, (defined($range)?$range:''));
	if ( exists $Specification_cache{$key} ) {
		return $Specification_cache{$key};
	} # end if

	if ( ! $$self{Specifications} ) {
		return if ! $$self{id};
		foreach ( openprint::EquipmentSpecification->find( equipment_id=>$$self{id}, order=>'dblmin NULLS FIRST,dblmax NULLS FIRST' ) ) {
			push @{$$self{Specifications}{$$_{name}}}, $_;
		} # end foreach
		if ( !$$self{Specifications} ) {
			$$self{Specifications} = {};
			$openprint::log->debug('Equipment::Specification No specifications for '.$self->to_string()) if $s_debug;
			return;
		} # end if
	} # end if

	if ( ! exists $$self{Specifications}{$name} ) {
		$openprint::log->warn("No specifications for ($name) " . $self->name() ) if $s_debug;
		return;
	} # end if
	my $Spec = openprint::misc::find_entry( $range, $$self{Specifications}{$name}, $s_debug );
	$Specification_cache{$key} = $Spec;
	return $Spec;
} # end sub specification

sub copy {
	my $self = shift;

	my $new = new openprint::Equipment();
	@$new{keys %fields} = @$self{keys %fields};
	delete $$new{id};
	$$new{deleted} = 0;
	$$new{name} = 'Copy of ' . $$new{name};
	$_ = $new->save();
	return if $_;

	my $ac = sql::start_transaction( $openprint::dbh );

	foreach my $ES ( openprint::EquipmentSpecification->find( equipment_id=>$$self{id} ) ) {
		$ES->copy()->save({ equipment_id=>$$new{id} });
	} # end foreach
	foreach my $Fold ( openprint::Fold->find( equipment_id=>$$self{id} ) ) {
		$Fold->copy()->save({ equipment_id=>$$new{id} });
	}

# Now do pricing, start with Service Prices
	my @prices = sql::execute( undef, undef, q{SELECT pricelist_id, service_id, min, max, units, cost, markup, price FROM Service_Prices WHERE equipment_id=?}, $$self{id} );
	while ( my ( $list_id, $service_id, $min, $max, $units, $cost, $markup, $price ) = splice @prices, 0, 8 ) {
		sql::insert( undef, undef, 'Service_Prices',[
				'pricelist_id',	 $list_id,
				'service_id',	$service_id,
				'min',			$min,
				'max',			$max,
				'units',		 $units,
				'cost',			$cost,
				'markup',		$markup,
				'Price',		 $price,
				'equipment_id', $$new{id},
				]);
	} # end while
	@prices = sql::execute( undef, undef, q{SELECT lnglistindex, lngmaterialindex, lngmin, lngmax, strunits, dblcost, dblmarkup, dblprice FROM tbl_Material_Prices WHERE lngEquipmentIndex=?}, $$self{id} );
	while ( my ( $list_id, $service_id, $min, $max, $units, $cost, $markup, $price ) = splice @prices, 0, 8 ) {
		sql::insert( undef, undef, 'tbl_Material_Prices',[
				'lnglistindex',	 $list_id,
				'lngmaterialindex', $service_id,
				'lngmin',			$min,
				'lngmax',			$max,
				'strunits',		 $units,
				'dblcost',			$cost,
				'dblmarkup',		$markup,
				'dblPrice',		 $price,
				'lngEquipmentindex', $$new{id},
				] );
	} # end while
	# Equipment_shifts
	foreach my $ES ( openprint::Equipment_Shift->find(equipment_id=>$$self{id}) ) {
		$ES->copy()->save({equipment_id=>$$new{id}});
	} # end foreach $ES
	sql::end_transaction( $openprint::dbh, $ac );

	return $new;
} # end sub copy

sub destroy {
	my $self = shift;

	delete $openprint::Object::cache{'openprint::Equipment'}{$$self{id}} if $openprint::Object::cache{'openprint::Equipment'};
	my $error;

	my $ac = sql::start_transaction( $openprint::dbh );
	sql::execute( undef, undef, q{DELETE FROM tbl_Equipment_Specifications WHERE lngEquipmentIndex=?}, $$self{id} );
	sql::execute( undef, undef, q{DELETE FROM Service_Prices WHERE equipment_id=?}, $$self{id} );
	sql::execute( undef, undef, q{DELETE FROM tbl_Material_Prices WHERE lngEquipmentIndex=?}, $$self{id} );
	sql::execute( undef, undef, q{DELETE FROM Schedule WHERE equipment_id=?}, $$self{id} );
	foreach my $ES ( openprint::Equipment_Shift->find(equipment_id=>$$self{id}) ) {
		$error .= $ES->delete();
		last if $error;
	} # end foreach ES
	if ( ! $error ) {
		foreach my $S ( openprint::Shift->find(equipment_id=>$$self{id}) ) {
			$error .= $S->delete();
			last if $error;
		} # end foreach ES
	} # end if error
    sql::execute( undef, undef, q{DELETE FROM tbl_Equipment WHERE lngIndex=?}, $$self{id} );
    sql::end_transaction( $openprint::dbh, $ac );

	openprint::logs::insertLogRecord('6', "Equipment Index: $$self{id} - " . $$self{name}, );
	return $error;
} # end sub destroy

sub update_schedule {
	my $self = shift;

	if ( $openprint::config{Smart_Schedule} ne 'Y' ) {
		$openprint::log->debug("Not using Smart Schedule.  Not Updating Press Schedule");
		return;
	} # end if

    my $starttime_seconds = Date::Parse::str2time( sql::execute( undef, undef, q{SELECT NOW()} ) );
	my $runtime;
	foreach my $Job ( openprint::ScheduledJob( equipment_id=>$$self{id}, order=>'starttime', 'starttime is null'=>0 ) ) {
		$Job->save({starttime_seconds	=> $starttime_seconds });
		$runtime = $Job->runtime_seconds();
	} # end foreach Job

} # end sub update_schedule

sub next {
	my ($self, $params) = shift;
	my $sql = q{SELECT min(strid) FROM tbl_Equipment WHERE strid > ?};
	my @values = ($$self{name});
	if ( $params and $$params{category_id} ) {
		$sql .= ' AND category=?';
		push @values, $$params{category_id};
	} # end if
	my ($name) = sql::execute( undef, undef, $sql, @values );
	( $_ ) = sql::execute( undef, undef, 'SELECT '.$fields{id}.' FROM tbl_Equipment WHERE '.$fields{name}.'=?', $name );
	return $_;
} # end sub next

sub Next {
	my ($self, $params) = shift;
	return new openprint::Equipment( $self->next($params) );
} # end sub Next

sub prev {
	my ( $self, $params ) = shift;
	my $sql = q{SELECT max(strid) FROM tbl_Equipment WHERE strid < ?};
	my @values = ($$self{name});
	if ( $params and $$params{category_id} ) {
		$sql .= ' AND category=?';
		push @values, $$params{category_id};
	} # end if
	my ($name) = sql::execute( undef, undef, $sql, @values );
	( $_ ) = sql::execute( undef, undef, 'SELECT '.$fields{id}.' FROM tbl_Equipment WHERE '.$fields{name}.'=?', $name );
	return $_;
} # end sub next

sub Previous {
	my ($self, $params) = shift;
	return new openprint::Equipment( $self->prev($params) );
} # end sub Next

sub Location {
	return new openprint::Location( $_[0]{location_id} );
} # end sub Location

sub Shifts {
} # end sub

sub Stock_Setting {
	if ( ! $_[0]{Stock_Settings} ) {
		%{$_[0]{Stock_Settings}} = map { $_->stock_id(), $_ } openprint::Equipment_Stock_Setting->find(equipment_id=>$_[0]{id});
	} # end if
	return $_[0]{Stock_Settings}{$_[1]{id}} if exists $_[0]{Stock_Settings}{$_[1]{id}};
	return;
} # end sub Stock_Setting
sub Stock_Settings {
	if ( ! $_[0]{Stock_Settings} ) {
		%{$_[0]{Stock_Settings}} = map { $_->stock_id(), $_ } openprint::Equipment_Stock_Setting->find(equipment_id=>$_[0]{id});
	} # end if
	return values %{$_[0]{Stock_Settings}};
} # end sub Stock_Settings

sub servicetype_id {
	my $self = shift;
	return [] if ! $$self{servicetype_id};
	return $$self{servicetype_id};
} # end sub servicetype_id

sub ServiceTypes {
	return () if ! $_[0]{servicetype_id};
	return map { new openprint::ServiceType( $_ ); } @{$_[0]{servicetype_id}};
} # end sub ServiceTypes

sub Equipment_Shifts {

	my @Equipment_Shifts = openprint::Equipment_Shift->find(equipment_id=>$_[0]{id},order=>'starttime_seconds');
	if ( ! @Equipment_Shifts ) {
		return ();
	} # end if
	# Setup Next and Previous links, turns it into a doubly linked list
	my $Last_ES;
	for ( my $ES_index = 0; $ES_index < @Equipment_Shifts; $ES_index += 1 ) {
		if ( $Last_ES ) {
			$Equipment_Shifts[$ES_index]->Previous( $Last_ES );
			$Last_ES->Next( $Equipment_Shifts[$ES_index] );
		} # end if
		$Last_ES = $Equipment_Shifts[$ES_index];
	} # end foreach Equipment Shift
	$Last_ES->Next( $Equipment_Shifts[0] );
	return @Equipment_Shifts;
} # end sub Equipment_Shifts

sub categories {
	return map { new openprint::Equipment_Category($_)->name() } ( $_[0]->category_id() ? @{$_[0]->category_id()} : () );
} # end sub categories

sub Operators {
	if ( ! $_[0]{Operators} ) {
		my @user_ids = map { $$_{user_id} } openprint::Equipment_Operator->find( equipment_id=>$_[0]{id} );
		@{$_[0]{Operators}} = @user_ids ? openprint::User->find( id=>\@user_ids, order=>'lower(firstname),lower(lastname)' ) : ();
	} # end if
	return @{$_[0]{Operators}};
} # end sub Operators

sub link_to {
  my $self = shift;
  my $text = @_ ? shift : $$self{strid};
  my $options = @_ ? shift : {};
	return '<a href="/administrator/equipment/edit.html?ddmEquipment='.$$self{id}.'"'.join(' ', map { $_.'="'.$$options{$_}.'"'} keys %$options).'>'.$text.'</a>';
}
sub button_to {
  my $self = shift;
  return ssi::button('EquipmentButton'.$$self{id}, {href=>'/administrator/equipment/edit.html?ddmEquipment='.$_[0]{id}.'">'.(@_ ? shift : $$self{strid})});
}

1;
__END__
