use strict;
package openprint::Manifest;
our @ISA = qw(openprint::Object);
require openprint::Object;

use openprint ();
use vars qw( $debug $table $serial %find_fields %fields %transforms %defaults );

require sql;
require openprint::Manifest_Content_Type;
require openprint::ManifestContent;
require openprint::PurchaseOrder;

$table = 'manifests';
$serial = 'manifests_id_seq';

$debug = 0;

%fields = (
		id					=>	'id',
		name				=>	'name',
		created_on	=>	'created_on',
		updated_on	=>	'updated_on',
		received_on	=>	'received_on',
		supplier_id	=>	'supplier_id',
		deleted			=>	'deleted',
		currency_id	=>	'currency_id',
		);

%find_fields = (
		docket						=>	'(SELECT docket FROM Manifest_Content_Types WHERE manifest_id=manifests.id)',
		po_id							=>	'(SELECT po_id FROM Manifest_Content_Types WHERE manifest_id=manifests.id)',
		skid_id						=>	'(SELECT skid_id FROM ManifestContents WHERE manifest_id=manifests.id)',
		rfidtag_id				=>	'(SELECT rfidtag_id FROM ManifestContents WHERE manifest_id=manifests.id)',
		manufacturers_id	=>	'(SELECT manufacturers_id FROM ManifestContents WHERE manifest_id=manifests.id)',
		type							=>	'(SELECT type from Manifest_Content_Types WHERE manifest_id=manifests.id)',
		po_unconfirmed_type_ids	=>	'(SELECT id FROM Manifest_Content_Types WHERE manifest_id=manifests.id AND po_content_id is NULL)',
		);

%transforms = (
		name				=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
		updated_on	=>	[ 's/.*//g' ],
		supplier_id	=>	[ 's/\D//g' ],
		);

%defaults = (
		created_on	=>	q`'NOW()'`,
		updated_on	=>	q`'NOW()'`,
		received_on	=>	q`'NOW()'`,
		supplier_id	=>	undef,
		currency_id	=>	undef,
		deleted	=>	0,
		);

sub destroy {
	my $self = shift;
	my $ac = sql::start_transaction( $openprint::dbh );
	foreach my $PO ( openprint::PurchaseOrder->find('manifest_id'=>$$self{id}) ) {
		$PO->save({'manifest_id'=>undef});
	} # end foreach $PO
	foreach my $C ( $self->Contents() ) {
		$C->delete();
	} # end foreach Content
	foreach my $T ( $self->Types() ) {
		$T->delete();
	} # end foreach Type

	sql::execute( undef, undef, q{DELETE FROM Manifests WHERE id=?}, $$self{id} );
	sql::end_transaction( $openprint::dbh, $ac );
	return $openprint::dbh->errstr() if $openprint::dbh->errstr();
	delete $openprint::Object::cache{'openprint::Manifest'}{$$self{id}};
	return '';
} # end sub destroy

sub Types {
	my ( $self, %params ) = @_;
	if ( $$self{id} and ! $_[0]{Types} ) {
		$_[0]{Types} = [ openprint::Manifest_Content_Type->find( manifest_id=>$$self{id}, order=>'id' ) ];
	}
	if ( %params ) {
		my @results;
TYPE: foreach my $Type ( @{$$self{Types}} ) {
				foreach my $key ( keys %params ) {
					next TYPE if $$Type{$key} ne $params{$key};
				}
				push @results, $Type;
			}
			return @results;
	} # end if
	return @{$$self{Types}} if $$self{Types};
	return;
} # end sub Types

sub Contents {
	my ( $self, %params ) = @_;
	if ( ( @_ == 2 ) and ( ref $_[1] eq 'ARRAY' ) ) {
		$$self{Contents} = $_[1];
	} elsif ( %params ) {
		if ( $$self{id} ) {
			return openprint::ManifestContent->find( manifest_id=>$$self{id}, %params );
		} # end if
	} # end if
	if ( ! $$self{Contents} ) {
		if ( $$self{id} ) {
			@{$$self{Contents}} = openprint::ManifestContent->find( manifest_id=>$$self{id} );
		} # end if
	} # end if
	return @{$$self{Contents}} if $$self{Contents};
	return;
} # end sub Contents

sub Vendor {
	require openprint::Company;
	return new openprint::Company( $_[0]{supplier_id} );
} # end sub Vendor

sub po_ids {
	return sets::union( map { $_->po_id() } $_[0]->Types() );
} # end sub po_ids
sub dockets {
	return sets::union( map { $_->docket() } $_[0]->Types() );
} # end sub dockets

sub link_to {
	return '<a href="/employee/inventory/manifest_view.html?manifest_id='.$_[0]{id}.'">'.$_[0]{name}.'</a>' if $_[0]{id};
	return '';
} # end sub link_to

sub check {
	my ( $Manifest ) = @_;
	
	my @Contents = $Manifest->Contents();
	my %skid_ids;
	foreach ( @Contents ) {
		push @{$skid_ids{$$_{skid_id}}}, $_ if $$_{skid_id};
	} # end foreach
	my %manufacturer_ids;
	foreach ( @Contents ) {
		push @{$manufacturer_ids{$$_{manufacturers_id}}}, $_ if $$_{manufacturers_id};
	} # end foreach
	my $error;
	if ( ! $$Manifest{supplier_id} ) {
		$error .= 'No vendor supplied.<br/>';
	}
	if ( keys %skid_ids != @Contents ) {
		foreach my $id ( keys %skid_ids ) {
			if ( @{$skid_ids{$id}} > 1 ) {
				$error .= "Skid $id is listed " . @{$skid_ids{$id}} . ' times<br/>';
			} # end if
		} # end foreach skid
	} # end if skid_ids duplicated
	my @mfg_ids = keys %manufacturer_ids;

	if ( @mfg_ids != @Contents ) {
		foreach my $id ( @mfg_ids ) {
			if ( @{$manufacturer_ids{$id}} > 1 ) {
				$error .= "Manufacturers $id is listed " . @{$manufacturer_ids{$id}} . ' times<br/>';
			} # end if
		} # end foreach manufacturer
	} # end if skid_ids duplicated
	foreach my $C ( @Contents ) {
		$error .= $C->check();
	} # end foreach C
	foreach my $T ( $Manifest->Types() ) {
		$error .= $T->check();
	}
	return $error;
} # end sub check

sub can_edit {
	return 1 if ! $_[0]{id};
	return 1 if $openprint::session{user_type} eq 'A';
	return 1 if $openprint::session{user_id} == $_[0]{created_by};
	return 1 if openprint::usergroup::is_user_in( ['Inventory','InventoryManager'], $openprint::session{user_id} );
	return 0;
} # end sub can_edit

sub can_see_pricing {
	return 1 if $openprint::session{user_type} eq 'A';
	return 1 if openprint::usergroup::is_user_in( ['Accounting','InventoryManager'], $openprint::session{user_id} );
	return 0;
} # end sub can_see_pricing

sub Currency {
	return new openprint::Currency( $_[0]{currency_id} );
}

1;
__END__
