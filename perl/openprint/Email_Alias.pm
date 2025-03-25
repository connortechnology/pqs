use strict;
package openprint::Email_Alias;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table $serial %fields %transforms %defaults @identified_by $dbh );
@identified_by = ( 'address' );

$table = 'alias';

%fields = map { $_, $_ } qw( 
address
goto
domain
created
modified
active 
);

%defaults = (
	domain		=>	q`$self->domain();`,
	created		=>	'NOW()',
	modified	=>	'NOW()',
);


sub domain {
	if ( ( ! $_[0]{domain} ) and $_[0]{address} ) {
		my ( $local_part, $domain ) = split( '@', $_[0]{address} );
		$_[0]{domain} = $domain;
	}
	return $_[0]{domain};
}

1;
__END__
