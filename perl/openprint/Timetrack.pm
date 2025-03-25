use strict;
package openprint::Timetrack;
our @ISA = qw(openprint::Object);

use openprint ();

require openprint::Currency;
require openprint::Company;
require openprint::Service;
require openprint::Paycheque_Timetrack;

use vars qw( $debug $table $serial %fields %find_fields %defaults %transforms );
$debug = 0;

$table = 'timetracks';
$serial = 'timetracks_id_seq';
%fields = (
	id				=> 'id',
	starting		=>	'starting',
	ending			=>	'ending',
	starting_dt		=>	undef,
	ending_dt		=>	undef,
	duration		=>	'duration',
	duration_override	=>	'duration_override',
	company_id    		=>	'company_id',
	project_id    		=>	'project_id',
	description   		=>	'description',
	invoice_id    		=>	'invoice_id',
	service_id    		=>	'service_id',
	owner_id      		=>	'owner_id',
	date_associated 	=>	'date_associated',
	time_associated 	=>	'time_associated',
	user_id	  	    	=>	'user_id',
	rate		        	=>	'rate',
  units             =>  'units',
	created_on    		=> 'created_on',
	updated_on    		=> 'updated_on',
	deleted	      		=> 'deleted',
	currency_id   		=>	'currency_id',
	travel_associated	=>	'travel_associated',
	distance	    		=>	'distance',
	billable	    		=>	'billable',
	po			      		=>	'po',
	keywords	    		=>	undef,
);
%find_fields = (
	paycheque_id		=>	'(SELECT paycheque_id FROM Paycheques_Timetracks WHERE timetrack_id=timetracks.id)',
);

%transforms = (
	rate	  	=>	[ 's/[^\d\.]//g' ],
	distance	=>	[ 's/[^\d\.]//g' ],
  po	  		=>	[ 's/^\s+//', 's/\s+$//' ],
);
%defaults = (
	created_on	  		=>	q`'NOW()'`,
	updated_on  			=>	q`'NOW()'`,
	deleted	  	   		=>	0,
	rate			       	=>	undef,
	currency_id		  	=>	undef,
	owner_id		     	=>	q`$openprint::Owner->id()`,
  company_id        =>  undef,
	invoice_id			  =>	undef,
	service_id		  	=>	undef,
	project_id		  	=>	undef,
	user_id			    	=>	undef,
	travel_associated	=>	0,
	distance			    =>	undef,
	billable		    	=>	q`1`,
	duration_override	=>	0,
);

my $parser = 'DateTime::Format::Pg';

sub starting_dt {
	if ( @_ > 1 ) {
		$_[0]{starting_dt} = $_[1];
		$_[0]{starting} = $parser->format_datetime( $_[0]{starting_dt} ) if $_[0]{starting_dt};
	}
	if ( ! $_[0]{starting_dt} ) {
		$_[0]{starting_dt} = $parser->parse_datetime( $_[0]{starting} );
    if (!$_[0]{time_associated}) {
      $_[0]{starting_dt}->hour(0);
      $_[0]{starting_dt}->minute(0);
      $_[0]{starting_dt}->second(0);
    }
	}
	return $_[0]{starting_dt};
}
sub ending_dt {
	if ( @_ > 1 ) {
		$_[0]{ending_dt} = $_[1];
		$_[0]{ending} = $parser->format_datetime( $_[0]{ending_dt} ) if $_[0]{ending_dt};
	}
	if ( ! $_[0]{ending_dt} ) {
		$_[0]{ending_dt} = $parser->parse_datetime( $_[0]{ending} );
    if (!$_[0]{time_associated}) {
      $_[0]{ending_dt}->hour(0);
      $_[0]{ending_dt}->minute(0);
      $_[0]{ending_dt}->second(0);
    }
	}
	return $_[0]{ending_dt};
}

sub duration {
	if ( @_ > 1 ) {
		$_[0]{duration} = $_[1];
	}
	if ( ( ! $_[0]{duration} ) and ( ! $_[0]{duration_override} ) ) {
		$_[0]{duration} = misc::seconds2hms( $_[0]->elapsed() );
	} # end if
	return $_[0]{duration};
} # end sub duration

