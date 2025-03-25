package openprint::Invoiced_Project;
@ISA = qw(openprint::Object);

use vars qw( %config $log $dbh %session );
*session = \%openprint::session;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;

my $debug = 0;

use strict;
use vars qw( $table $serial %fields %defaults %transforms %find_cache );

$table = 'invoiced_projects';
$serial = 'invoiced_projects_id_seq';

require sql;

%fields = (
	'id'				=>	'id',
	'price'				=>	'price',
	'quantity'			=>	'quantity',
	'invoice_id'		=>	'invoice_id',
	'project_id'		=>	'project_id',
	'description'		=>	'description',
	'po'				=>	'po',
);

%transforms = (
);
%defaults = (
	invoice_id	=>	undef,
	project_id	=>	undef,
	price		=>	undef,	# undef means look it up in the Product
	quantity	=>	undef,
);

sub Invoice {
	if ( @_ > 1 ) {
		$_[0]{Invoice} = $_[1];
	}
	$_[0]{Invoice} = new openprint::Invoice( $_[0]{invoice_id} ) if ! $_[0]{Invoice};
	
	return $_[0]{Invoice};
} # end sub Invoice

sub Project {
	return new openprint::Project( $_[0]{project_id} );
} # end sub Product

sub name {
	return $_[0]->Project()->name();
} # end sub name

sub total {
	my ( $self ) = @_;
	return $$self{'quantity'} * $self->price();
} # end sub total

sub price {
	my $self = $_[0];
	if ( @_ == 2 ) {
		$$self{price} = $_[1];
	} # end if
	if ( ( ! defined $$self{price} ) and $$self{project_id} ) {
		my %Price = $self->Project()->get_price( $$self{quantity} );
		$$self{price} = $Price{Price};
	} # end if
	return $$self{price};
} # end sub price

sub description {
	my ( $self ) = @_;
	if ( ( ! $$self{'description'} ) and $$self{'project_id'} ) {
		$$self{'description'} = $self->Project()->name();
	} # end if
	return $$self{'description'};
} # end if

1;
__END__
