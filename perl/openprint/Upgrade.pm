use strict;

package openprint::Upgrade_Type;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'upgrade_types';
$serial = 'upgrade_types_id_seq';

%fields = ( 
	id	=>	'id',
	name=>	'name',
);
%transforms = (
	id	=>	['s/\D//g'],
    name => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
);

package openprint::Upgrade;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'upgrades';
$serial = 'upgrades_id_seq';

%fields = ( 
	id	=>	'id',
	rma_id	=>	'rma_id',
	type_id	=>	'type_id',
	type	=>	undef,
	old_version	=>	'old_version',
	new_version	=>	'new_version',
);
%transforms = (
	id	=>	['s/\D//g'],
	rma_id	=>	['s/\D//g'],
	type_id	=>	['s/\D//g'],
    old_version => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    new_version => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
);

sub Type {
	return new openprint::Upgrade_Type( $_[0]{type_id} );
} # end sub Type

sub type {
	if ( @_ > 1 ) {
		my $Type = openprint::Upgrade_Type->find_one('name lc'=> lc openprint::Upgrade_Type->transform('name',$_[1]) );
		if ( ! $Type ) {
			$Type = new openprint::Upgrade_Type();
			$Type->save({name=>$_[1]});
		} # end if
		$_[0]{type_id} = $Type->id();
		$_[0]{type} = $Type->name();
	} # end if
	if ( ! $_[0]{type} ) {
		$_[0]{type} = new openprint::Upgrade_Type( $_[0]{type_id} )->name();
	} # end if
	return $_[0]{type};
} # end sub type
1;
__END__