sub elapsed {
	my ( $self ) = @_;

	if ( $$self{duration_override} ) {
		return misc::hms2time( $_[0]{duration} );

	} elsif ( $$self{time_associated} ) {
		return Date::Parse::str2time($$self{ending}) - Date::Parse::str2time($$self{starting});
	} else {
		my ($start) = $$self{starting} =~ /(\d\d\d\d-\d\d-\d\d)/;
		my ($end) = $$self{ending} =~ /(\d\d\d\d-\d\d-\d\d)/;
if ( 0 ) {
    my $start_dt = $parser->parse_datetime( "$start 00:00:00");
$openprint::log->debug("starting: " . $parser->format_datetime( $start_dt ) );
    my $end_dt = $parser->parse_datetime( "$end 00:00:00" )->add( DateTime::Duration->new('days'=>1) ) ;
$openprint::log->debug('ending: ' . $parser->format_datetime( $end_dt ) );
    my $duration_dt = $end_dt->subtract_datetime( $start_dt );
$openprint::log->debug('elapsed: ' . $duration_dt->in_units('seconds') );
    return $duration_dt->in_units('seconds');
}

		return (Date::Parse::str2time("$end 23:59:59")+1) - Date::Parse::str2time("$start 00:00:00");

	} # end if
} # end sub elapsed

sub rate {
	my ( $self ) = @_;

  if ( $$self{rate} ) {
    return $$self{rate};
  }

  if ( $$self{service_id} ) {
    my $Service = $self->Service();
    my %Price = $Service->get_price( undef, undef, $self->Company()->Pricelist() );
    return $Price{Price};
	} # end if
  return;
}

sub units {
	my $self = shift;
  $$self{units} = shift if @_;
  if ( (! $$self{units}) and $$self{service_id} ) {
    my $Service = $self->Service();
    my %Price = $Service->get_price( undef, undef, $self->Company()->Pricelist() );
    $$self{units} = $Price{units};
  } 
  return $$self{units};
} # end sub units

sub Price {
	my ( $self ) = @_;
	my $elapsed = $self->elapsed();
	my $Service = $self->Service();
	my $price = $Service->get_Price( undef, undef, $self->Company()->Pricelist(), $self->starting() );
  $$price{price} = $$price{Price};

	if ( $$self{rate} ) {
    $openprint::log->debug("Overriding rate to $$self{rate}") if $debug;
		$$price{cost} = $$price{price} = $$self{rate};
	} # end if

  my $units = lc $self->units();
  $units = lc $$price{units} if ! $units;
  $$price{units} = $units;

	if ( $units eq '/year' ) {
		my $years = Math::Round::nearest(1, $elapsed/(60*60*24*365));
    #$openprint::log->debug('Years pricing ' . $years .' from elapsed '.$elapsed);
		$$price{total} = $$price{price} * $years;
	} elsif ( $units eq '/month' ) {
		$elapsed = Math::Round::nearest(1, $elapsed/(60*60*24*30));
		$$price{total} = $$price{price} * $elapsed;
		$openprint::log->debug('Month pricing ' . $elapsed .'month * '.$$price{price}.'='.$$price{total}) if $debug;
	} elsif ( $units eq '/week' ) {
		$elapsed = Math::Round::nearest(1,$elapsed/(60*60*24*7));
		#$openprint::log->debug('Month pricing ' . $elapsed );
		$$price{total} = $$price{price} * $elapsed;
	} elsif ( $units =~ /^\/hr\.?/i ) {
		$$price{total} = $$price{price} * $elapsed / 3600;
    $openprint::log->debug("Total is $$price{total} from $$price{price} * $elapsed /3600") if $debug;
	} elsif ( $units eq 'once' ) {
		$$price{total} = $$price{price};
	} else {
		$openprint::log->warn('Unknown units in Timetrack Service ('.$Service->name().') ('.$units.') assuming Hrs');
		$$price{total} = $$price{price} * $elapsed / 3600;
	} # end if
	return $price;
} # end sub Price

