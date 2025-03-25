use strict;
package openprint::Claim_Content;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );

require openprint::Claim_ContentType;
require openprint::Claim;
require openprint::Skid;

$debug = 0;

$table = 'claim_contents';
$serial = 'claim_contents_id_seq';

%fields = (
	'id'				=>	'id',
	'claim_id'			=>	'claim_id',
	'skid_id'			=>	'skid_id',
	'quantity'			=>	'quantity',
	'quantity_units'	=>	'quantity_units',
	'weight'			=>	'weight',
	'weight_units'		=>	'weight_units',
	'reason'			=>	'reason',
	'description'		=>	'description',
	'cost'				=>	'cost',
	'cost_units'		=>	'cost_units',
	'type_id'			=>	'type_id',
);

%transforms = (
	'quantity'	=> [ 's/[^\d\.]//g' ],
	'skid_id'	=> [ 's/\D//g' ],
	'type_id'	=> [ 's/\D//g' ],
	'cost'		=> [ 's/[^\d\.]//g' ],
);

%defaults = (
	'quantity'		=> 0,
	'quantity_units'	=>	undef,
	'weight'		=> 0,
	'weight_units'	=>	undef,
	'type_id'		=>	undef,
	'skid_id'		=>	undef,
	'cost'			=>	undef,
	'cost_units'	=>	undef,
);

sub Skid {
	return new openprint::Skid( $_[0]{skid_id} );
} # end sub Skid

sub Claim {
	return new openprint::Claim( $_[0]{claim_id} );
} # end sub Manifest

sub Type {
	if ( @_ > 1 ) {
		$_[0]{'type_id'} = $_[1]->id();
	} # end if
	return new openprint::Claim_ContentType( $_[0]{type_id} );
} # end sub Manifest

sub description {
	my ( $self ) = @_;
	if ( @_ > 1 ) {
		$$self{'description'} = $_[1];
	} # end if
	if ( ! $$self{'description'} ) {
		my $description;
		foreach my $SkidContent ( $self->Skid()->Contents() ) {
			$description .= $SkidContent->Paper()->to_string().'<br/>';
		} # end foreach SkidContent
		$$self{'description'} = $description;
	} # end if

	return $$self{'description'};
} # end sub description

sub total {
	my ( $self ) = @_;
	if ( $$self{'cost_units'} eq 'Each' ) {
		return sprintf('%.2f', $$self{'cost'} * $$self{'quantity'} );
	} elsif ( $$self{'cost_units'} eq '/100lb' ) {
		return sprintf('%.2f', $$self{'cost'} * $$self{'weight'}/100 );
	} elsif ( $$self{'cost_units'} eq '/Kg' ) {
		return sprintf('%.2f', $$self{'quantity'} * $$self{'cost'} * $$self{'weight'}*453.59237 );
	} elsif ( $$self{'cost_units'} eq '/1000' ) {
		return sprintf('%.2f', $$self{'cost'} * $$self{'quantity'}/1000 );
	} # end if
	return sprintf('%.2f', $$self{'cost'} * $$self{'quantity'} );
} # end sub total

sub save {
	my ( $self, $hash ) = @_;
	if ( $$self{'id'} ) {
		return $self->SUPER::save( $hash );
	} else {
		my $rc = $self->SUPER::save( $hash );	
		my $Claim = $self->Claim();
		if ( ! sets::isin( $$self{'id'}, [ map { $_->id() } $Claim->Contents() ] ) ) {
			push @{$$Claim{'Contents'}}, $self;
		} # end if
		return $rc;
	} # end if
} # end sub save

1;
__END__
