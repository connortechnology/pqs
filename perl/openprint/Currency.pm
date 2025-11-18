use strict;
package openprint::Currency;
our @ISA = qw(openprint::Object);

require openprint;
require openprint::Currency_Conversion;
require openprint::Pricelist;
require openprint::Company;
require sql;

use vars qw( $log $dbh $debug $table $serial %fields %transforms %defaults $cache_field );
*log = \$openprint::log;
*dbh = \$openprint::dbh;

$debug = 0;
$table = 'Currency';
$serial = 'currencies_id_seq';
%fields = (
	id		=>	'id',
	short	=>	'code',
	name	=>	'name',
	symbol	=>	'symbol',
  #precision =>  'precision',
);
%transforms = (
	id		=> [ 's/\D//g', '<2147483647' ],
	name	=> [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	short => [ 's/\s+//' ],
);
%defaults = (
  precision => 2,
);

$cache_field = 'short';
sub cache_field {
	return $cache_field;
}
sub conversions {
	my ( $self, $to, $period ) = @_;
	return 1 if $$self{id} == $to;
	return 1 if !$$self{id};
	if ( ! exists $$self{Conversions} ) {
		if ( $$self{id} ) {
			%{$$self{Conversions}} = sql::execute( undef, undef, q{SELECT to_id, rate FROM Currency_Conversions WHERE from_id=? AND period_end IS NULL}, $$self{id} );
		} else {
			%{$$self{Conversions}} = ();
		} # end if
	} # end if
	if ( $to ) {
		if ( $$self{Conversions}{$to} ) {
			return $$self{Conversions}{$to};
		} else {
			my $To = new openprint::Currency( $to );
			if ( $To->id() ) {
				if ( ! exists $$To{Conversions} ) {
					%{$$To{Conversions}} = sql::execute( undef, undef, q{SELECT to_id, rate FROM Currency_Conversions WHERE from_id=? AND period_end IS NULL}, $$To{id} );
				} # end if
				if ( my $rate = $$To{Conversions}{$$self{id}} ) {
					return 1/$rate;
				} else {
$openprint::log->error("No conversion rate set for $$self{name} to $$To{name}");
				} # end if
				return;
			} # end if
		} # end if
	} # end if
	return %{$$self{Conversions}};
} # end sub conversions

sub set_conversion {
	my ( $self, $to_id, $rate ) = @_;
	my $Conversion = openprint::Currency_Conversion->find_one({to_id=>$to_id, from_id=>$$self{id},period_end=>undef});
	if ( ! $Conversion ) {
		$Conversion = new openprint::Currency_Conversion();
		$Conversion->set({to_id=>$to_id, from_id=>$$self{id}});
	} else {
		$Conversion->save({period_end=>'NOW()'});
		$Conversion->set({period_start=>'NOW()',period_end=>undef});
	} # end if
	$Conversion->save({rate=>$rate});
} # end sub add_conversion

sub convert_from {
	my ( $self, $value, $options ) = @_;
  my $DST_Currency;
  my $period;
  if ( ref $options eq 'openprint::Currency' ) {
    $DST_Currency = $DST_Currency;
  } elsif ( $options ) {
    $DST_Currency = $$options{DST_Currency} if $$options{DST_Currency};
    $period = $$options{period} if $$options{period};
  }
  $DST_Currency = get_current() if ! $DST_Currency;;

	if ( ! ( $DST_Currency and $$DST_Currency{id} ) ) {
		$log->error("Invalid destination currency in convert_from");
		return $value;
	} elsif ( ! $$self{id} ) {
		$log->error("Invalid src currency in convert_from");
		return $value;
	}

  my $rate;
	if ( $DST_Currency->id() != $$self{id} ) {
    if ( $period ) {
      ( $rate ) = sql::execute(undef, undef, q{SELECT rate FROM Currency_Conversions WHERE from_id=? AND to_id=? AND (period_end IS NULL OR period_end >= ?) AND (period_start IS NULL OR period_start <= ?)}, $$self{id}, $$DST_Currency{id}, $period, $period);
      if ( !$rate ) {
        $log->error("No rate found for converting $$self{name} to $$DST_Currency{name} period $period");
        $rate = $self->conversions($$DST_Currency{id});
      }
    } else {
      $rate = $self->conversions($$DST_Currency{id});
    }
		my $new = $value * $rate;
		$log->debug("Converting $value in $$self{name} to $$DST_Currency{name} using rate $rate $new") if $debug;
		return $new;
	} # end if
	return $value;
} # end sub convert_from

sub convert_to {
	my ( $From, $To, $value ) = @_;
	if ( ! ref $To ) {
		$To = openprint::Currency->find_one('short'=>$To);
	} 
	if ( $From eq 'openprint::Currency' ) {
		$From = get_current();
	} # end if
	if ( ! $To ) {
		$log->error('No Currency for ' . $_[1] );
		return;
	} # end if
	if ( $To and ( $$To{id} != $$From{id} ) ) {
		my $rate = $From->conversions( $To->id() );
		$log->debug("Converting $value in $$From{name} to $$To{name}") if $debug;
		$value *= $rate;
	} # end if
	return $value;
} # end sub

# Takes a ref to a price
# The price has a currency_id
# if $$price{currency_id} is not the Session's Currency, then convert it , and return
sub convert {
	my $Price = $_[0];

	if ( ref $Price eq 'ARRAY' or ref $Price eq '' ) {
		Carp::cluck("Non hash price passed to Currency::convert from");
		return;
	}

	# Get display_currency
	my $DST_Currency = get_current();
	if ( $DST_Currency ) {
		if ( $$DST_Currency{id} != $$Price{currency_id} ) {
			my $SRC_Currency = $$Price{Currency} ? $$Price{Currency} : new openprint::Currency( $$Price{currency_id} );
			my $rate = $SRC_Currency->conversions( $DST_Currency->id() );
			if ( $rate ) {
				$$Price{Price} *= $rate;
				$$Price{price} *= $rate;
				$$Price{cost} *= $rate;
			}
#$log->debug("Converting $$Price{Price} in $$SRC_Currency{name} to $$DST_Currency{name}") if $debug;
			$$Price{currency_id} = $DST_Currency->id();
			$$Price{Currency} = $DST_Currency;
		} # end if
	} # end if
	return $Price;
} # end sub convert

sub get_current {

	if ( $openprint::Currency ) {
		return $openprint::Currency;
	}

	if ( $openprint::session{Currency_id} ) {
		return new openprint::Currency( $openprint::session{Currency_id} );
	} # end if

	if ( ( ! $openprint::session{Currency_id} ) and $openprint::session{company_id} ) {
		my $Company = new openprint::Company( $openprint::session{company_id} );
		$openprint::session{Currency_id} = $Company->currency_id();
	} # end if

	if ( ! $openprint::session{Currency_id} ) {
		my $list_id = openprint::pricing::get_pricelist_id( );
		my $Pricelist = new openprint::Pricelist( $list_id );
		$openprint::session{Currency_id} = $Pricelist->currency_id();
	} # end if
	if ( ! $openprint::session{Currency_id} ) {
		if ( $openprint::config{Currency} ) {
			my @Currencies = openprint::Currency->find('short'=>$openprint::config{Currency});
			if ( @Currencies ) {
				$openprint::session{Currency_id} = $Currencies[0]->id();
			} # end if
		} # end if
	} # end if
	if ( $openprint::session{Currency_id} ) {
		return new openprint::Currency( $openprint::session{Currency_id} );
	} # end if
	return new openprint::Currency();

} # end sub get_currency

sub format {
	my ( $Currency, $price, $precision, $symbol );
	if ( ref $_[0] eq 'openprint::Currency' ) {
		( $Currency, $price, $precision, $symbol ) = @_;
	} else {
		( $price, $precision, $symbol ) = @_;
		$Currency = get_current();
	} # end if
	

	$price = 0 if ! $price;
	$precision = $$Currency{precision} if ! defined $precision;
  $precision = 2 if ! defined $precision;
  $symbol = $Currency->symbol() if ! defined $symbol;
	require Number::Format;
	my $Formatter = new Number::Format(
			-decimal_digits     =>  $precision,
			-int_curr_symbol    =>  $symbol,
			);
	return $Formatter->format_price($price, $precision);
} # end sub format

1;
__END__
