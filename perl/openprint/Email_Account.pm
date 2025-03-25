use strict;
package openprint::Email_Account;
our @ISA = qw( openprint::Object );
require openprint::Email_Alias;

use vars qw( $debug $table $serial %fields %transforms %defaults @identified_by $dbh );
@identified_by = ( 'username' );

$table = 'mailbox';

%fields = (
	username	=>	'username',
	password	=>	'password',
	name			=>	'name',
	maildir		=>	'maildir',
	quota			=>	'quota',
	domain		=>	'domain',
	local_part	=>	'local_part',
	created_on	=>	'created',
	updated_on	=>	'modified',
	active		=>	'active',
);

%defaults = (
	local_part => q`$self->local_part();`,
	domain		=>	q`$self->domain();`,
	maildir		=>	q`$self->maildir();`,
	created_on	=>	'NOW()',
	updated_on	=>	'NOW()',
	quota				=>	-1,
);


sub local_part {
	if ( ( ! $_[0]{local_part} ) and $_[0]{username} ) {
		my ( $local_part, $domain ) = split( '@', $_[0]{username} );
		$_[0]{local_part} = $local_part;
	}
	return $_[0]{local_part};
}
sub domain {
	if ( ( ! $_[0]{domain} ) and $_[0]{username} ) {
		my ( $local_part, $domain ) = split( '@', $_[0]{username} );
		$_[0]{domain} = $domain;
	}
	return $_[0]{domain};
}
sub maildir {
	if ( ( ! $_[0]{maildir} ) and $_[0]{username} ) {
		my ( $local_part, $domain ) = split( '@', $_[0]{username} );
		$_[0]{maildir} = join( '/', $domain, $local_part, '' );
$openprint::log->debug("Setting maildir");
	} else {
$openprint::log->debug("not Setting maildir");
	}
	return $_[0]{maildir};
}
sub save {
	my ( $self, $hash ) = @_;
	my $rc  = $self->SUPER::save( $hash );
	if ( ! $rc ) {
		my $Alias = openprint::Email_Alias->find_one( address=>$$self{username}, dbh=>$dbh );
		if ( ! $Alias ) {
			$Alias = new openprint::Email_Alias();
			$rc .= $Alias->save({ address=>$$self{username}, goto=>$$self{username}, active=>1, dbh=>$dbh });
		}
	}
	return $rc;
} # end sub save

1;
__END__
