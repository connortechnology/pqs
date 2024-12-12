use strict;
package openprint::ProjectTypeCategory;
our @ISA = qw( openprint::Object );

use vars qw( $debug %fields %transforms %defaults $table $serial );

$debug = 1;
$table =  'project_type_group';
$serial = 'projecttype_categories_id_seq';

%fields = (
	id	=>	'id',
	name	=>	'name',
	sort	=>	'sort',
);
%transforms = (
    name => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
	sort	=>	undef,
);

sub ProjectTypes {
	require openprint::ProjectType;
	my $self = shift;
	
	if ( @_ ) {
		my %params;
		if ( ref $_[0] eq 'HASH' ) {
			%params = %{$_[0]};
		} else {
			%params = @_;
		} # end if
		$params{'category_id'} = $$self{'id'};
		return openprint::ProjectType->find( %params );
	} elsif ( ! $$self{'ProjectTypes'} ) {
		@{$$self{'ProjectTypes'}} = openprint::ProjectType->find( 'category_id'=>$$self{'id'} );
	} # end if
	return @{$$self{'ProjectTypes'}};
} # end sub ProjectTypes

sub description {
	return $_[0]->name();
} # end sub description

1;
__END__
