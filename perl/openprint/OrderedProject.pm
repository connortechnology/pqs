use strict;
package openprint::OrderedProject;
our @ISA=qw(openprint::Object);

require openprint::Object;
require openprint::Project;
require openprint::Project_Service;
require openprint::Order;

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'order_contents';
$serial = 'order_contents_id_seq';

%fields = (
	id				=>	'id',
	order_id		=>	'orderindex',
	project_id		=>	'lngprojectindex',
	quantity		=>	'intquantity',
	quantity_index	=>	'intquantityindex',
	price			=>	'cursalesprice',
	shipping_type	=>	'shippingtype',
	requested_for	=>	'daterequired',
	duedate			=>	'duedate',
	gst				=>	'dbltax1',
	hst				=>	'dbltax2',
	pst				=>	'dbltax3',
	description		=>	'strdescription',
);

sub Project {
	if ( ! $_[0]{Project} ) {
		$_[0]{Project} = new openprint::Project( $_[0]{project_id} );
		$_[0]{Project}{OrderedProject} = $_[0];
	}
	return $_[0]{Project};
} # end sub Project

sub cost {
    my ( $self, $qty_index, $new_value ) = @_;
    if ( @_ == 3 ) {
        $$self{'cost'.$qty_index} = $new_value;
    } # end if
    if ( ! (1*$$self{'cost'.$qty_index}) ) {
		my $Project = $self->Project();
        $$self{'cost'.$qty_index} = Math::Round::nearest( 0.01, $Project->Currency()->convert_to( $self->Order()->Currency(), $Project->price($qty_index) ) );
    } # end if
    return $$self{'cost'.$qty_index};
} # end sub cost

# Price returned should be in the rder's currency
sub price {
	if ( @_ > 1 ) {
		$_[0]{price} = $_[1];
	} # end if

	if ( ! $_[0]{price} ) {
		my $Project = $_[0]->Project();
		$_[0]{price} = Math::Round::nearest( 0.01, $Project->Currency()->convert_to( $_[0]->Order()->Currency(), $Project->price( $_[0]->quantity_index() ) ) );
	} # end if
	return $_[0]{price};
} # end sub price

sub quantity {
	if ( @_ > 1 ) {
		$_[0]{quantity} = $_[1];
	} # end if
	if ( ! $_[0]{quantity} ) {
		$_[0]{quantity} = $_[0]->Project()->quantity( $_[0]->quantity_index() );
	} # end if
	return $_[0]{quantity};
} # end sub quantity

sub delete {
	my $self = shift;

	my $error;
	require sql;
	my $ac = sql::start_transaction( $openprint::dbh );
	my $Project = $self->Project();
	$Project->add_to_log( @openprint::session{'company_id','user_id'}, "Removed from order $$self{order_id}" );
	$Project->docket( '' );
	$Project->order_id( '' );
	$error .= $Project->save();
	$Project->update_status();
	sql::execute( undef, undef, q{DELETE FROM Order_Contents WHERE OrderIndex=? AND lngProjectIndex=?}, @$self{'order_id','project_id'});
	$error .= $openprint::dbh->errstr();
	sql::end_transaction( $openprint::dbh, $ac );
	return $error;
} # end sub delete

sub shippingtype {
	my ( $self, $new ) = @_;
	if ( $new ) {
		$$self{shippingtype} = $new;
	} # end if
	if ( ! $$self{shippingtype} ) {
		my $services = $self->Project()->services();
		$$self{shippingtype} = join(',', map { $_->ServiceType()->name() } openprint::Project_Service->find(project_id=>$$self{project_id}, category=>'Shipping') );
	} # end if
	return $$self{shippingtype};
} # end sub shippingtype

sub description { 
	if ( @_ > 1 ) {
		$_[0]{description} = $_[1];
	} # end if
	if ( ! $_[0]{description} ) {
		$_[0]{description} = $_[0]->Project()->reference();
	} # end if
	return $_[0]{description};
} # end sub description

1;
__END__
