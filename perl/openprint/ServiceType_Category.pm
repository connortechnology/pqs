use strict;
package openprint::ServiceType_Category;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'ServiceType_Categories';
$serial = 'ServiceType_Categories_id_seq';

%fields = (
	id				=> 'id',
	name			=> 'name',
	sorting		=> 'sorting',
);
%transforms = (
);
%defaults = (
	sorting		=>	undef,
);


sub ServiceTypes {
	require openprint::ServiceType;
	my $self = shift;
	
	if ( @_ ) {
		my %params;
		if ( ref $_[0] eq 'HASH' ) {
			%params = %{$_[0]};
		} else {
			%params = @_;
		} # end if
		$params{category_id} = $$self{id};
		return openprint::ServiceType->find( %params );
	} elsif ( ! $$self{ServiceTypes} ) {
		@{$$self{ServiceTypes}} = openprint::ServiceType->find( category_id=>$$self{id} );
	} # end if
	return @{$$self{ServiceTypes}};
} # end sub ServiceTypes

sub description {
	return $_[0]->name();
} # end sub description
1;
__END__
