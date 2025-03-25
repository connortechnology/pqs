use strict;
package openprint::QuotedProject;
our @ISA = qw(openprint::Object);

use openprint ();
use vars qw( $debug $table $serial %fields %transforms %defaults );

require openprint::QuoteLevel;
require openprint::Quote;
require openprint::Project;
require Math::Round;

$debug = 0;

$table = 'tbl_quote_details';
$serial = 'tbl_quote_details_id_seq';
%fields = (
		id						=>	'id',
		quantity1			=>	'intquantity1',
		quantity2			=>	'intquantity2',
		quantity3			=>	'intquantity3',
		markup1				=>	'dblmarkup1',
		markup2			=>	'dblmarkup2',
		markup3			=>	'dblmarkup3',
		price1			=>	'dblprice1',
		price2			=>	'dblprice2',
		price3			=>	'dblprice3',
		template_id		=>	'template_id',
		include_detailed	=>	'include_detailed',
		project_id		=>	'project_id',
		quote_id			=>	'quote_id',
		description				=>	'strdescription',
		cost1		=>	undef,
		cost2		=>	undef,
		cost3		=>	undef,
);

%transforms = (
);

%defaults = (
	id			=> undef,
	markup1	=> undef,
	markup2	=> undef,
	markup3	=> undef,
	price1	=> undef,
	price2	=> undef,
	price3	=> undef,
);

sub template_id {
	if ( @_ > 1 ) {
		$_[0]{template_id} = $_[1];
	} # end if
	if ( $_[0]{template_id} ) {
		return $_[0]{template_id};
	} else {
		return $_[0]->Project()->style_id();
	} # end if
} # end sub template_id

sub Template {
	if ( $_[0]{template_id} ) {
		return new openprint::QuoteLevel( $_[0]{template_id} );
	} else {
		return $_[0]->Project()->Template();
	} # end if
} # end sub Template

sub Project {
	return new openprint::Project( $_[0]{project_id} );
} # end sub Project
sub Quote {
	return new openprint::Quote( $_[0]{quote_id} );
} # end sub Quote

sub markup {
	if ( @_ == 3 ) {
		$_[0]{'markup'.$_[1]} = $_[2];
		$_[0]->price($_[1], undef);
	} # end if
	return $_[0]{'markup'.$_[1]};
} # end sub total

sub cost {
	my ( $self, $qty_index, $new_value ) = @_;
	if ( @_ == 3 ) {
		$$self{'cost'.$qty_index} = $new_value;
	} # end if
	if ( ! (1*$$self{'cost'.$qty_index}) ) {
		$$self{'cost'.$qty_index} = Math::Round::nearest( 0.01, $self->Project()->Currency()->convert_to( $self->Quote()->Currency(), $self->Project()->price($qty_index) ) );
	} # end if
	return $$self{'cost'.$qty_index};
} # end sub cost

sub price {
	my ( $self, $qty_index, $new_value ) = @_;
	if ( @_ == 3 ) {
		$$self{'price'.$qty_index} = $new_value;
	} # end if
	if ( ! (1*$$self{'price'.$qty_index}) ) {
		$$self{'price'.$qty_index} = Math::Round::nearest( 0.01, $self->Project()->Currency()->convert_to( $self->Quote()->Currency(), $self->Project()->price($qty_index) * ( 1 + $$self{'markup'.$qty_index}/100 ) ) );
	} # end if
	return $$self{'price'.$qty_index};
} # end sub price

sub quantity {
	my ( $self, $qty_index, $new_value ) = @_;
	if ( @_ == 3 ) {
		$$self{'quantity'.$qty_index} = $new_value;
	} # end if
	if ( ! $$self{'quantity'.$qty_index} ) {
		$$self{'quantity'.$qty_index} = $self->Project()->quantity($qty_index);
	}
	return $$self{'quantity'.$qty_index};
} # end sub total

sub quantity_indexes {
	my ( $self ) = @_;
	if ( ! exists $$self{quantity_indexes} ) {
		@{$$self{quantity_indexes}} = ();
		foreach my $qty_index ( 1 .. 3 ) {
			push @{$$self{quantity_indexes}}, $qty_index if $self->quantity($qty_index);
		} # end foreach qty_index
	} # end if
	return @{$$self{quantity_indexes}};
} # end sub quantity_indexes

1;
__END__
