use strict;
package openprint::Pricelist;
our @ISA = qw(openprint::Object);

require sql;
#require openprint::MaterialPrice;
#require openprint::ServicePrice;
require openprint::PaperPrice;
require openprint::Currency;
require openprint;

use vars qw( $debug $table $serial %fields %transforms %defaults $default_sort);

$debug = 0;
$table = 'pricelist';
$default_sort = 'lower(name)';
$serial = 'price_list_id_seq';
%fields = (
	'id'			=>	'id',
	'name'			=>	'name',
  #'owner_id'		=>	'owner_id',
	'currency_id'	=>	'currency_id',
	description	=>	'description',
  #'deleted'		=>	'deleted',
  discount => 'discount',
);
%defaults = (
	owner_id  	=>	q`$openprint::session{'company_id'}`,
	deleted     =>	0,
	currency_id	=>	undef,
);
%transforms = (
	id			=>	[ 's/\D//g', '<2147483647' ],
	name		=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	description		=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);

sub destroy {
	my $self = shift;

	my @PaperPrices = $self->getPrices('Paper');
	my $ac = sql::start_transaction( $openprint::dbh );
	sql::update( undef, undef, 'companies', ['pricelist_id=?', $$self{'id'}], 'pricelist_id', undef );
    sql::execute( $openprint::log, $openprint::dbh, q{DELETE FROM Service_Prices WHERE pricelist_id=?}, $$self{id} );
    sql::execute( $openprint::log, $openprint::dbh, q{DELETE FROM tbl_Material_Prices WHERE lngListIndex=?}, $$self{id} );
    sql::execute( $openprint::log, $openprint::dbh, q{DELETE FROM Paper_Prices WHERE lngListIndex=?}, $$self{id} ) if @PaperPrices;
    sql::execute( $openprint::log, $openprint::dbh, q{DELETE FROM Product_Prices WHERE pricelist_id=?}, $$self{id} );
	$self->SUPER::destroy();
	sql::end_transaction( $openprint::dbh, $ac );
	new openprint::Log()->save({action=>'Destroy', Object=>$self});
} # end sub delete

sub getPrices {
	my ( $self, $type ) = @_;

	my @prices;
	if ( ( ! $type ) or $type eq 'Material' ) {
		my @indexes = sql::execute( $openprint::log, $openprint::dbh, q{SELECT id FROM tbl_Material_Prices WHERE lngListIndex=?}, $$self{'id'} );
		while ( @indexes ) {
			push @prices, new openprint::MaterialPrice( shift @indexes );
		} # end while
	} # end if

	if ( ( ! $type ) or $type eq 'Service' ) {
		my @indexes = sql::execute( $openprint::log, $openprint::dbh, q{SELECT id FROM Service_Prices WHERE pricelist_id=?}, $$self{'id'} );
		while ( @indexes ) {
			push @prices, new openprint::ServicePrice( shift @indexes );
		} # end while
	} # end if
	if ( ( ! $type ) or $type eq 'Paper' ) {
		push @prices, openprint::PaperPrice->find( 'pricelist_id'=>$$self{'id'} );
	} # end if
	if ( ( ! $type ) or $type eq 'Product' ) {
		my @indexes = sql::execute( undef, undef, q{SELECT id FROM Product_Prices WHERE pricelist_id=?}, $$self{'id'} );
		while ( @indexes ) {
			push @prices, new openprint::ProductPrice( shift @indexes );
		} # end while
	} # end if
	return @prices;
	
} # end sub getPrices

sub Next {
	my $self = shift;
	my $New;
	if ( $$self{'id'} ) {
		$New = new openprint::Pricelist( sql::execute( undef, undef, q{SELECT MIN(id) FROM pricelists WHERE id > ?}, $$self{'id'} ) );
		if ( ! $New->id() ) {
			$New = new openprint::Pricelist( sql::execute( undef, undef, q{SELECT MAX(id) FROM Pricelists WHERE id <=?},  $$self{'id'} ) );
		} # end if
	} else { 
		$New = new openprint::Pricelist( sql::execute( undef, undef, q{SELECT MIN(id) FROM pricelists} ) );
	} # end if
	return $New;
} # end sub next
sub Previous {
	my $self = shift;
	my $New;
	if ( $$self{'id'} ) {
		$New = new openprint::Pricelist( sql::execute( undef, undef, q{SELECT MAX(Id) FROM pricelists WHERE Id < ?}, $$self{'id'} ) );
		if ( ! $New->id() ) {
			$New = new openprint::Pricelist( sql::execute( $openprint::log, $openprint::dbh, q{SELECT MIN(Id) FROM pricelists WHERE Id >=?},  $$self{'id'} ) );
		} # end if
	} else {
		$New = new openprint::Pricelist( sql::execute( $openprint::log, $openprint::dbh, q{SELECT MIN(Id) FROM pricelists} ) );
	} # end if
	return $New;
} # end sub prev

sub Currency {
	return new openprint::Currency( $_[0]{'currency_id'} );
} # end sub Currency

sub get_current {

	if ( $openprint::session{'Pricelist_id'} ) {
		# Validity of session variables is the job of openprint.pm, so it is done once per hit
		return new openprint::Pricelist( $openprint::session{'Pricelist_id'} );
	} # end if

	my $list_id;

	if ( $openprint::Company ) {
    if ( $openprint::Company->pricelist_id() ) {
      $list_id = $openprint::Company->pricelist_id();
    } elsif ( $openprint::Company->country() ) {
      $list_id = $openprint::config{'Default'.$openprint::Company->country().'Pricelist'};
    }
	} # end if

	if ( (! $list_id) and $openprint::session{'Country'} ) {
		$list_id = $openprint::config{'Default'.$openprint::session{'Country'}.'Pricelist'};
	} # end if
	if ( ! $list_id ) {
		$list_id = $openprint::config{'DefaultPricelist'};
	} # end if
	if ( (! $list_id) and $openprint::session{'Country'} ) {
		$openprint::log->debug("No pricelist to be had! Country: $openprint::session{'Country'}" );
    my @pricelists = openprint::Pricelist->find();
    if (@pricelists == 1) {
      $openprint::session{'Pricelist_id'} = $pricelists[0]->id();
      return $pricelists[0];
    }
	} # end if
	
	$openprint::session{'Pricelist_id'} = $list_id;
	return new openprint::Pricelist( $list_id );
} # end sub get_current

sub url_to {
  my $self = shift;
  return '/administrator/production/pricelists.html?ddmPriceList='.$$self{id};
}

sub link_to {
  my $self = shift;
  if ($openprint::User{type} eq 'A') {
    return '<a href="'.$self->url_to().'">'.($_[0] ? $_[0] : $self->name()).'</a>';
  } else {
    return ($_[0] ? $_[0] : $self->name());
  }
}

1;
__END__
