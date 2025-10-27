package openprint::price;

use strict;

sub new {
	my ( $type, $log, $dbh, $group ) = @_;
	my $self = {};
	bless $self, $type;

	$self->{log} = $log;
	$self->{dbh} = $dbh;
	$self->{group} = $group;

	return $self;
}

sub save {
	my $self = shift;

	sql::insert( $self->{log}, $self->{dbh}, 'tbl_Prices',
		'lngListIndex',			$self->{group}->{list_id},
		'lngIndex',				$self->{group}->{product_index},
		'lngEquipmentIndex',	$self->{equipment_index},
		'lngMin',				( $self->{min} eq '' ? undef : $self->{min} ),
		'lngMax',				( $self->{max} eq '' ? undef : $self->{max} ),
		'strUnits',				( $self->{units} eq '' ? undef : $self->{units} ),
		'dblCost',				( $self->{Cost} eq '' ? undef : $self->{Cost} ),
		'dblMarkup',			( $self->{Markup} eq '' ? undef : $self->{Markup} ),
		'dblPrice',				( $self->{Price} eq '' ? undef : $self->{Price} )
	);
} # end sub save

sub set {
	my $self = shift;
	#$self->{log}->debug("In Set");
	setEquipment( $self, shift );
	setMin( $self, shift );
	setMax( $self, shift );
	setRangeUnits( $self, shift );
	setUnits( $self, shift );
	setCost( $self, shift );
	setMarkup( $self, shift );
	setPrice( $self, shift );
	setDiscountable( $self, shift );
} # end sub set

sub setDiscountable {
	my $self = shift;
	$self->{Discountable} = shift;
}
sub setEquipment {
	my $self = shift;
	$self->{equipment_index} = shift;
}

sub setMin {
	$_[0]{min} = $_[1];
}

sub setMax {
	$_[0]{max} = $_[1];
}

sub setRangeUnits {
	my $self = shift;
	$self->{range_units} = shift;
}
sub setUnits {
	my $self = shift;
	$self->{units} = shift;
}

sub setCost {
    $_[1] =~ s/([^\d\.])//g;
    $_[0]{Cost} = $_[1];
}

sub setMarkup {
    $_[1] =~ s/\%//g;
    $_[0]{Markup} = $_[1];
}

sub setPrice {
    $_[1] =~ s/([^\d\.])//g;
    $_[0]->{Price} = $_[1];
}

sub copy {
	my $self = shift;
	my $src = shift;

	setEquipment( $self, $src->{equipment_index} );
	setMin( $self, $src->{min} );
	setMax( $self, $src->{max} );
	setRangeUnits( $self, $src->{range_units} );
	setUnits( $self, $src->{units} );
	setCost( $self, $src->{Cost} );
	setMarkup( $self, $src->{Markup} );
	setPrice( $self, $src->{Price} );
	setDiscountable( $self, $src->{Discountable} );
	$$self{interpolate} = $$src{interpolate};
} # end sub copy

1;
__END__
