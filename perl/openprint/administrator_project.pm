package openprint::administrator_project;

use strict;
require openprint::main_project;
require openprint::print_project;

sub view {
	openprint::main_project::view( $openprint::param{'ProjectIndex'} );
} # end sub view_project

sub summary {
	openprint::print_project::summary( @_ );
}

sub docket {
	openprint::print_project::summary( @_ );
}

1;
__END__
