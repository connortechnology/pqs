use strict;
package openprint::PaperInventory;
our @ISA = qw(openprint::Object);
require openprint::Object;

use openprint ();
use vars qw( $table $debug $serial %fields %transforms %defaults );

require sql;
require openprint::Skid;

$debug = 0;
$table = 'paper_inventory';
$serial = 'paperinventory_id_seq';

%fields = (
	id			=>	'id',
	paper_id	=>	'paper_id',
	user_id		=>	'user_id',
	instock		=>	'instock',
	updated_on	=>	'updated_on',
	delta		=>	'delta',
	comment		=>	'comment',
	skid_id		=>	'skid_id',
	units		=>	'units',
	docket		=>	'docket',
	project_id	=>	'project_id',
);
# project_id is deprecated
%transforms = (
	project_id	=>	 [ 's/\D//g' ],
	paper_id	=>	[ 's/\D//g' ],
	skid_id		=>	[ 's/\D//g' ],
	user_id		=>	[ 's/\D//g' ],
	instock		=>	[ 's/\D//g' ],
	docket		=>	[ 's/\D//g' ],
	delta		=>	[ 's/[^\d\-]//g' ],
);
%defaults = (
	updated_on	=>	q`'NOW()'`,
	docket		=>	undef,
	project_id	=>	undef,
	instock		=>	undef,
	paper_id	=>	undef,
);

sub Paper {
	return new openprint::Paper( $_[0]{paper_id} );
} # end sub Paper
sub Skid {
	return new openprint::Skid( $_[0]{skid_id} );
} # end sub Skid
sub User {
	return new openprint::User( $_[0]{user_id} );
} # end sub User

sub docket {
	my $self = shift;
	if ( @_ ) {
		$$self{docket} = shift;
		$$self{docket} =~ s/\D//g;
	} # end if
	if ( ! $$self{docket} ) {
		if ( $$self{comment} =~ /docket (\d+)/ ) {
			$$self{docket} = $1;
		} # end if
	} # end if
	return $$self{docket};
} # end sub docket

sub Project {
	my $self = $_[0];
	return new openprint::Project() if ! $$self{docket};
	my @Projects = openprint::Project->find('docket'=>$$self{docket});
	if ( @Projects ) {
		return $Projects[0];
	} # end if
	return new openprint::Project();
} # end sub Project

sub comment_html {
	my ( $self ) = @_;

	if ( $$self{comment} =~ /^Checked out for docket (\d+) by (.*)$/ ) {
		return qq`Checked out for docket <a href="/employee/project/view.html?docket=$1">$1</a> by $2`;
	} elsif ( $$self{comment} =~ /^Checked out for docket (\d+)$/ ) {
		return qq`Checked out for docket <a href="/employee/project/view.html?docket=$1">$1</a>`;
	} elsif ( $$self{comment} =~ /^Allocated (\d+)lbs to docket (\d+)$/ ) {
		return qq`Allocated ${1}lbs to docket <a href="/employee/project/view.html?docket=$2">$2</a>`;
	} elsif ( $$self{comment} =~ /^Inventory adjusted from manifest (.+)\.$/ ) { 
		return qq`Inventory adjusted from manifest <a href="/employee/inventory/manifests.html?manifest_name=$1">$1</a>`;
	} # end if
	return $$self{comment};
} # end comment_html

sub instock {
	my $self = shift;
	if ( @_ ) {
		$$self{instock} = shift;
	} # end if
	if ( ! defined $$self{instock} ) {
		@$self{instock} = sql::execute( undef, undef, 'SELECT SUM(delta) FROM Paper_Inventory WHERE paper_id=? AND id <= ?', @$self{'paper_id', 'id'} );
	} # end if
	return $$self{instock};
} # end sub instock

sub units {
	if ( ! $_[0]{units} ) {
		$_[0]{units} = $_[0]->Paper()->units();
	} 
	return $_[0]{units};
} # end sub units

sub Cost {
	return $_[0]->Skid()->Cost();	
}

sub Value {
	my $Cost = $_[0]->Cost();
	my $qty = -1*$_[0]{delta};
	if ( $_[0]{units} eq 'sheets' ) {
		my $Paper = $_[0]->Paper();
		if ( $Paper->type() ne 'Roll' ) {
		$qty = $qty * $$Paper{width} * $$Paper{height} * $Paper->wpsi();
		}
	}
	$$Cost{value} = $$Cost{cost} * $qty / 100;
	return $Cost;
}

1;
__END__