sub value {
	my ( $self ) = @_;
	my $Price = $self->Price();
	return $$Price{total};
} # end sub value 

sub wage {
	my ( $self ) = @_;
	my $elapsed = $self->elapsed();
	return $self->User()->wage() * $elapsed / 3600;
} # end sub  wage

sub Employee {
	return new openprint::User( $_[0]{user_id} );
} # end sub Employee

sub Paycheques {
	if ( ( ! exists $_[0]{Paycheques} ) and $_[0]{id} ) {
		$_[0]{Paycheques} = [ map { $_->Paycheque() } openprint::Paycheque_Timetrack->find( timetrack_id=>$_[0]{id}) ];
	} # end if
	return @{$_[0]{Paycheques}} if $_[0]{Paycheques};
	return ();
} # end sub Paycheques

sub paycheque_id {
	my $PT = openprint::Paycheque_Timetrack->find_one('timetrack_id'=>$_[0]{id});
	return $$PT{paycheque_id} if $PT;
	return;
} # end sub paycheque_id

sub paid {
	return $_[0]->Paycheques() ? 1 : 0;
} # end sub paid

sub invoiced {
	return $_[0]->invoice_id() ? 1 : 0;
} # end sub invoiced

sub copy {
	my $New = $_[0]->SUPER::copy();
	delete $$New{invoice_id};
	return $New;
} # end sub copy

sub elapsed_formatted {
  my $self = shift;
  if ( $$self{time_associated} ) {
    return misc::seconds_to_pretty_interval( $self->elapsed() );
  } 
  my $units = lc $self->units();

  my $elapsed = $self->elapsed();
  if ( $units eq '/year' ) {
    $elapsed = Math::Round::nearest(1, $elapsed/(60*60*24*365));
    return $elapsed . ' year' . ($elapsed == 1 ? '' : 's');
  } elsif ( $units eq '/month' ) {
    $elapsed = Math::Round::nearest(1, $elapsed/(60*60*24*30));
    return $elapsed . ' month' . ($elapsed == 1 ? '' : 's');
  } elsif ( $units eq '/week' ) {
    $elapsed = Math::Round::nearest(1, $elapsed/(60*60*24*7));
    return $elapsed . ' week' . ($elapsed == 1 ? '' : 's');
  } elsif ( $units eq '/day' ) {
    $elapsed = Math::Round::nearest(1, $elapsed/(60*60*24));
    return $elapsed . ' day' . ($elapsed == 1 ? '' : 's');
  } elsif ( $units eq 'once' ) {
    return '';
  } elsif ( $units =~ /^\/hr\.?/ ) {
    $elapsed = Math::Round::nearest(1, $elapsed/(60*60));
    return $elapsed . ' hour' . ($elapsed == 1 ? '' : 's');
  } else {
    return $elapsed . ' hour' . ($elapsed == 1 ? '' : 's');
  } # end if
}

sub link_to {
    my $self = shift;
    my $text = @_ ? shift : $$self{id};
    if ( $self->invoiced() ) {
      return '<a href="/timetrack/view.html?timetrack_id='.$$self{id}.'">'.$text.'</a>';
    } else {
      return '<a href="/timetrack/edit.html?timetrack_id='.$$self{id}.'">'.$text.'</a>';
    }
}

sub can_view {
  my $self = shift;
  my $user = @_ ? shift : $openprint::User;
  return 1 if $$user{id} == $$self{user_id};
  return 1 if $$user{type} eq 'A';
  return 1 if $user->in_Group('Accounting');
  return 0;
}

sub can_edit {
  my $self = shift;
  my $user = @_ ? shift : $openprint::User;
  return 1 if $$user{id} == $$self{user_id};
  return 1 if $$user{type} eq 'A';
  return 1 if $user->in_Group('Accounting');
  return 0;
}

sub Currency {
  my $self = shift;
  return new openprint::Currency($$self{currency_id});
}

1;
__END__
