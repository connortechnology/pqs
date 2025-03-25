use strict;
package openprint::Project_Service_Operator;
our @ISA = qw(openprint::Object);

require openprint;
require openprint::Project;
require openprint::User;
require openprint::ServiceType;
require openprint::Operator_Role;

use vars qw( $debug %fields %find_fields %transforms %defaults $table $serial );

$debug = 0;
%fields = (
	id					=>	'id',
	service_id	=>	'service_id',
	user_id			=>	'user_id',
	User				=>	undef,
	role_id			=>	'role_id',
	Role				=>	undef,
);
%find_fields = (
);
%transforms = (
);
%defaults = (
	role_id	=>	undef,
	user_id	=>	undef,
);
$table = 'project_service_operators';
$serial = 'project_service_operators_id_seq';

sub Project {
	return $_[0]->Service()->Project();
} # end sub Project

sub Service {
	return openprint::Service->find_one(service_id=>$_[0]{service_id});
}

sub User {
	if ( @_ > 1 ) {
		$_[0]{User} = $_[1];
		$_[0]{user_id} = $_[0]{User} ? $_[0]{User}{id} : undef;
	}
	if ( !$_[0]{User} ) {
		$_[0]{User} = new openprint::User($_[0]{user_id});
	}
	return $_[0]{User};
} # end sub User

sub Role {
	if ( @_ > 1 ) {
		$_[0]{Role} = $_[1];
		$_[0]{role_id} = $_[0]{Role} ? $_[0]{Role}{id} : undef;
	}
	if ( ! $_[0]{Role} ) {
		$_[0]{Role} = new openprint::Operator_Role($_[0]{role_id});
	}
	return $_[0]{Role};
} # end sub Role

1;
__END__
