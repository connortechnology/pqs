use strict;
package openprint::PaperPrice;
our @ISA = qw(openprint::Object);

require Math::Round;
require openprint::Pricelist;
require openprint::Equipment;

use vars qw( $debug $table $serial %find_fields %fields %transforms %defaults );
$debug = 0;
$table = 'tbl_paper_prices';
$serial = 'tbl_paper_prices_id_seq';

%fields = (
	id			=>	'id',
	pricelist_id	=>	'lnglistindex',
	paper_id		=>	'lngpaperindex',	
	min			=>	'lngmin',
	max			=>	'lngmax',
	units			=>	'strunits',
	cost			=>	'dblcost',
	markup		=>	'dblmarkup',
	price			=>	'dblprice',
	discountable	=>	'ysndiscountable',
	interpolate	=>	'interpolate',
  service		=>	'service',
  equipment_id	=>	'equipment_id',
	stock_id		=>	undef,
  Stock=>undef,
  Paper => undef,
);
%find_fields = (
	stock_id	=>	'lngpaperindex',
);
%transforms = (
	min => [ 's/,//g', 's/(\d*)/$1/g' ],
	max => [ 's/,//g', 's/(\d*)/$1/g' ],
	cost => [ 's/[^\d\.]//g' ],
	price => [ 's/[^\d\.]//g' ],
	markup => [ 's/[^\d\.]//g' ],
);
%defaults = (
	equipment_id	=>	undef,
	min => undef,
	max => undef,
  units => '100 lbs',
	cost => 0,
	price => 0,
	markup => 0,
	interpolate	=>	'1',
	discountable	=>	q`'Y'`,
);

sub Pricelist {
	return new openprint::Pricelist( $_[0]{pricelist_id} );
} # end sub Pricelist

sub Equipment {
	return new openprint::Equipment( $_[0]{equipment_id} );
} # end sub Pricelist

sub delete {
	my $Paper = $_[0]->Paper();
	delete $$Paper{Prices};
	return $_[0]->SUPER::delete();
} # end sub delete

sub costperm {
	my $self = shift;
	my $Paper = $self->Paper();
	if ( $Paper->wpsi() ) {
		# Roll papers won't have an mweight
		return Math::Round::nearest(0.01, $$self{cost} * $Paper->wpsi() * $Paper->width() * $Paper->height() * 10 );
	} elsif ( $Paper->mweight() ) {
		return Math::Round::nearest(0.01, $$self{cost} * $Paper->mweight() / 100 );
	} # end if
  $openprint::log->error("Can't calculate costperm");
  return undef;
} # end sub costperm

sub priceperm {
	my $self = shift;
	my $Paper = $self->Paper();
	if ( $Paper->wpsi() ) {
		# ROll papers won't have an mweight
		return Math::Round::nearest(0.01, $$self{price} * $Paper->wpsi() * $Paper->width() * $Paper->height() * 10 );
	} elsif ( $Paper->mweight() ) {
		return Math::Round::nearest(0.01, $$self{price} * $Paper->mweight() / 100 );
	} # end if
  return undef;
} # end sub priceperm

sub costperfoot {
	my $self = $_[0];
	my $Paper = $self->Paper();
	return Math::Round::nearest(0.01, ($$self{cost}/100 ) * ( $Paper->wpsi() * 144 ) );
}

sub priceperfoot {
	my $self = $_[0];
	my $Paper = $self->Paper();
	return Math::Round::nearest(0.01, $$self{price} * ( $Paper->wpsi() * 144 ) /100 );
}

sub markup {
	if ( @_ > 1 ) {
		$_[0]{markup} = $_[1];
	} # end if
	return $_[0]{markup};
} # end sub markup

sub price {
	if ( @_ > 1 ) {
		$_[0]{price} = $_[1];
	} # end if
	if ( ! defined $_[0]{price} ) {
		$_[0]{price} = Math::Round::nearest(0.01, $_[0]{cost} * ( 1+($_[0]{markup}/100) ) );
	} # end if
	return $_[0]{price};
}

sub stock_id {
	if ( @_ > 1 ) {
		$_[0]{paper_id} = $_[1];
	} # end if
	return $_[0]{paper_id};
} # end sub stock_id

sub Stock {
  my $self = shift;
  $$self{Stock} = shift if @_;
  $$self{Stock} = new openprint::Paper( $$self{paper_id} ) if !$$self{Stock};
  return $$self{Stock};
}

sub Paper {
  return Stock(@_);
}

sub id_string {
	my $Price = $_[0];
	my $price_desc = '';
	if ( ! ( $Price->min() or $Price->max() ) ) {
		$price_desc .= 'all quantities';
	} else {
		if ( $Price->min() ) {
			$price_desc .= 1*$Price->min() . ' ';
		}
		$price_desc .= 'up';
		if ( $Price->max() ) {
			$price_desc .= ' to ' . 1*$Price->max();
		}
	} # end if
	return $Price->Pricelist()->name() . ' '. $price_desc . ' on ' . $Price->Equipment()->strid();
}

1;
__END__
